import assert from "node:assert/strict";
import { test } from "node:test";
import { stripVTControlCharacters } from "node:util";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { visibleWidth } from "@earendil-works/pi-tui";
import compactFooter from "./index.ts";

type Footer = { render(width: number): string[] };

/**
 * The footer a running pi shows: the extension loaded into a TUI session on Claude Opus,
 * thinking high, in a session named crystal-business, with pi-usage's and pi-rewind's statuses.
 */
function footer(statuses: Record<string, string> = {}, provider = "anthropic"): Footer {
  const handlers = new Map<string, Function>();
  compactFooter({
    on: (name: string, handler: Function) => handlers.set(name, handler),
    registerCommand: () => {},
    getThinkingLevel: () => "high",
  } as unknown as ExtensionAPI);
  let factory: Function | undefined;
  const ctx = {
    mode: "tui",
    cwd: "/tmp/crystal",
    model: { provider, id: "claude-opus-5-5", reasoning: true, cost: { input: 5, output: 25 } },
    getContextUsage: () => ({ percent: 12 }),
    sessionManager: {
      getEntries: () => [{ type: "usage", provider, usage: { cost: { total: 0.4321 } } }],
      getSessionName: () => "crystal-business",
    },
    ui: { setFooter: (f: Function) => { factory = f; }, notify: () => {} },
  };
  handlers.get("session_start")!({}, ctx);
  const theme = { fg: (_color: string, text: string) => text };
  const footerData = {
    onBranchChange: () => () => {},
    getExtensionStatuses: () => new Map(Object.entries({
      "pi-usage": "⚡ Claude:2%/24m,76%/2.1d",
      rewind: "◆ 1 checkpoint",
      ...statuses,
    })),
  };
  return factory!({ requestRender() {} }, theme, footerData);
}

test("a phone-width footer fits every piece on two lines, leaving the session name to Herdr's tab", () => {
  assert.deepEqual(footer().render(45), [
    "5h 2% 24m · 7d 76% 2d 2h · ctx 12%",
    "claude-opus-5-5 high                      ↺ 1",
  ]);
});

test("a desk-width footer keeps its bars, labels, provider and folder", () => {
  assert.deepEqual(footer().render(120), [
    "5h: ░░░░░░░░ 2% reset 24m | 7d: ██████░░ 76% reset 2d 2h | ctx: ░░░░░░░░ 12%",
    `[crystal-business] · claude-opus-5-5 high (anthropic) · /tmp/crystal${" ".repeat(38)}↺ 1 checkpoint`,
  ]);
});

test("a 60-column desk split keeps the full footer", () => {
  assert.equal(stripVTControlCharacters(footer().render(60)[0]), "5h: ░░░░░░░░ 2% reset 24m | 7d: ██████░░ 76% reset 2d 2h | …");
});

test("a phone-width footer shows the session's estimated cost where the provider has no quota", () => {
  assert.equal(footer({}, "google").render(45)[0], "cost $0.432 · ctx 12%");
});

test("no phone-width line is wider than the screen", () => {
  const lines = footer({ watchdog: "watchdog: 2 children running, 1 stalled for 4m" }).render(45);
  for (const line of lines) assert.ok(visibleWidth(line) <= 45, `${visibleWidth(line)} columns: ${line}`);
});
