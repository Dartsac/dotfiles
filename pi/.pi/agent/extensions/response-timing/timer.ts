import type { ExtensionContext, ExtensionAPI } from "@earendil-works/pi-coding-agent";

export const ENTRY_TYPE = "response-timing";

export const VERBS = [
  ["Brewed", "Brewing"], ["Buzzed", "Buzzing"], ["Churned", "Churning"],
  ["Cogitated", "Cogitating"], ["Cooked", "Cooking"], ["Crunched", "Crunching"],
  ["Deciphered", "Deciphering"], ["Dialed in", "Dialing in"],
  ["Engineered", "Engineering"], ["Explored", "Exploring"],
  ["Fiddled", "Fiddling"], ["Forged", "Forging"], ["Honed", "Honing"],
  ["Mulled", "Mulling"], ["Percolated", "Percolating"], ["Polished", "Polishing"],
  ["Pondered", "Pondering"], ["Puzzled", "Puzzling"], ["Quested", "Questing"],
  ["Rambled", "Rambling"], ["Riffed", "Riffing"], ["Sautéed", "Sautéing"],
  ["Steeped", "Steeping"], ["Swarmed", "Swarming"], ["Tinkered", "Tinkering"],
  // Coffee and the kitchen.
  ["Roasted", "Roasting"], ["Ground", "Grinding"], ["Filtered", "Filtering"],
  ["Pressed", "Pressing"], ["Poured", "Pouring"], ["Frothed", "Frothing"],
  ["Foamed", "Foaming"], ["Blended", "Blending"], ["Infused", "Infusing"],
  ["Simmered", "Simmering"], ["Stirred", "Stirring"], ["Whisked", "Whisking"],
  ["Seasoned", "Seasoning"], ["Toasted", "Toasting"], ["Caramelized", "Caramelizing"],
  // Tinkering, engineering, and refining.
  ["Calibrated", "Calibrating"], ["Tuned", "Tuning"], ["Refined", "Refining"],
  ["Crafted", "Crafting"], ["Assembled", "Assembling"], ["Wired", "Wiring"],
  ["Soldered", "Soldering"], ["Welded", "Welding"], ["Bolted", "Bolting"],
  ["Sculpted", "Sculpting"], ["Sketched", "Sketching"], ["Prototyped", "Prototyping"],
  ["Optimized", "Optimizing"], ["Debugged", "Debugging"], ["Invented", "Inventing"],
  // Studying, curiosity, and improvement.
  ["Studied", "Studying"], ["Learned", "Learning"], ["Reasoned", "Reasoning"],
  ["Deduced", "Deducing"], ["Unraveled", "Unraveling"], ["Untangled", "Untangling"],
  ["Decoded", "Decoding"], ["Solved", "Solving"], ["Investigated", "Investigating"],
  ["Researched", "Researching"], ["Reflected", "Reflecting"], ["Contemplated", "Contemplating"],
  ["Synthesized", "Synthesizing"], ["Connected", "Connecting"], ["Practiced", "Practicing"],
  // Trails, games, and time with friends.
  ["Trekked", "Trekking"], ["Hiked", "Hiking"], ["Roamed", "Roaming"],
  ["Wandered", "Wandering"], ["Navigated", "Navigating"], ["Scouted", "Scouting"],
  ["Traversed", "Traversing"], ["Climbed", "Climbing"], ["Adventured", "Adventuring"],
  ["Leveled up", "Leveling up"], ["Rallied", "Rallying"], ["Strategized", "Strategizing"],
  ["Bantered", "Bantering"], ["Jammed", "Jamming"], ["Collaborated", "Collaborating"],
  // Color and creativity, without spooky or occult imagery.
  ["Tooled", "Tooling"], ["Machined", "Machining"], ["Trailblazed", "Trailblazing"],
  ["Brightened", "Brightening"], ["Illuminated", "Illuminating"], ["Colored", "Coloring"],
  ["Tinted", "Tinting"], ["Shaded", "Shading"], ["Highlighted", "Highlighting"],
  ["Harmonized", "Harmonizing"], ["Doodled", "Doodling"], ["Moonwalked", "Moonwalking"],
  ["Stargazed", "Stargazing"], ["Meandered", "Meandering"], ["Daydreamed", "Daydreaming"],
] as const;

export interface TimingEntry {
  verb?: string;
  durationMs: number;
  finishedAt: number;
  outcome: "done" | "interrupted" | "error";
}

