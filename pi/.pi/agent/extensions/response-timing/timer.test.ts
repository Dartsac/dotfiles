import assert from "node:assert/strict";
import { test } from "node:test";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
  ENTRY_TYPE, SUBAGENT_COMPLETE, SUBAGENT_STARTED, VERBS, WAKE_GRACE_MS,
  formatDuration, formatTiming, registerTimer, type TimingEntry,
} from "./timer.ts";

function harness(t: { mock: { method: Function; timers: { enable: Function; tick: Function } } }, mode = "tui") {
  t.mock.timers.enable({ apis: ["setInterval", "setTimeout"] });
  let now = 0;
  t.mock.method(performance, "now", () => now);
  const start = new Date(2026, 0, 1, 16, 42).getTime();
  t.mock.method(Date, "now", () => start + now);
  let idle = true;
  const messages: (string | undefined)[] = [];
  const ctx = { mode, isIdle: () => idle, ui: { setWorkingMessage: (message?: string) => messages.push(message) } };
  const handlers = new Map<string, Function>();
  const listeners = new Map<string, Set<Function>>();
  const entries: { type: string; data: TimingEntry }[] = [];
  registerTimer({
    on: (name: string, handler: Function) => handlers.set(name, handler),
    appendEntry: (type: string, data: TimingEntry) => entries.push({ type, data }),
    events: {
      on: (channel: string, handler: Function) => {
        if (!listeners.has(channel)) listeners.set(channel, new Set());
        listeners.get(channel)!.add(handler);
        return () => listeners.get(channel)!.delete(handler);
      },
    },
  } as unknown as ExtensionAPI);
  return {
    entries,
    messages,
    setIdle: (value: boolean) => { idle = value; },
    advance: (ms: number) => { now += ms; t.mock.timers.tick(ms); },
    emit: (name: string, event = {}) => handlers.get(name)?.(event, ctx),
    publish: (channel: string, data: unknown) => listeners.get(channel)?.forEach((handler) => handler(data)),
  };
}

/** The wall-clock time `ms` after the harness started. */
const at = (ms: number) => new Date(2026, 0, 1, 16, 42).getTime() + ms;

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
  assert.equal(h.entries[0].data.finishedAt, at(83000));
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

test("a run that settles while subagents run records once, timed through the run their completion wakes", (t) => {
  const h = harness(t);
  h.emit("before_agent_start", { messageType: "user" });
  h.emit("agent_start");
  h.publish(SUBAGENT_STARTED, { id: "a" });
  h.publish(SUBAGENT_STARTED, { id: "b" });
  h.advance(60000);
  h.emit("agent_settled", { aborted: false });
  assert.equal(h.entries.length, 0);
  // The first completion wakes the parent while the other subagent still runs.
  h.advance(600000);
  h.publish(SUBAGENT_COMPLETE, { runId: "a" });
  h.emit("before_agent_start", { messageType: "custom" });
  assert.equal(h.messages.at(-1), `${h.messages[0]!.replace(/ 0s$/, "")} 11m 0s`);
  h.emit("agent_start");
  h.advance(30000);
  h.emit("agent_settled", { aborted: false });
  assert.equal(h.entries.length, 0);
  h.advance(400000);
  h.publish(SUBAGENT_COMPLETE, { id: "b" });
  h.emit("before_agent_start", { messageType: "custom" });
  h.emit("agent_start");
  h.advance(20000);
  h.emit("agent_settled", { aborted: false });
  assert.equal(h.entries.length, 1);
  assert.equal(h.entries[0].data.durationMs, 1110000);
  assert.equal(h.entries[0].data.finishedAt, at(1110000));
  assert.equal(h.entries[0].data.outcome, "done");
  // Nothing is left waiting: the next prompt is timed on its own.
  h.emit("before_agent_start", { messageType: "user" });
  h.emit("agent_start");
  h.advance(5000);
  h.emit("agent_settled", { aborted: false });
  assert.equal(h.entries[1].data.durationMs, 5000);
});

test("a subagent completion that does not wake the parent ends the waiting task", (t) => {
  const h = harness(t);
  h.emit("agent_start");
  h.publish(SUBAGENT_STARTED, { id: "a" });
  h.advance(10000);
  h.emit("agent_settled", { aborted: false });
  h.advance(50000);
  h.publish(SUBAGENT_COMPLETE, { runId: "a" });
  h.advance(WAKE_GRACE_MS - 1);
  assert.equal(h.entries.length, 0);
  h.advance(1);
  assert.equal(h.entries.length, 1);
  assert.equal(h.entries[0].data.durationMs, 60000 + WAKE_GRACE_MS);
  assert.equal(h.entries[0].data.outcome, "done");
});

