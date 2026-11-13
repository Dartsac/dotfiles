import { test } from "node:test";
import assert from "node:assert/strict";
import { bar, readableDuration, selectedQuota, sessionSpend } from "./format.ts";

test("additional providers preserve quota meaning", () => {
  assert.equal(selectedQuota("⚡ Copilot:42%p/3d,2%r/1h", "github-copilot")?.windows[0].label, "premium");
  assert.equal(selectedQuota("⚡ Kimi:20%r/2h,50%w/2d", "kimi-coding")?.windows[1].label, "weekly");
  assert.equal(selectedQuota("⚡ OpenRouter:$1.50/d,$9.00 left", "openrouter")?.windows[0].label, "account");
  assert.equal(selectedQuota("⚡ Claude:20%/1h", "google"), undefined);
});
test("session estimates isolate providers and include pre-compaction usage", () => {
  const entries = [
    { type: "message", message: { role: "assistant", provider: "google", usage: { cost: { total: 0.2 } } } },
    { type: "usage", provider: "google", usage: { cost: { total: 0.3 } } },
    { type: "usage", provider: "anthropic", usage: { cost: { total: 99 } } },
    { type: "usage", provider: "google", usage: { cost: { total: NaN } } },
  ];
  assert.equal(sessionSpend(entries, "google"), 0.5);
  assert.equal(sessionSpend(entries, "other"), undefined);
});

test("bars clamp values and preserve zero", () => {
  assert.equal(bar(0), "░░░░░░░░");
  assert.equal(bar(1000), "████████");
  assert.equal(bar(-2), "░░░░░░░░");
});
test("rounded upstream countdowns become readable", () => {
  assert.equal(readableDuration("4.8h"), "4h 48m");
  assert.equal(readableDuration("5.1d"), "5d 2h");
});
test("select active provider and strip colors", () => {
  const text = "⚡ Codex:2%/4.8h,10%/5.1d │ Claude:\x1b[32m0%/2h\x1b[0m,30%/3d";
  assert.equal(selectedQuota(text, "anthropic")?.windows[0].percent, 0);
  assert.equal(selectedQuota(text, "openai-codex")?.windows[1].reset, "5d 2h");
  assert.equal(selectedQuota(text, "other"), undefined);
});
test("missing and expired windows are not reported as unused", () => {
  assert.equal(selectedQuota("⚡ Codex:10%/5d", "openai-codex")?.windows[0].label, "quota");
  assert.equal(selectedQuota("⚡ Codex:--,10%/5d", "openai-codex")?.windows[0].raw, "--");
  assert.equal(selectedQuota("⚡ Claude limited:limited/2h", "anthropic")?.limited, true);
  assert.equal(selectedQuota("", "anthropic"), undefined);
});
