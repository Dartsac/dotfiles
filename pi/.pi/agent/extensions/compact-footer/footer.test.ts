import assert from "node:assert/strict";
import { test } from "node:test";
import { stripVTControlCharacters } from "node:util";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { visibleWidth } from "@earendil-works/pi-tui";
import compactFooter from "./index.ts";

type Footer = { render(width: number): string[]; gitRuns: string[][] };

/** A folder in git: the branch Pi reports, and what `git status --porcelain=v2 --branch` prints there. */
type Git = { branch: string; status: string };

/**
 * The footer a running pi shows: the extension loaded into a TUI session on Claude Opus,
 * thinking high, in a session named crystal-business, with pi-usage's and pi-rewind's statuses,
 * in a folder outside git unless `git` says otherwise.
 */
function footer(statuses: Record<string, string> = {}, provider = "anthropic", git?: Git): Footer {
  const handlers = new Map<string, Function>();
  const gitRuns: string[][] = [];
  compactFooter({
    on: (name: string, handler: Function) => handlers.set(name, handler),
    registerCommand: () => {},
    getThinkingLevel: () => "high",
    exec: async (command: string, args: string[]) => {
      gitRuns.push([command, ...args]);
      return git ? { stdout: git.status, stderr: "", code: 0 } : { stdout: "", stderr: "fatal: not a git repository", code: 128 };
    },
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
    getGitBranch: () => git?.branch ?? null,
    getExtensionStatuses: () => new Map(Object.entries({
      "pi-usage": "⚡ Claude:2%/24m,76%/2.1d",
      rewind: "◆ 1 checkpoint",
      ...statuses,
    })),
  };
  const component = factory!({ requestRender() {} }, theme, footerData);
  return { render: (width: number) => component.render(width), gitRuns };
}

/** Lets a `git status` the footer started finish. */
const settle = () => new Promise(resolve => setImmediate(resolve));

const job: Git = {
  branch: "herdr-phone-screen-size",
  status: [
    "# branch.oid 8e2514e",
    "# branch.head herdr-phone-screen-size",
    "# branch.upstream origin/herdr-phone-screen-size",
    "# branch.ab +1 -0",
    "1 .M N... 100644 100644 100644 aaa aaa pi/index.ts",
    "1 M. N... 100644 100644 100644 aaa bbb pi/README.md",
    "1 MM N... 100644 100644 100644 aaa bbb pi/footer.test.ts",
    "1 .D N... 100644 100644 000000 aaa aaa old.txt",
    "1 A. N... 000000 100644 100644 000 ccc new.ts",
    "? notes.md",
    "",
  ].join("\n"),
};

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

test("a phone-width footer in git adds a line with the branch and what changed in it", async () => {
  const phone = footer({}, "anthropic", job);
  assert.equal(phone.render(45)[2], "⎇ herdr-phone-screen-size");
  await settle();
  assert.deepEqual(phone.render(45), [
    "5h 2% 24m · 7d 76% 2d 2h · ctx 12%",
    "claude-opus-5-5 high                      ↺ 1",
    "⎇ herdr-phone-screen-size  +2 ~3 -1 ↑1",
  ]);
});

test("a clean branch's line is its name alone", async () => {
  const phone = footer({}, "anthropic", { branch: "main", status: "# branch.head main\n# branch.ab +0 -0\n" });
  phone.render(45);
  await settle();
  assert.equal(phone.render(45)[2], "⎇ main");
});

test("a branch behind its upstream, with a conflict, says so", async () => {
  const status = "# branch.head main\n# branch.ab +0 -3\nu UU N... 100644 100644 100644 100644 a b c both.txt\n";
  const phone = footer({}, "anthropic", { branch: "main", status });
  phone.render(45);
  await settle();
  assert.equal(phone.render(45)[2], "⎇ main  !1 ↓3");
});

test("a desk-width footer runs no git and adds no line", async () => {
  const desk = footer({}, "anthropic", job);
  assert.equal(desk.render(120).length, 2);
  await settle();
  assert.equal(desk.render(120).length, 2);
  assert.deepEqual(desk.gitRuns, []);
});

test("while Pi is idle, a change made elsewhere shows on the next git check", async (t) => {
  t.mock.timers.enable({ apis: ["setInterval", "Date"], now: 1_000_000 });
  const git = { branch: "main", status: "# branch.head main\n" };
  const phone = footer({}, "anthropic", git);
  phone.render(45);
  t.mock.timers.tick(10); // the first `git status` takes 10 ms
  await settle();
  git.status += "? notes.md\n";
  t.mock.timers.tick(4990); // the timer's first tick, 5 s after the footer started
  await settle();
  assert.equal(phone.render(45)[2], "⎇ main  +1");
});
