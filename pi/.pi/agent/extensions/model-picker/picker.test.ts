import assert from "node:assert/strict";
import test from "node:test";
import picker from "./index.ts";
import { matchesKey, visibleWidth } from "@earendil-works/pi-tui";

const model = (id: string, reasoning = true) => ({
  id, provider: "test", name: id, reasoning,
  thinkingLevelMap: { xhigh: null, max: null },
});

function harness(options: Record<string, any> = {}) {
  const models = options.models ?? [model("alpha"), model("beta")];
  const changes: any[] = [];
  const notices: string[] = [];
  const shortcuts = new Map();
  const commands = new Map();
  let level = "high";
  let component: any;
  const theme = { fg: (_color: string, text: string) => text, bold: (text: string) => text };
  const pi: any = {
    getThinkingLevel: () => level,
    setThinkingLevel: (next: string) => { level = next; changes.push(["thinking", next]); },
    setModel: async (next: any) => { if (options.auth === false) return false; changes.push(["model", next.id]); return true; },
    registerShortcut: (key: string, entry: any) => shortcuts.set(key, entry.handler),
    registerCommand: (name: string, entry: any) => commands.set(name, entry.handler), on() {},
  };
  const keys: Record<string, string> = {
    "tui.select.confirm": "enter", "tui.select.cancel": "esc",
    "tui.select.up": "up", "tui.select.down": "down",
    "tui.select.pageUp": "pageUp", "tui.select.pageDown": "pageDown", "tui.input.tab": "tab",
  };
  const ctx: any = {
    mode: options.mode ?? "tui", isIdle: () => options.busy !== true,
    model: options.current ?? models[0], scopedModels: options.scoped ?? [],
    modelRegistry: { getAvailable: () => models },
    ui: {
      notify: (text: string) => notices.push(text),
      custom: (factory: any) => new Promise(resolve => {
        component = factory({ requestRender() {} }, theme, { matches: (data: string, action: string) => keys[action] === data }, resolve);
        component.focused = true;
        for (const width of [1, 20, 80, 160]) assert.ok(component.render(width).every((line: string) => visibleWidth(line) <= width));
        for (const key of options.keys ?? []) component.handleInput(key);
      }),
    },
  };
  picker(pi);
  return { changes, notices, shortcuts, commands, run: () => shortcuts.get("ctrl+shift+alt+m")(ctx), get component() { return component; } };
}

test("Command+M bridge and slash command are the only registered picker routes", () => {
  const h = harness();
  assert.deepEqual([...h.shortcuts.keys()], ["ctrl+shift+alt+m"]);
  assert.deepEqual([...h.commands.keys()], ["model-picker"]);
  assert.ok(matchesKey("\u001b[109;8u", "ctrl+shift+alt+m"));
  assert.equal(matchesKey("\u001bm", "ctrl+shift+alt+m"), false);
});

test("Command+M searches by model substring and applies only after both choices", async () => {
  const h = harness();
  const pending = h.run();
  h.component.handleInput("bet");
  assert.match(h.component.render(160).join("\n"), /test\/beta/);
  assert.doesNotMatch(h.component.render(160).join("\n"), /test\/alpha/);
  h.component.handleInput("enter");
  assert.deepEqual(h.changes, []);
  h.component.handleInput("up");
  h.component.handleInput("enter");
  await pending;
  assert.deepEqual(h.changes, [["model", "beta"], ["thinking", "medium"]]);
});

test("search matches provider and display name", async () => {
  const h = harness({ keys: ["test bet", "enter", "enter"] });
  await h.run();
  assert.equal(h.changes[0][1], "beta");
});

for (const keys of [["esc"], ["down", "enter", "esc"]]) {
  test(`cancel leaves model and thinking unchanged: ${keys}`, async () => {
    const h = harness({ keys });
    await h.run();
    assert.deepEqual(h.changes, []);
  });
}

test("Tab returns to model selection without applying", async () => {
  const h = harness({ keys: ["down", "enter", "tab", "up", "enter", "enter"] });
  await h.run();
  assert.deepEqual(h.changes, [["model", "alpha"], ["thinking", "high"]]);
});

test("non-reasoning models offer only off", async () => {
  const h = harness({ models: [model("plain", false)], keys: ["enter", "enter"] });
  await h.run();
  assert.deepEqual(h.changes, [["model", "plain"], ["thinking", "off"]]);
});

test("scope limits models and supplies the initial thinking level", async () => {
  const beta = model("beta");
  const h = harness({ scoped: [{ model: beta, thinkingLevel: "low" }], keys: ["enter", "enter"] });
  await h.run();
  assert.deepEqual(h.changes, [["model", "beta"], ["thinking", "low"]]);
});

test("unsupported thinking levels are omitted", async () => {
  const h = harness();
  const pending = h.run();
  h.component.handleInput("enter");
  assert.doesNotMatch(h.component.render(160).join("\n"), /xhigh|maximum/i);
  h.component.handleInput("esc");
  await pending;
});

test("no matches cannot apply anything", async () => {
  const h = harness({ keys: ["not-a-model", "enter", "esc"] });
  await h.run();
  assert.deepEqual(h.changes, []);
});

test("unavailable scoped models do not leak outside the scope", async () => {
  const h = harness({ scoped: [{ model: model("missing") }] });
  await h.run();
  assert.equal(h.component, undefined);
  assert.match(h.notices[0], /No authenticated models/);
});

test("authentication failure does not change thinking", async () => {
  const h = harness({ auth: false, keys: ["enter", "enter"] });
  await h.run();
  assert.deepEqual(h.changes, []);
  assert.match(h.notices[0], /authentication/);
});

test("busy and non-TUI sessions never open a picker", async () => {
  for (const options of [{ busy: true }, { mode: "rpc" }, { mode: "print" }, { models: [] }]) {
    const h = harness(options);
    await h.run();
    assert.equal(h.component, undefined);
  }
});

test("an active picker cannot be opened again", async () => {
  const h = harness();
  const pending = h.run();
  const original = h.component;
  await h.run();
  assert.equal(h.component, original);
  h.component.handleInput("esc");
  await pending;
});

test("work starting while picker is open prevents stale application", async () => {
  const options = { busy: false };
  const h = harness(options);
  const pending = h.run();
  options.busy = true;
  h.component.handleInput("enter");
  h.component.handleInput("enter");
  await pending;
  assert.deepEqual(h.changes, []);
  assert.match(h.notices[0], /response started/);
});
