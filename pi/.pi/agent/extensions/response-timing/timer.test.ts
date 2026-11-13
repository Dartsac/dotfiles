import assert from "node:assert/strict";
import { test } from "node:test";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { ENTRY_TYPE, VERBS, formatDuration, formatTiming, registerTimer, type TimingEntry } from "./timer.ts";

function harness(t: { mock: { method: Function } }, mode = "tui") {
  let now = 0;
  t.mock.method(performance, "now", () => now);
  const finishedAt = new Date(2026, 0, 1, 16, 42).getTime();
  t.mock.method(Date, "now", () => finishedAt);
  const messages: (string | undefined)[] = [];
  const ctx = { mode, ui: { setWorkingMessage: (message?: string) => messages.push(message) } };
  const handlers = new Map<string, Function>();
  const entries: { type: string; data: TimingEntry }[] = [];
  registerTimer({
    on: (name: string, handler: Function) => handlers.set(name, handler),
    appendEntry: (type: string, data: TimingEntry) => entries.push({ type, data }),
  } as unknown as ExtensionAPI);
  return {
    entries,
    messages,
    advance: (ms: number) => { now += ms; },
    emit: (name: string, event = {}) => handlers.get(name)?.(event, ctx),
  };
}

test("durations include seconds and roll over to minutes and hours", () => {
  for (const [ms, expected] of [
    [-1, "0s"], [0, "0s"], [999, "0s"], [59000, "59s"],
    [60000, "1m 0s"], [83000, "1m 23s"], [3600000, "1h 0m 0s"],
    [3723000, "1h 2m 3s"],
  ] as const) assert.equal(formatDuration(ms), expected);
});

test("completion line matches the requested local-time format", () => {
  assert.equal(formatTiming({
    durationMs: 83000,
    finishedAt: new Date(2026, 0, 1, 16, 42).getTime(),
    outcome: "done",
  }), "✻ Crunched for 1m 23s · done 4:42 PM");
});

test("records once at final idle, preserving time across low-level restarts", (t) => {
  const h = harness(t);
  h.emit("before_agent_start");
  h.advance(1000);
  h.emit("agent_start");
  h.advance(40000);
  h.emit("agent_end");
  assert.equal(h.entries.length, 0);
  h.emit("before_agent_start");
  h.emit("agent_start");
  h.advance(42000);
  h.emit("agent_settled", { aborted: false });
  h.emit("agent_settled", { aborted: false });
  assert.equal(h.entries.length, 1);
  assert.equal(h.entries[0].type, ENTRY_TYPE);
  assert.equal(h.entries[0].data.durationMs, 83000);
  assert.equal(h.entries[0].data.outcome, "done");
  h.advance(100000);
  h.emit("agent_start");
  h.advance(2000);
  h.emit("agent_settled", { aborted: false });
  assert.equal(h.entries[1].data.durationMs, 2000);
});

test("cancellation and errors are not labelled done; successful retries recover", (t) => {
  const h = harness(t);
  h.emit("agent_start");
  h.emit("agent_settled", { aborted: true });
  assert.equal(h.entries[0].data.outcome, "interrupted");
  h.emit("agent_start");
  h.emit("message_end", { message: { role: "assistant", stopReason: "error" } });
  h.emit("agent_settled", { aborted: false });
  assert.equal(h.entries[1].data.outcome, "error");
  h.emit("agent_start");
  h.emit("message_end", { message: { role: "assistant", stopReason: "error" } });
  h.emit("agent_start");
  h.emit("message_end", { message: { role: "assistant", stopReason: "stop" } });
  h.emit("agent_settled", { aborted: false });
  assert.equal(h.entries[2].data.outcome, "done");
});

test("all 100 verbs have unique running forms and exclude Baked", () => {
  assert.equal(VERBS.length, 100);
  assert.equal(new Set(VERBS.map(([past]) => past)).size, 100);
  assert.equal(new Set(VERBS.map(([, running]) => running)).size, 100);
  assert.ok(VERBS.every(([past, running]: readonly [string, string]) => past !== "Baked" && running.length > 0));
});

test("excludes the spooky and occult-themed verbs", () => {
  const removed = new Set([
    "Conjured", "Enchanted", "Summoned", "Bewitched", "Spellbound", "Hexed",
    "Charmed", "Transmuted", "Alchemized", "Scryed", "Divined", "Shapeshifted", "Mesmerized",
  ]);
  assert.ok(VERBS.every(([past]) => !removed.has(past)));
});

test("selects once per run, preserves the verb across retries, and persists it", (t) => {
  let picks = 0;
  t.mock.method(Math, "random", () => picks++ === 0 ? 7 / 100 : 23 / 99);
  const h = harness(t);
  h.emit("before_agent_start");
  assert.equal(h.messages[0], "Dialing in… 0s");
  h.emit("agent_start");
  h.emit("agent_start");
  h.advance(18000);
  h.emit("agent_settled");
  assert.equal(picks, 1);
  assert.equal(h.entries[0].data.verb, "Dialed in");
  assert.match(formatTiming(h.entries[0].data), /^✻ Dialed in for 18s/);
  assert.equal(h.messages.at(-1), undefined);
  h.emit("agent_start");
  assert.equal(h.messages.at(-1), "Tinkering… 0s");
  h.emit("agent_settled");
  assert.equal(h.entries[1].data.verb, "Tinkered");
});

for (const random of [0, 0.5, 0.999999]) {
  test(`consecutive runs never repeat even with constant randomness ${random}`, (t) => {
    t.mock.method(Math, "random", () => random);
    const h = harness(t);
    for (let i = 0; i < 20; i++) {
      h.emit("agent_start");
      h.emit("agent_settled", { aborted: i % 2 === 0 });
      assert.ok(VERBS.some(([past]) => past === h.entries[i].data.verb));
      if (i > 0) assert.notEqual(h.entries[i].data.verb, h.entries[i - 1].data.verb);
    }
  });
}

test("a run that fails while starting does not add its time to the next run", (t) => {
  const h = harness(t);
  // Pi emits neither agent_start nor agent_settled when preparing the run fails after this hook.
  h.emit("before_agent_start");
  h.advance(600000);
  h.emit("before_agent_start");
  assert.match(h.messages.at(-1)!, /… 0s$/);
  h.emit("agent_start");
  h.advance(2000);
  h.emit("agent_settled", { aborted: false });
  assert.equal(h.entries.length, 1);
  assert.equal(h.entries[0].data.durationMs, 2000);
});

test("shutdown discards an unfinished timer", (t) => {
  const h = harness(t);
  h.emit("agent_start");
  h.emit("session_shutdown");
  h.emit("agent_settled");
  assert.equal(h.entries.length, 0);
});

for (const mode of ["print", "json", "rpc"]) {
  test(`does not add transcript entries in ${mode} mode`, (t) => {
    const h = harness(t, mode);
    h.emit("agent_start");
    h.emit("agent_settled");
    assert.equal(h.entries.length, 0);
  });
}
