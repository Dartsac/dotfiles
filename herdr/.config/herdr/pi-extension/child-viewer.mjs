// Runs in a child's Herdr tab: the subagent's own Pi session, drawn with Pi's
// components (messages, tool calls, markdown) and redrawn by pi-tui, which only
// repaints changed lines. Children still run through pi-subagents; this only
// reads their session file and steers/stops them through pi-subagents' own
// control channel. Arguments arrive as PI_SUBAGENT_VIEW_* environment variables.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

const TICK_MS = 250;
const STATE_TEXT = { queued: "Queued", pending: "Queued", running: "Working", complete: "Finished", completed: "Finished", failed: "Failed", paused: "Paused", stopped: "Stopped" };
const BUILTIN_TOOLS = { read: "createReadToolDefinition", bash: "createBashToolDefinition", edit: "createEditToolDefinition",
  write: "createWriteToolDefinition", grep: "createGrepToolDefinition", find: "createFindToolDefinition", ls: "createLsToolDefinition" };

// New complete JSONL entries appended since the last read. Bytes, not text, are
// buffered across reads so a multi-byte character split by a write survives.
export class JsonlTail {
  constructor(file) { this.file = file; this.offset = 0; this.rest = Buffer.alloc(0); }
  read() {
    let fd;
    try { fd = fs.openSync(this.file, "r"); } catch { return []; }
    try {
      const size = fs.fstatSync(fd).size;
      if (size < this.offset) { this.offset = 0; this.rest = Buffer.alloc(0); } // rewritten
      if (size === this.offset) return [];
      const chunk = Buffer.alloc(size - this.offset);
      fs.readSync(fd, chunk, 0, chunk.length, this.offset);
      this.offset = size;
      let bytes = Buffer.concat([this.rest, chunk]);
      const entries = [];
      for (let nl = bytes.indexOf(10); nl >= 0; nl = bytes.indexOf(10)) {
        const line = bytes.subarray(0, nl).toString("utf8").trim();
        bytes = bytes.subarray(nl + 1);
        if (line) try { entries.push(JSON.parse(line)); } catch { /* a torn or foreign line */ }
      }
      this.rest = Buffer.from(bytes);
      return entries;
    } finally { fs.closeSync(fd); }
  }
}

// The session file pi-subagents recorded for this child, only if it lies inside
// one of the child's session roots (as pi-subagents' own inspector requires).
export function childSessionFile(status, index, roots) {
  const step = status?.steps?.[index ?? 0];
  const file = typeof step?.sessionFile === "string" ? path.resolve(step.sessionFile) : undefined;
  if (!file) return { file: undefined };
  const inside = roots.some(root => typeof root === "string" && root && file.startsWith(path.resolve(root) + path.sep));
  return inside ? { file } : { file: undefined, refused: file };
}

const duration = ms => {
  const s = Math.max(0, Math.round(ms / 1000));
  return s < 60 ? `${s}s` : s < 3600 ? `${Math.floor(s / 60)}m${String(s % 60).padStart(2, "0")}s` : `${Math.floor(s / 3600)}h${String(Math.floor(s / 60) % 60).padStart(2, "0")}m`;
};
const thousands = n => n >= 1000 ? `${Math.round(n / 1000)}k` : String(n);

