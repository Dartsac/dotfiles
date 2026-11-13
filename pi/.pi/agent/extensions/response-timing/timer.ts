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

export function registerTimer(pi: ExtensionAPI) {
  let startedAt: number | undefined;
  let failed = false;
  // Whether the agent has started since the timer did.
  let agentStarted = false;
  let ticker: ReturnType<typeof setInterval> | undefined;
  // Index into VERBS of the current (or last) run's verb.
  let verbIndex: number | undefined;

  const stopTicker = () => {
    clearInterval(ticker);
    ticker = undefined;
  };
  const start = (_event: unknown, ctx: ExtensionContext) => {
    // Preserve the first start and verb across retries, compaction, and follow-ups.
    if (startedAt !== undefined) return;
    const started = startedAt = performance.now();
    // Sample uniformly from every verb except the previous one, without retry loops.
    let index = Math.floor(Math.random() * (VERBS.length - (verbIndex === undefined ? 0 : 1)));
    if (verbIndex !== undefined && index >= verbIndex) index += 1;
    verbIndex = index;
    if (ctx.mode !== "tui") return;
    const running = VERBS[index][1];
    const update = () => ctx.ui.setWorkingMessage(`${running}… ${formatDuration(performance.now() - started)}`);
    update();
    ticker = setInterval(update, 1000);
    ticker.unref();
  };
  pi.on("before_agent_start", (event, ctx) => {
    // Pi emits neither agent_start nor agent_settled when preparing a run fails after this hook,
    // so a timer still waiting for agent_start belongs to a run that never began. Drop it.
    if (startedAt !== undefined && !agentStarted) {
      startedAt = undefined;
      stopTicker();
    }
    start(event, ctx);
  });
  pi.on("agent_start", (event, ctx) => {
    start(event, ctx);
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
    const durationMs = Math.max(0, performance.now() - startedAt);
    startedAt = undefined;
    agentStarted = false;
    stopTicker();
    // Only the interactive transcript needs this display-only entry.
    if (ctx.mode !== "tui") return;
    ctx.ui.setWorkingMessage();
    pi.appendEntry<TimingEntry>(ENTRY_TYPE, {
      durationMs,
      verb: VERBS[verbIndex!][0],
      finishedAt: Date.now(),
      outcome: event.aborted ? "interrupted" : failed ? "error" : "done",
    });
  });
  pi.on("session_shutdown", (_event, ctx) => {
    stopTicker();
    if (ctx.mode === "tui") ctx.ui.setWorkingMessage();
    startedAt = undefined;
    agentStarted = false;
    failed = false;
  });
}
