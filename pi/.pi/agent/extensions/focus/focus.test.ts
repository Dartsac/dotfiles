import assert from "node:assert/strict";
import { copyFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";
import { AssistantMessageComponent, initTheme, ToolExecutionComponent } from "@earendil-works/pi-coding-agent";
import focus from "./index.ts";

initTheme("dark");

// The extension keeps its on/off state on globalThis so it survives /reload; reset it between tests.
const state = () => (globalThis as any)[Symbol.for("pi-focus-extension.state")];
test.beforeEach(() => { state().focusOn = false; });

/** Load the extension the way pi does and return its `/focus` command. */
function load(factory: typeof focus = focus) {
  const statuses: (string | undefined)[] = [];
  let command: (args: string, ctx: unknown) => Promise<void>;
  factory({ on() {}, registerCommand: (_name: string, options: any) => { command = options.handler; } } as any);
  const ctx = {
    hasUI: true,
    ui: { theme: { fg: (_color: string, text: string) => text }, setStatus: (_id: string, text?: string) => statuses.push(text), notify() {}, setWidget() {} },
  };
  return { statuses, toggle: () => command("", ctx) };
}

const plain = (lines: string[]) => lines.join("\n").replace(/\x1b\][^\x07]*\x07|\x1b\[[0-9;]*m/g, "");

function reply() {
  return new AssistantMessageComponent({
    role: "assistant",
    content: [{ type: "thinking", thinking: "SECRET THOUGHTS" }, { type: "text", text: "The reply." }],
    stopReason: "stop",
  } as any);
}

function tool(name: string, result?: { text: string; isError: boolean }) {
  const component = new ToolExecutionComponent(name, "call-1", { command: "echo hi" }, {}, undefined, { requestRender() {} } as any, process.cwd());
  if (result) component.updateResult({ content: [{ type: "text", text: result.text }], isError: result.isError });
  return component;
}

test("focus hides thinking and keeps the reply; toggling again brings it back", async () => {
  const { toggle } = load();
  const message = reply();
  assert.match(plain(message.render(80)), /SECRET THOUGHTS/);

  await toggle();
  assert.doesNotMatch(plain(message.render(80)), /SECRET THOUGHTS/);
  assert.match(plain(message.render(80)), /The reply\./);

  await toggle();
  assert.match(plain(message.render(80)), /SECRET THOUGHTS/);
});

test("a reply that arrived while focus was on gets its thinking back", async () => {
  const { toggle } = load();
  await toggle();
  const message = reply();
  assert.doesNotMatch(plain(message.render(80)), /SECRET THOUGHTS/);
  await toggle();
  assert.match(plain(message.render(80)), /SECRET THOUGHTS/);
});

test("focus hides a successful tool call and shows it again when off", async () => {
  const { toggle } = load();
  const call = tool("bash", { text: "TOOL OUTPUT", isError: false });
  assert.match(plain(call.render(80)), /TOOL OUTPUT/);
  await toggle();
  assert.deepEqual(call.render(80), []);
  await toggle();
  assert.match(plain(call.render(80)), /TOOL OUTPUT/);
});

test("a failed tool call stays visible in focus", async () => {
  const { toggle } = load();
  await toggle();
  // pi also reports an aborted or errored turn as an error result on the tool call.
  assert.match(plain(tool("bash", { text: "Operation aborted", isError: true }).render(80)), /Operation aborted/);
});

test("subagent and question cards stay visible in focus", async () => {
  const { toggle } = load();
  await toggle();
  for (const name of ["subagent", "subagent_supervisor", "ask_user_question"]) {
    assert.notDeepEqual(tool(name, { text: "CARD", isError: false }).render(80), [], name);
  }
});

test("the footer status follows the toggle", async () => {
  const { toggle, statuses } = load();
  await toggle();
  assert.equal(statuses.at(-1), "◎ focus");
  await toggle();
  assert.equal(statuses.at(-1), undefined);
});

test("/reload does not wrap pi's components twice, and the new load takes over", async (t) => {
  load();
  const updateContent = AssistantMessageComponent.prototype.updateContent;
  const render = ToolExecutionComponent.prototype.render;
  const hooks = state().hooks;

  // pi evaluates the file again on /reload. A copy at another path is evaluated fresh the same way.
  const dir = mkdtempSync(join(tmpdir(), "focus-reload-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  copyFileSync(fileURLToPath(new URL("./index.ts", import.meta.url)), join(dir, "index.ts"));
  const reloaded = load((await import(pathToFileURL(join(dir, "index.ts")).href)).default);
  assert.equal(AssistantMessageComponent.prototype.updateContent, updateContent);
  assert.equal(ToolExecutionComponent.prototype.render, render);
  assert.notEqual(state().hooks, hooks, "the reloaded file's behavior replaces the old one");

  const message = reply();
  await reloaded.toggle();
  assert.doesNotMatch(plain(message.render(80)), /SECRET THOUGHTS/);
  assert.deepEqual(tool("bash", { text: "TOOL OUTPUT", isError: false }).render(80), []);
});