test("a subagent that starts during the grace keeps the task waiting until it completes", (t) => {
  const h = harness(t);
  h.emit("agent_start");
  h.publish(SUBAGENT_STARTED, { id: "a" });
  h.advance(10000);
  h.emit("agent_settled", { aborted: false });
  h.publish(SUBAGENT_COMPLETE, { runId: "a" });
  h.advance(1000);
  h.publish(SUBAGENT_STARTED, { id: "b" });
  h.advance(WAKE_GRACE_MS + 60000);
  assert.equal(h.entries.length, 0);
  h.publish(SUBAGENT_COMPLETE, { runId: "b" });
  h.emit("before_agent_start", { messageType: "custom" });
  h.emit("agent_start");
  h.advance(1000);
  h.emit("agent_settled", { aborted: false });
  assert.equal(h.entries.length, 1);
  assert.equal(h.entries[0].data.durationMs, 10000 + 1000 + WAKE_GRACE_MS + 60000 + 1000);
});

test("a completion whose wake is still starting after the grace leaves the task to that run", (t) => {
  const h = harness(t);
  h.emit("agent_start");
  h.publish(SUBAGENT_STARTED, { id: "a" });
  h.advance(10000);
  h.emit("agent_settled", { aborted: false });
  h.publish(SUBAGENT_COMPLETE, { runId: "a" });
  // Pi is busy from the wake's send, while it compacts before before_agent_start.
  h.setIdle(false);
  h.advance(WAKE_GRACE_MS + 30000);
  assert.equal(h.entries.length, 0);
  h.setIdle(true);
  h.emit("before_agent_start", { messageType: "custom" });
  h.emit("agent_start");
  h.advance(1000);
  h.emit("agent_settled", { aborted: false });
  assert.equal(h.entries.length, 1);
  assert.equal(h.entries[0].data.durationMs, 10000 + WAKE_GRACE_MS + 31000);
});

test("a user prompt while subagents run records the waiting task as it settled, then times the prompt", (t) => {
  const h = harness(t);
  h.emit("before_agent_start", { messageType: "user" });
  h.emit("agent_start");
  h.publish(SUBAGENT_STARTED, { id: "a" });
  h.advance(10000);
  h.emit("message_end", { message: { role: "assistant", stopReason: "error" } });
  h.emit("agent_settled", { aborted: false });
  h.advance(50000);
  h.emit("before_agent_start", { messageType: "user" });
  assert.equal(h.entries.length, 1);
  assert.equal(h.entries[0].data.durationMs, 10000);
  assert.equal(h.entries[0].data.finishedAt, at(10000));
  assert.equal(h.entries[0].data.outcome, "error");
  assert.match(h.messages.at(-1)!, /… 0s$/);
  h.emit("agent_start");
  h.advance(3000);
  h.emit("agent_settled", { aborted: false });
  // The subagent still runs: this prompt's line waits for it too.
  assert.equal(h.entries.length, 1);
  h.publish(SUBAGENT_COMPLETE, { runId: "a" });
  h.emit("before_agent_start", { messageType: "custom" });
  h.emit("agent_start");
  h.advance(2000);
  h.emit("agent_settled", { aborted: false });
  assert.equal(h.entries[1].data.durationMs, 5000);
});

test("an interrupted run records at once, even while subagents run", (t) => {
  const h = harness(t);
  h.emit("agent_start");
  h.publish(SUBAGENT_STARTED, { id: "a" });
  h.advance(10000);
  h.emit("agent_settled", { aborted: true });
  assert.equal(h.entries.length, 1);
  assert.equal(h.entries[0].data.outcome, "interrupted");
  // Its subagent's later wake starts a fresh timer.
  h.publish(SUBAGENT_COMPLETE, { runId: "a" });
  h.emit("before_agent_start", { messageType: "custom" });
  h.emit("agent_start");
  h.advance(4000);
  h.emit("agent_settled", { aborted: false });
  assert.equal(h.entries[1].data.durationMs, 4000);
});

test("shutdown drops a waiting task and stops listening for subagents", (t) => {
  const h = harness(t);
  h.emit("agent_start");
  h.publish(SUBAGENT_STARTED, { id: "a" });
  h.emit("agent_settled", { aborted: false });
  h.emit("session_shutdown");
  h.publish(SUBAGENT_STARTED, { id: "b" });
  h.publish(SUBAGENT_COMPLETE, { runId: "a" });
  h.advance(WAKE_GRACE_MS);
  assert.equal(h.entries.length, 0);
  h.emit("agent_start");
  h.emit("agent_settled", { aborted: false });
  assert.equal(h.entries.length, 1);
});