export function formatDuration(milliseconds: number): string {
  const seconds = Math.max(0, Math.floor(milliseconds / 1000));
  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
  return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m ${seconds % 60}s`;
}

const TIME_FORMAT = new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit", hour12: true });

export function formatTiming(entry: TimingEntry): string {
  const time = TIME_FORMAT.format(entry.finishedAt);
  return `✻ ${entry.verb ?? "Crunched"} for ${formatDuration(entry.durationMs)} · ${entry.outcome} ${time}`;
}

// pi-subagents announces each background run on pi.events; its completion wakes the parent.
export const SUBAGENT_STARTED = "subagent:async-started";
export const SUBAGENT_COMPLETE = "subagent:async-complete";
// How long after the last subagent completes a parent still idle counts as not woken.
export const WAKE_GRACE_MS = 2000;

function subagentRunId(data: unknown): string | undefined {
  if (typeof data !== "object" || data === null) return undefined;
  const { runId, id } = data as Record<string, unknown>;
  const value = runId ?? id;
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

export function registerTimer(pi: ExtensionAPI) {
  let startedAt: number | undefined;
  let failed = false;
  // Whether the agent has started since the timer did.
  let agentStarted = false;
  let ticker: ReturnType<typeof setInterval> | undefined;
  // Index into VERBS of the current (or last) run's verb.
  let verbIndex: number | undefined;
  // Background subagent runs started and not yet complete.
  const subagents = new Set<string>();
  // A run that settled while subagents still ran. Its line waits for the run their completion wakes.
  let waiting: { settledAt: number; finishedAt: number; ctx: ExtensionContext } | undefined;
  let wakeCheck: ReturnType<typeof setTimeout> | undefined;

  const stopTicker = () => {
    clearInterval(ticker);
    ticker = undefined;
  };
  const stopWaiting = () => {
    clearTimeout(wakeCheck);
    wakeCheck = undefined;
    const deferred = waiting;
    waiting = undefined;
    return deferred;
  };
  const start = (ctx: ExtensionContext) => {
    // Preserve the first start and verb across retries, compaction, follow-ups and subagent wakes.
    if (startedAt === undefined) {
      startedAt = performance.now();
      // Sample uniformly from every verb except the previous one, without retry loops.
      let index = Math.floor(Math.random() * (VERBS.length - (verbIndex === undefined ? 0 : 1)));
      if (verbIndex !== undefined && index >= verbIndex) index += 1;
      verbIndex = index;
    }
    if (ctx.mode !== "tui" || ticker) return;
    const started = startedAt;
    const running = VERBS[verbIndex!][1];
    const update = () => ctx.ui.setWorkingMessage(`${running}… ${formatDuration(performance.now() - started)}`);
    update();
    ticker = setInterval(update, 1000);
    ticker.unref();
  };
  const finish = (ctx: ExtensionContext, endedAt: number, finishedAt: number, aborted: boolean) => {
    const durationMs = Math.max(0, endedAt - startedAt!);
    startedAt = undefined;
    // Only the interactive transcript needs this display-only entry.
    if (ctx.mode !== "tui") return;
    pi.appendEntry<TimingEntry>(ENTRY_TYPE, {
      durationMs,
      verb: VERBS[verbIndex!][0],
      finishedAt,
      outcome: aborted ? "interrupted" : failed ? "error" : "done",
    });
  };

  const unsubscribe = [
    pi.events.on(SUBAGENT_STARTED, (data) => {
      const id = subagentRunId(data);
      if (id) subagents.add(id);
    }),
    pi.events.on(SUBAGENT_COMPLETE, (data) => {
      const id = subagentRunId(data);
      if (!id || !subagents.delete(id) || !waiting || subagents.size > 0) return;
      // A completion that wakes the parent has started its run by now; one that does not
      // (a held or non-waking notice) leaves the parent idle, and the task ends here.
      clearTimeout(wakeCheck);
      wakeCheck = setTimeout(() => {
        wakeCheck = undefined;
        if (!waiting?.ctx.isIdle()) return;
        finish(stopWaiting()!.ctx, performance.now(), Date.now(), false);
      }, WAKE_GRACE_MS);
      wakeCheck.unref();
    }),
  ];

  pi.on("before_agent_start", (event, ctx) => {
    const deferred = stopWaiting();
    if (deferred) {
      // A subagent's completion woke the parent: the same task goes on, on the same timer.
      if (event.messageType === "custom") return start(ctx);
      // The user moved on before the subagents finished: their task ended when it settled.
      finish(deferred.ctx, deferred.settledAt, deferred.finishedAt, false);
    } else if (startedAt !== undefined && !agentStarted) {
      // Pi emits neither agent_start nor agent_settled when preparing a run fails after this hook,
      // so a timer still waiting for agent_start belongs to a run that never began. Drop it.
      startedAt = undefined;
      stopTicker();
    }
    start(ctx);
  });
  pi.on("agent_start", (_event, ctx) => {
    start(ctx);
    agentStarted = true;
    failed = false;
  });
  pi.on("message_end", (event) => {
    if (event.message.role === "assistant") {
      failed = event.message.stopReason === "error";
    }
  });
  pi.on("agent_settled", (event, ctx) => {
    if (startedAt === undefined) return;
    agentStarted = false;
    stopTicker();
    if (ctx.mode === "tui") ctx.ui.setWorkingMessage();
    // The parent is idle, but the task is not over while its background subagents run.
    if (!event.aborted && subagents.size > 0) {
      waiting = { settledAt: performance.now(), finishedAt: Date.now(), ctx };
      return;
    }
    finish(ctx, performance.now(), Date.now(), event.aborted);
  });
  pi.on("session_shutdown", (_event, ctx) => {
    stopTicker();
    stopWaiting();
    for (const off of unsubscribe) off();
    subagents.clear();
    if (ctx.mode === "tui") ctx.ui.setWorkingMessage();
    startedAt = undefined;
    agentStarted = false;
    failed = false;
  });
}
