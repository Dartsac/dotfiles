// Dotfiles-owned replacement for Herdr's Pi lifecycle reporter. The managed
// integration remains installed but is excluded in Pi settings: one authority
// for state, with pi-subagents retaining ownership of its summary metadata.
import { randomUUID } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Supervision, asyncRunsRoot, clean, hasChildIssue, pendingRequests, supervisorRoot } from "./supervision.mjs";
import { ChildTabs, isLive, scanChildren, viewerSessionRoots } from "./children.mjs";
import { request } from "./rpc.mjs";
import { TOPIC_ATTEMPTS, generateTopic, messageText } from "./topic.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const agentDir = () => process.env.PI_CODING_AGENT_DIR || path.join(os.homedir(), ".pi/agent");
// Session entry recording whether this task's children had failures, so a
// /reload doesn't forget a failure that pi-subagents already delivered.
const ISSUES_ENTRY = "dotfiles-herdr-child-issues";
// How long shutdown waits for a child-tab step in flight (tab create, viewer
// launch, tag: up to 5s + 5s + 1.5s), so it can't land after the next runtime starts.
const TAB_SHUTDOWN_MS = 12_000;

// Steer/stop in a child tab follow pi-subagents' own authority policy.
function viewerAuthority() {
  try {
    const policy = JSON.parse(fs.readFileSync(path.join(agentDir(), "extensions/subagent/config.json"), "utf8")).authorityPolicy ?? {};
    return { steer: (policy.steerRun ?? "auto") === "auto", stop: (policy.stopRun ?? "auto") === "auto" };
  } catch { return { steer: true, stop: true }; }
}

// pi-subagents' configured session folder, if any (also readable by viewers).
function defaultSessionDir() {
  try {
    const dir = JSON.parse(fs.readFileSync(path.join(agentDir(), "extensions/subagent/config.json"), "utf8")).defaultSessionDir;
    return typeof dir === "string" && dir ? dir.replace(/^~(?=$|\/)/, os.homedir()) : undefined;
  } catch { return undefined; }
}

// The node that runs pi-subagents' viewer in a child tab.
// The pi-coding-agent package of the running Pi, so a child tab's viewer draws
// with the same Pi version's components. Undefined falls back to the old viewer.
export function piPackageRoot(entry = process.argv[1]) {
  try {
    for (let dir = path.dirname(fs.realpathSync(entry)); dir !== path.dirname(dir); dir = path.dirname(dir)) {
      const manifest = path.join(dir, "package.json");
      if (fs.existsSync(manifest) && JSON.parse(fs.readFileSync(manifest, "utf8")).name === "@earendil-works/pi-coding-agent") return dir;
    }
  } catch { /* not started from a Pi install */ }
  return undefined;
}

function viewerNode() {
  const onPath = (process.env.PATH ?? "").split(path.delimiter).map(dir => path.join(dir, "node")).find(file => {
    try { fs.accessSync(file, fs.constants.X_OK); return true; } catch { return false; }
  });
  const node = /^node(\.exe)?$/.test(path.basename(process.execPath)) ? process.execPath : onPath;
  if (!node) throw new Error("node not found for the subagent viewer");
  return node;
}

