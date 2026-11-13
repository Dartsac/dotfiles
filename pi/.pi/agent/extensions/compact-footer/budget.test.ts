import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import compactFooter from "./index.ts";

type Notice = { message: string; type: string };

function agentDir(t: { after: (fn: () => void) => void }): string {
  const dir = mkdtempSync(join(tmpdir(), "compact-footer-"));
  const previous = process.env.PI_CODING_AGENT_DIR;
  process.env.PI_CODING_AGENT_DIR = dir;
  t.after(() => {
    if (previous === undefined) delete process.env.PI_CODING_AGENT_DIR;
    else process.env.PI_CODING_AGENT_DIR = previous;
    rmSync(dir, { recursive: true, force: true });
  });
  return dir;
}

/** One running pi: the extension loaded and its session started with `provider` selected. */
function startPi(provider: string) {
  const handlers = new Map<string, Function>();
  const commands = new Map<string, Function>();
  const notices: Notice[] = [];
  compactFooter({
    on: (name: string, handler: Function) => handlers.set(name, handler),
    registerCommand: (name: string, options: { handler: Function }) => commands.set(name, options.handler),
  } as unknown as ExtensionAPI);
  // Not "tui", so no footer is installed; budgets are read and saved all the same.
  const ctx = { mode: "rpc", model: { provider }, ui: { notify: (message: string, type: string) => notices.push({ message, type }) } };
  handlers.get("session_start")!({}, ctx);
  return { notices, footerBudget: (args: string) => commands.get("footer-budget")!(args, ctx) };
}

const saved = (dir: string) => JSON.parse(readFileSync(join(dir, "compact-footer.json"), "utf8")).sessionBudgetsUSD;

test("a budget saved by another running pi is kept", async (t) => {
  const dir = agentDir(t);
  const first = startPi("anthropic");
  const second = startPi("google");
  await first.footerBudget("5");
  await second.footerBudget("3");
  assert.deepEqual(saved(dir), { anthropic: 5, google: 3 });
});

test("off removes only the selected provider's budget", async (t) => {
  const dir = agentDir(t);
  writeFileSync(join(dir, "compact-footer.json"), JSON.stringify({ sessionBudgetsUSD: { anthropic: 5, google: 3 } }));
  await startPi("google").footerBudget("off");
  assert.deepEqual(saved(dir), { anthropic: 5 });
});

test("a config file that cannot be read is left as it is", async (t) => {
  const dir = agentDir(t);
  const broken = '{ "sessionBudgetsUSD": { "anthropic": 5, }';
  writeFileSync(join(dir, "compact-footer.json"), broken);
  const pi = startPi("google");
  await pi.footerBudget("3");
  assert.equal(readFileSync(join(dir, "compact-footer.json"), "utf8"), broken);
  assert.equal(pi.notices.at(-1)?.type, "error");
  assert.match(pi.notices.at(-1)!.message, /^Budget not saved/);
});