// "Working · 3m12s · 41k tokens · gpt-6.1-sol" for the header's second line.
export function headerFacts(status, index, now = Date.now()) {
  const step = status?.steps?.[index ?? 0] ?? {};
  const state = step.status ?? status?.state ?? "queued";
  const facts = [STATE_TEXT[state] ?? state];
  if (typeof step.startedAt === "number") facts.push(duration((step.endedAt ?? now) - step.startedAt));
  const tokens = typeof step.tokens === "number" ? step.tokens : step.tokens?.total;
  if (tokens) facts.push(`${thousands(tokens)} tokens`);
  if (typeof step.model === "string") facts.push(step.model.replace(/^[^/]+\//, "").replace(/:[a-z]+$/, ""));
  return { state, text: facts.join(" · ") };
}

function userText(message) {
  if (typeof message.content === "string") return message.content;
  return (message.content ?? []).filter(part => part.type === "text").map(part => part.text).join("\n");
}

// Session entries -> Pi's chat components, as Pi's renderSessionItems does: a
// tool call shows as running until its toolResult entry arrives.
export class Transcript {
  constructor({ pi, tuiLib, ui, cwd, container, markdownTheme, hideThinking = false }) {
    Object.assign(this, { pi, tuiLib, ui, cwd, container, markdownTheme, hideThinking });
    this.pending = new Map();
    this.tools = [];
    this.definitions = new Map();
    this.expanded = false;
  }
  definition(name) {
    if (!this.definitions.has(name)) {
      const make = BUILTIN_TOOLS[name] && this.pi[BUILTIN_TOOLS[name]];
      let def;
      try { def = make ? make(this.cwd) : undefined; } catch { def = undefined; }
      this.definitions.set(name, def);
    }
    return this.definitions.get(name);
  }
  add(entry) {
    if (entry?.type === "message" && entry.message) this.message(entry.message);
    else if (entry?.type === "custom_message" && entry.display) {
      this.container.addChild(new this.pi.CustomMessageComponent(
        { role: "custom", customType: entry.customType, content: entry.content, display: true, details: entry.details, timestamp: entry.timestamp },
        undefined, this.markdownTheme));
    }
  }
  message(message) {
    const { pi, container } = this;
    if (message.role === "user") {
      const text = userText(message);
      if (!text) return;
      if (container.children.length) container.addChild(new this.tuiLib.Spacer(1));
      container.addChild(new pi.UserMessageComponent(text, this.markdownTheme));
    } else if (message.role === "assistant") {
      container.addChild(new pi.AssistantMessageComponent(message, this.hideThinking, this.markdownTheme));
      for (const part of message.content ?? []) {
        if (part.type !== "toolCall") continue;
        const tool = new pi.ToolExecutionComponent(part.name, part.id, part.arguments, { showImages: false },
          this.definition(part.name), this.ui, this.cwd);
        tool.setExpanded(this.expanded);
        container.addChild(tool);
        this.tools.push(tool);
        if (message.stopReason === "aborted" || message.stopReason === "error") {
          tool.updateResult({ content: [{ type: "text", text: message.stopReason === "aborted" ? "Operation aborted" : message.errorMessage || "Error" }], isError: true });
        } else this.pending.set(part.id, tool);
      }
    } else if (message.role === "toolResult") {
      const tool = this.pending.get(message.toolCallId);
      if (tool) { tool.updateResult(message); this.pending.delete(message.toolCallId); }
    }
  }
  toggleExpanded() {
    this.expanded = !this.expanded;
    for (const tool of this.tools) tool.setExpanded(this.expanded);
  }
}

// What a key does in the viewer. Pi asks for the kitty keyboard protocol, which
// also reports key releases (and repeats while held): without this filter every
// Ctrl-o toggled twice (press, release) and one Ctrl-c counted as a double press.
export function viewerKey(data, tuiLib, isExpandKey) {
  if (tuiLib.isKeyRelease(data) || tuiLib.isKeyRepeat(data)) return undefined;
  if (isExpandKey(data)) return "expand";
  if (tuiLib.matchesKey(data, "ctrl+c")) return "ctrl+c";
  return undefined;
}

// Ctrl-c on an empty input: the first press shows "press again"; the next press
// closes while that notice is still showing, however long the owner took to
// read it. The notice (and the arming) lapse after CLOSE_ARMED_MS.
export const CLOSE_ARMED_MS = 3000;
export class CloseGuard {
  armedUntil = 0;
  press(now = Date.now()) {
    if (now < this.armedUntil) return "close";
    this.armedUntil = now + CLOSE_ARMED_MS;
    return "arm";
  }
  armed(now = Date.now()) { return now < this.armedUntil; }
  reset() { this.armedUntil = 0; }
}

function readJson(file) { try { return JSON.parse(fs.readFileSync(file, "utf8")); } catch { return undefined; } }
const importFile = file => import(pathToFileURL(file).href);

async function main() {
  const env = process.env;
  const piRoot = env.PI_SUBAGENT_VIEW_PI_ROOT;
  if (!piRoot) throw new Error("PI_SUBAGENT_VIEW_PI_ROOT is not set");
  const pi = await importFile(path.join(piRoot, "dist/index.js"));
  const tuiLib = await importFile(path.join(piRoot, "../pi-tui/dist/index.js")); // the copy Pi itself uses
  const control = await importFile(path.join(path.dirname(env.PI_SUBAGENT_VIEW_RUNNER), "src/inspectors/inspector-runner.js"));

  const agentDir = env.PI_CODING_AGENT_DIR || path.join(os.homedir(), ".pi/agent");
  const settings = readJson(path.join(agentDir, "settings.json")) ?? {};
  pi.initTheme(settings.theme);
  const markdownTheme = pi.getMarkdownTheme();
  // Pi's app keybindings (with the owner's keybindings.json), so tool previews
  // say "ctrl+o to expand" and the expand key is whatever Pi uses. Not a public
  // export: without it the viewer keeps Ctrl-o and the hint loses its key name.
  let keybindings;
  try {
    const { KeybindingsManager } = await importFile(path.join(piRoot, "dist/core/keybindings.js"));
    keybindings = KeybindingsManager.create();
    tuiLib.setKeybindings(keybindings);
  } catch { keybindings = undefined; }
  const isExpandKey = data => keybindings ? keybindings.matches(data, "app.tools.expand") : tuiLib.matchesKey(data, "ctrl+o");

  const asyncDir = path.resolve(env.PI_SUBAGENT_VIEW_ASYNC_DIR);
  const index = env.PI_SUBAGENT_VIEW_INDEX ? Number(env.PI_SUBAGENT_VIEW_INDEX) : undefined;
  let roots = [];
  try { roots = JSON.parse(Buffer.from(env.PI_SUBAGENT_VIEW_ROOTS || "", "base64").toString("utf8")); } catch { roots = []; }
  const controlOptions = {
    asyncDir, runId: env.PI_SUBAGENT_VIEW_RUN_ID, ...(index !== undefined ? { index } : {}),
    sessionRoots: roots, refreshMs: 1500,
    allowSteer: env.PI_SUBAGENT_VIEW_STEER !== "false", allowStop: env.PI_SUBAGENT_VIEW_STOP !== "false",
  };
  const name = env.PI_SUBAGENT_VIEW_NAME || "subagent";
  const title = env.PI_SUBAGENT_VIEW_TITLE || "";

  // Pi's fullscreen layout (its default tuiMode): an alt screen whose transcript
  // scrolls (wheel, PgUp/PgDn) and follows the end, above a fixed input dock.
  // Here a fixed header (name, state) sits on top.
  const { TuiAltScreen, ProcessTerminal, Container, Text, Editor, ScrollView, VStack, matchesKey } = tuiLib;
  const ui = new TuiAltScreen(new ProcessTerminal(), false, undefined, {
    wheelScrollLines: "auto",
    scrollToEndIndicator: () => markdownTheme.bold(" \u2193 Jump to latest "),
  });
  const header = new Text("", 1, 0);
  const chat = new Container();
  const waiting = new Text(markdownTheme.quote("Waiting for the child's session to start..."), 1, 0);
  const notice = new Text("", 1, 0);
  // Pi doesn't export its editor theme; this is built from the parts it does export.
  const editor = new Editor(ui, { borderColor: markdownTheme.codeBlockBorder, selectList: pi.getSelectListTheme() });
  chat.addChild(waiting);
  const transcriptView = new ScrollView(chat, { follow: "end", primary: true, overscroll: "chain", scrollbar: "auto" });
  const dock = new VStack([
    { component: notice, shrink: 1, minSize: 0 },
    { component: editor, shrink: 1, minSize: 3 },
  ]);
  for (const part of [header, chat, notice, editor]) ui.addChild(part);
  ui.setLayoutRoot(new VStack([
    { component: header, basis: "auto", grow: 0, shrink: 0, minSize: 1 },
    { component: transcriptView, basis: 0, grow: 1, shrink: 1, minSize: 1 },
    { component: dock, basis: "auto", grow: 0, shrink: 1, minSize: 1 },
  ]));
  ui.setFocus(editor);

  let cwd = process.cwd();
  let transcript, tail, lastHeader = "";
  const expandKey = keybindings?.getKeys("app.tools.expand")?.join("/") || "ctrl+o";
  const hint = markdownTheme.linkUrl(`Enter steers · /stop stops · ${expandKey} tool output · ctrl+c twice closes`);
  const setNotice = text => { notice.setText(text ? `${text}\n${hint}` : hint); };
  setNotice("");

  const refresh = () => {
    const status = readJson(path.join(asyncDir, "status.json"));
    const facts = headerFacts(status, index);
    const next = `${markdownTheme.bold(name)}${title && title !== name ? `  ${title}` : ""}\n${markdownTheme.linkUrl(facts.text)}`;
    let changed = next !== lastHeader;
    if (changed) { header.setText(next); lastHeader = next; }
    if (!tail && status) {
      const found = childSessionFile(status, index, roots);
      if (found.refused) waiting.setText(markdownTheme.quote(`Not showing ${found.refused}: outside this run's session folder.`));
      if (found.file) {
        if (typeof status.cwd === "string") cwd = status.cwd;
        tail = new JsonlTail(found.file);
        transcript = new Transcript({ pi, tuiLib, ui, cwd, container: chat, markdownTheme, hideThinking: settings.hideThinkingBlock === true });
        chat.removeChild(waiting);
        changed = true;
      }
    }
    if (tail) {
      const entries = tail.read();
      for (const entry of entries) transcript.add(entry);
      changed ||= entries.length > 0;
    }
    if (changed) ui.requestRender();
  };

  editor.onSubmit = text => {
    const line = text.trim();
    editor.setText("");
    if (!line) return;
    editor.addToHistory?.(line);
    try { setNotice(control.submitInspectorControl(controlOptions, line === "/stop" ? "stop" : line)); }
    catch (error) { setNotice(`Not sent: ${error instanceof Error ? error.message : String(error)}`); }
    ui.requestRender();
  };

  const closeGuard = new CloseGuard();
  let closeNoticeTimer;
  const quit = () => { ui.stop(); process.exit(0); };
  ui.addInputListener(data => {
    // Swallow the release/repeat of our own keys so the editor never sees them.
    if ((tuiLib.isKeyRelease(data) || tuiLib.isKeyRepeat(data)) && (isExpandKey(data) || matchesKey(data, "ctrl+c"))) return { consume: true };
    const action = viewerKey(data, tuiLib, isExpandKey);
    if (action === "expand") {
      transcript?.toggleExpanded();
      ui.requestRender();
      return { consume: true };
    }
    if (action === "ctrl+c") {
      if (editor.getText()) { editor.setText(""); closeGuard.reset(); ui.requestRender(); return { consume: true }; }
      if (closeGuard.press() === "close") quit();
      setNotice("Press Ctrl-c again to close this tab (the child keeps running).");
      ui.requestRender();
      clearTimeout(closeNoticeTimer);
      closeNoticeTimer = setTimeout(() => {
        if (!closeGuard.armed()) { setNotice(""); ui.requestRender(); }
      }, CLOSE_ARMED_MS + 50);
      return { consume: true };
    }
    return undefined;
  });
  process.on("SIGTERM", quit);
  process.on("SIGHUP", quit);

  ui.start();
  refresh();
  setInterval(refresh, TICK_MS);
}

if (process.argv[1] && path.resolve(process.argv[1]) === new URL(import.meta.url).pathname) {
  main().catch(error => {
    process.stderr.write(`Child viewer failed: ${error instanceof Error ? error.stack : String(error)}\n`);
    process.exit(1);
  });
}