export default function (pi) {
  const socket = process.env.HERDR_SOCKET_PATH;
  const pane = process.env.HERDR_PANE_ID;
  if (process.env.HERDR_ENV !== "1" || !socket || !pane) return;
  const policy = new Supervision();
  const instance = randomUUID();
  let ctx;
  let root = false;
  const humanTools = new Set();
  const subscriptions = [];
  let timer;
  let sessionId;
  let sessionRef = {};
  let seq = Date.now() * 1000;
  let signature = "";
  let lastState;
  let lastRefresh = 0;
  let queued;
  let draining;
  let parentError = false;
  const channels = supervisorRoot();
  const asyncRoot = asyncRunsRoot();
  const runner = path.join(agentDir(), "local-packages/pi-subagents/inspector-runner.mjs");
  let tabs;
  let syncing; // the tabs.sync() pass in flight
  function setChildIssues(value) {
    if (policy.childIssues === value) return;
    policy.childIssues = value;
    if (root) pi.appendEntry(ISSUES_ENTRY, { childIssues: value });
  }
  let sessionFile;
  // Session label (topic.mjs): asked for on a prompt, at most TOPIC_ATTEMPTS times.
  let topicTries = 0;
  let topicPending = false;
  let topicUnclear = false; // the last prompt didn't say what the work is: ask again with the reply
  let lastPrompt = "";
  let retitle = 0; // polls left that send the title again; the last one renames tabs
  let renamer; // herdr-automatic-rename's engine, looked up once
  const call = (method, params) => request(socket, method, params);
  const metadata = (tokens) => call("pane.report_metadata", {
    pane_id: pane, source: "dotfiles:supervision", agent: "pi",
    applies_to_source: "herdr:pi", tokens, ttl_ms: 120_000, seq: ++seq,
  });
  const identity = d => d.attention ? `${instance}:${d.attention}` : "";

  function publish(force = false) {
    if (!root) return;
    const d = policy.desired();
    const next = JSON.stringify(d);
    if (!force && signature === next) return;
    signature = next;
    queued = d;
    if (draining) return;
    draining = (async () => {
      while (queued && root) {
        const next = queued;
        queued = undefined;
        try {
          await metadata({ activity: clean(next.activity), "attention-id": identity(next) || null,
            "attention-title": next.title || null, "completion-title": next.completionTitle || null });
          if (!root) break;
          const latest = policy.desired();
          if (JSON.stringify(latest) !== JSON.stringify(next)) {
            queued = latest;
            continue; // Never announce a question answered during the API call.
          }
          // Metadata heartbeats must not create completion/state transitions.
          const stateKey = JSON.stringify([next.state, next.activity, identity(next)]);
          if (stateKey !== lastState) {
            await call("pane.report_agent", {
              pane_id: pane, source: "herdr:pi", agent: "pi", state: next.state,
              message: clean(next.activity), seq: ++seq, ...sessionRef,
            });
            lastState = stateKey;
          }
          // Herdr 0.9.5 plays NeedsAttention sounds even for an active pane.
          // Publish lifecycle state only: manual notifications would duplicate
          // the sound and cannot retract themselves when the question resolves.
          lastRefresh = Date.now();
          ctx?.ui.setStatus("herdr-supervision", undefined);
        } catch (error) {
          // Retry the latest projection on the next tick, never queue obsolete
          // transitions behind an unavailable server.
          signature = "";
          if (Date.now() - lastRefresh > 120_000) ctx?.ui.setStatus("herdr-supervision", "Herdr reporting unavailable");
        }
      }
    })().finally(() => {
      draining = undefined;
      if (queued && root) { signature = ""; publish(); }
    });
  }

  // Pi titles a named session "π - name - folder". herdr-automatic-rename names
  // the tab after the title, so send it without the folder: "pi:name".
  function showTopic() {
    const name = clean(pi.getSessionName(), 60);
    if (root && name) ctx?.ui.setTitle(`π - ${name}`);
  }
  // The plugin renames tabs on Herdr events, and a new terminal title isn't
  // one: the tab would keep its old name until you switched tabs or the agent
  // changed state. Run the plugin's naming pass directly, as its shell hooks do.
  async function renameTabs() {
    renamer ??= herdrCli(["plugin", "list", "--json"]).then(result => {
      const plugin = result?.plugins?.find(p => p.plugin_id === "herdr-automatic-rename" && p.enabled !== false);
      const engine = plugin?.plugin_root && path.join(plugin.plugin_root, "automatic-rename.sh");
      return engine && fs.existsSync(engine) ? engine : undefined;
    }).catch(() => undefined);
    const engine = await renamer;
    if (engine && root) await pi.exec("bash", [engine, "pane.agent_status_changed"], { timeout: 10_000 }).catch(() => {});
  }

  // Name an unnamed session after its work. A name you set with /name is kept.
  async function nameSession(context, reply) {
    if (!root || topicPending || topicTries >= TOPIC_ATTEMPTS || pi.getSessionName()) return;
    topicPending = true;
    topicTries++;
    const session = sessionId;
    try {
      const first = (context.sessionManager.getBranch?.() ?? []).find(e => e.type === "message" && e.message?.role === "user");
      const topic = await generateTopic(context, {
        folder: path.basename(context.cwd), first: messageText(first?.message) || lastPrompt, latest: lastPrompt, reply,
      });
      topicUnclear = !topic;
      if (topic && root && session === sessionId && !pi.getSessionName()) pi.setSessionName(topic);
    } catch {
      topicUnclear = true; // offline or no credentials: the tab stays "pi"
    } finally {
      topicPending = false;
    }
  }

  function poll() {
    if (!root) return;
    if (retitle > 0) {
      showTopic();
      if (--retitle === 0 && pi.getSessionName()) void renameTabs();
    }
    policy.requests = pendingRequests(channels, sessionId, policy.requests);
    const children = scanChildren(asyncRoot, [sessionFile, sessionId]);
    policy.setChildren(children.filter(c => isLive(c.state)).length);
    publish(Date.now() - lastRefresh >= 45_000);
    if (tabs && !syncing) {
      const wrapUp = policy.desired().state === "idle";
      syncing = tabs.sync(children, { waitingRunIds: new Set(policy.requests.flatMap(r => [r.runId, `${r.runId}#${r.childIndex}`])), wrapUp })
        .catch(() => {}).finally(() => { syncing = undefined; });
    }
  }

  async function herdrCli(args) {
    const bin = process.env.HERDR_BIN_PATH && fs.existsSync(process.env.HERDR_BIN_PATH) ? process.env.HERDR_BIN_PATH : "herdr";
    const result = await pi.exec(bin, args, { timeout: 5000, maxBuffer: 1_000_000 });
    if (result.code !== 0) throw new Error(result.stderr || `herdr ${args[0]} ${args[1]} failed`);
    return result.stdout.trim() ? JSON.parse(result.stdout).result : undefined;
  }

  async function startChildTabs(context) {
    if (!fs.existsSync(runner)) return; // pi-subagents not installed here
    const self = await call("pane.get", { pane_id: pane });
    const node = viewerNode();
    const piRoot = piPackageRoot();
    const authority = viewerAuthority();
    const sessionDir = defaultSessionDir();
    tabs = new ChildTabs({
      cli: herdrCli, rpc: call, workspace: self.pane.workspace_id, parentPane: pane, cwd: context.cwd,
      viewer: {
        launcher: path.join(HERE, "subagent-view.sh"),
        env: child => ({
          PI_SUBAGENT_VIEW_NODE: node, PI_SUBAGENT_VIEW_RUNNER: runner,
          PI_SUBAGENT_VIEW_ASYNC_DIR: child.asyncDir, PI_SUBAGENT_VIEW_RUN_ID: child.runId,
          PI_SUBAGENT_VIEW_INDEX: child.key.includes("#") ? String(child.index) : "",
          PI_SUBAGENT_VIEW_ROOTS: Buffer.from(JSON.stringify(viewerSessionRoots(child, sessionFile, sessionDir))).toString("base64"),
          PI_SUBAGENT_VIEW_STEER: String(authority.steer), PI_SUBAGENT_VIEW_STOP: String(authority.stop),
          PI_SUBAGENT_VIEW_TITLE: child.title || child.name,
          PI_SUBAGENT_VIEW_NAME: child.name,
          PI_SUBAGENT_VIEW_PI_ROOT: piRoot ?? "",
        }),
      },
    });
    tabs.adopt((await call("session.snapshot", {})).snapshot);
  }

  // Capture restored overlays even if pi-subagents' session_start handler runs
  // before ours. Headless children never reach the TUI-only activation below.
  subscriptions.push(pi.events.on("herdr:busy", data => { policy.setBusy(data?.active === true); publish(); }));
  for (const name of ["subagent:async-complete", "subagent:foreground-complete"]) {
    subscriptions.push(pi.events.on(name, data => {
      if (hasChildIssue(data)) setChildIssues(true);
      publish();
    }));
  }
  pi.on("before_agent_start", (event, context) => {
    if (event.messageType === "user" && !policy.busy && !policy.wrappingUp()) setChildIssues(false);
    if (event.messageType === "user" && typeof event.prompt === "string") {
      lastPrompt = event.prompt;
      void nameSession(context); // not awaited: never delays the turn
    }
  });
  // Pi has rewritten its title by the time this arrives. The next poll sends
  // ours once more and renames the tab.
  pi.on("session_info_changed", () => {
    if (!root) return;
    showTopic();
    retitle = 1;
  });
  // Deliberately do not map generic herdr:blocked notices to human attention:
  // pi-subagents uses those for parent-addressed coordination and slow tools.
  subscriptions.push(pi.events.on("rpiv:ask-user:blocked", data => {
    if (!root) return;
    policy.setHuman("questionnaire", data?.active === true);
    publish();
  }));
  pi.on("tool_execution_start", event => {
    if (event.toolName === "ask_user_question" || event.toolName === "quiz") humanTools.add(event.toolCallId);
  });
  pi.on("ui_prompt_start", event => {
    // A fleet inspector is also custom UI, but isn't a question. The known
    // questionnaire/quiz tools have lifecycle coverage; ordinary native
    // confirm/select/input/editor dialogs are human prompts in their own right.
    if (!root || !policy.parentActive || (event.kind === "custom" && humanTools.size === 0)) return;
    policy.setHuman("ui", true);
    publish();
  });
  pi.on("ui_prompt_end", () => {
    if (!root) return;
    policy.setHuman("ui", false);
    publish();
  });
  pi.on("session_start", async (_event, context) => {
    if (context.mode !== "tui") return;
    // Refuse competing state authorities if setup was skipped or undone.
    if (!pi.getSettings().extensions?.includes("-extensions/herdr-agent-state.ts")) {
      context.ui.notify("Herdr supervision not enabled: run ~/.config/herdr/scripts/install-pi-supervision.py, then /reload", "warning");
      return;
    }
    ctx = context;
    sessionId = context.sessionManager.getSessionId();
    const file = context.sessionManager.getSessionFile();
    sessionFile = file;
    sessionRef = file ? { agent_session_path: file } : { agent_session_id: sessionId };
    // Restore this task's child failures from the session, then record any that
    // arrived during startup (pi-subagents can deliver before this handler runs).
    const arrived = policy.childIssues;
    policy.childIssues = (context.sessionManager.getBranch?.() ?? [])
      .filter(e => e.type === "custom" && e.customType === ISSUES_ENTRY).at(-1)?.data?.childIssues === true;
    root = true;
    if (arrived) setChildIssues(true);
    policy.parentActive = !context.isIdle();
    // A unique attention identity prevents a reloaded runtime's first question
    // from colliding with a dismissed question in the same terminal.
    await call("pane.report_agent_session", {
      pane_id: pane, source: "herdr:pi", agent: "pi", seq: ++seq,
      session_start_source: _event.reason, ...sessionRef,
    }).catch(() => {});
    await startChildTabs(context).catch(() => {
      context.ui.notify("Herdr child tabs unavailable this session", "warning");
    });
    // Pi sets its own title once more after a session loads, at a moment no
    // event marks: send ours on the next few polls.
    retitle = 3;
    // A reloaded or resumed session that already has a conversation is named
    // from it now, rather than at its next prompt.
    const messages = (context.sessionManager.getBranch?.() ?? []).filter(e => e.type === "message").map(e => e.message);
    lastPrompt = messageText(messages.findLast(m => m?.role === "user"));
    if (lastPrompt) void nameSession(context, messageText(messages.findLast(m => m?.role === "assistant")));
    poll();
    timer = setInterval(poll, 1000);
    timer.unref?.();
  });
  pi.on("agent_start", () => {
    if (!root) return;
    parentError = false;
    policy.start();
    showTopic();
    poll();
  });
  pi.on("message_end", event => {
    if (root && event.message.role === "assistant") parentError = event.message.stopReason === "error";
  });
  pi.on("agent_settled", (event, context) => {
    if (!root || !context.isIdle()) return;
    policy.settled({ aborted: event.aborted, error: parentError, pending: context.hasPendingMessages() });
    if (topicUnclear && !event.aborted && !parentError) {
      const reply = (context.sessionManager.getBranch?.() ?? []).findLast(e => e.type === "message" && e.message?.role === "assistant");
      void nameSession(context, messageText(reply?.message));
    }
    poll();
  });
  pi.on("tool_execution_end", event => {
    humanTools.delete(event.toolCallId);
    if (!root) return;
    if (event.toolName === "ask_user_question") policy.setHuman("questionnaire", false);
    poll();
  });
  pi.on("session_shutdown", async () => {
    for (const unsubscribe of subscriptions) unsubscribe();
    if (!root) return;
    root = false;
    // Child tabs stay open; the next runtime adopts them. Finish a tab step in
    // flight first, so its tag lands before that runtime looks, then go silent.
    const closing = tabs;
    tabs = undefined;
    closing?.stop();
    clearInterval(timer);
    queued = undefined;
    const tabStep = syncing && new Promise(resolve => {
      const timeout = setTimeout(resolve, TAB_SHUTDOWN_MS);
      timeout.unref?.();
      syncing.finally(() => { clearTimeout(timeout); resolve(); });
    });
    await Promise.all([draining, tabStep]);
    closing?.halt();
    await metadata({ activity: null, "attention-id": null, "attention-title": null, "completion-title": null }).catch(() => {});
  });

  pi.registerShortcut("ctrl+shift+a", {
    description: "Inspect this session's subagent fleet (no model turn)",
    handler: async context => {
      if (context.mode !== "tui") return;
      if (!pi.getCommands().some(c => c.name === "subagents-fleet" && c.source === "extension")) {
        context.ui.notify("Fleet inspector unavailable; enable pi-subagents", "warning");
        return;
      }
      // Pi dispatches registered extension commands before its streaming
      // check. Never use deliverAs: that would queue text to the model.
      pi.sendUserMessage("/subagents-fleet", { expandPromptTemplates: true });
    },
  });
}
