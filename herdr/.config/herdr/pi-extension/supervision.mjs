// Pure state policy plus read-only access to pi-subagents' supervisor protocol.
// No prompts, task output, or request bodies are copied into notifications.
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

export const GRACE_MS = 60_000;
// How long "Finishing up" waits for the parent's wrap-up turn after the last
// child or busy tool ends while the parent is idle. pi-subagents normally wakes
// the parent within about a second; quiet scheduled runs and workflow steps
// never do, and a child can end between polls just after the parent settled.
export const WRAPUP_GRACE_MS = 30_000;
// How long a turn that was already running when the last child ended waits for
// pi-subagents' wake turn before it counts as the wrap-up itself.
export const WRAPUP_CONFIRM_MS = 5_000;
export const clean = (text, max = 160) => String(text ?? "").replace(/[\x00-\x1f\x7f-\x9f]/g, " ").replace(/\s+/g, " ").trim().slice(0, max);

export function subagentsRoot(env = process.env) {
  return env.PI_SUBAGENTS_TEMP_ROOT?.trim()
    ? path.resolve(env.PI_SUBAGENTS_TEMP_ROOT.trim())
    : path.join(os.tmpdir(), `pi-subagents-uid-${process.getuid()}`);
}
export const supervisorRoot = env => path.join(subagentsRoot(env), "supervisor-channels");
export const asyncRunsRoot = env => path.join(subagentsRoot(env), "async-subagent-runs");
const plural = (n, word) => `${n} ${word}${n === 1 ? "" : word === "child" ? "ren" : "s"}`;

// Request/reply files, not control-notice delivery or parent activity, decide
// whether a native supervisor question remains unanswered. Other sessions and
// progress-only notices must never turn this pane into a human blocker.
export function pendingRequests(root, sessionId, previous = [], now = Date.now()) {
  const pending = new Map();
  const priorByFile = new Map(previous.map(r => [r.file, r]));
  let channels;
  try { channels = fs.readdirSync(root, { withFileTypes: true }); }
  catch (error) { return error.code === "ENOENT" ? [] : previous; }
  for (const channel of channels) {
    if (!channel.isDirectory()) continue;
    const dir = path.join(root, channel.name);
    let names;
    try { names = fs.readdirSync(path.join(dir, "requests")); }
    catch (error) {
      if (error.code !== "ENOENT") for (const r of previous) if (path.dirname(path.dirname(r.file)) === dir) pending.set(r.id, r);
      continue;
    }
    for (const name of names) {
      if (!name.endsWith(".json")) continue;
      const file = path.join(dir, "requests", name);
      try {
        const r = JSON.parse(fs.readFileSync(file, "utf8"));
        if (r.type !== "subagent.supervisor.request" || r.orchestratorSessionId !== sessionId || r.expectsReply !== true) continue;
        if (typeof r.id !== "string" || !/^[A-Za-z0-9._-]+$/.test(r.id) || typeof r.runId !== "string") continue;
        if (!["need_decision", "interview_request"].includes(r.reason) || !Number.isFinite(r.createdAt)) continue;
        if (fs.existsSync(path.join(dir, "replies", `${r.id}.json`))) continue;
        const expiresAt = Number.isFinite(r.expiresAt) ? r.expiresAt : r.createdAt + 600_000;
        if (now > expiresAt) continue;
        pending.set(r.id, { id: r.id, file, createdAt: r.createdAt, expiresAt, agent: clean(r.agent, 40), runId: r.runId, childIndex: Number.isInteger(r.childIndex) ? r.childIndex : 0 });
      } catch {
        // Atomic writes normally avoid this. Do not call an unreadable request
        // resolved just because one read failed; retry on the next tick.
        if (priorByFile.has(file)) pending.set(priorByFile.get(file).id, priorByFile.get(file));
      }
    }
  }
  return [...pending.values()].filter(r => now <= r.expiresAt);
}

export function hasChildIssue(data) {
  const queue = [data];
  for (let i = 0; i < queue.length && i < 512; i++) {
    const item = queue[i];
    if (!item || typeof item !== "object") continue;
    if (item.success === false || ["failed", "paused", "stopped"].includes(item.state ?? item.status)) return true;
    for (const key of ["results", "steps", "children", "nestedChildren"]) {
      if (Array.isArray(item[key])) queue.push(...item[key].slice(0, 128));
    }
  }
  return false;
}

export class Supervision {
  parentActive = false;
  busy = 0;
  wrapupPending = false;
  wrapupSince = 0;
  human = new Set();
  requests = [];
  problem = "";
  childIssues = false;
  children = 0; // live background children found in lifecycle files
  // pi-subagents' busy signal outlasts an async workflow by up to 45s (its
  // completion doesn't clear it; only a refresh does). So once the scan has
  // seen the last live child end (childrenDone) and the parent has wrapped up,
  // busy no longer keeps the parent working. It counts again when the scan
  // finds a live child, when it drops (the lag is over) or when it rises (work
  // pi-subagents has just seen). The wrap-up is a turn that began after the
  // children ended (pi-subagents' wake turn). A turn that was already running
  // counts once no wake turn has followed it for WRAPUP_CONFIRM_MS: the
  // results reached it while it ran.
  childrenDone = false;
  wakeTurn = false;
  wrappedUp = false;
  confirmAt = 0;
  question = 0;
  lastQuestion = "";

  start() { this.parentActive = true; this.problem = ""; this.wakeTurn = this.childrenDone; this.confirmAt = 0; }
  settled({ aborted = false, pending = false, error = false } = {}, now = Date.now()) {
    this.parentActive = false;
    this.human.clear(); // No blocking tool prompt can outlive a settled run.
    if (this.childrenDone && !pending) {
      if (this.wakeTurn && !aborted && !error) this.wrappedUp = true;
      else this.confirmAt = now + WRAPUP_CONFIRM_MS;
    }
    if (aborted || error) {
      this.problem = aborted ? "Interrupted, not done" : "Error, not done";
      this.wrapupPending = false;
    } else if (!this.busyNow(now) && !this.children && !pending) this.wrapupPending = false;
    else if (this.wrapupPending) this.wrapupSince = now; // wait afresh for the queued turn
  }
  armWrapup(now) { this.wrapupPending = true; this.wrapupSince = now; }
  // From here busy counts again. If it had gone stale, that wrap-up is over:
  // it must not come back as a Finishing up when the late signal drops.
  newWork(now = Date.now()) {
    if (this.stale(now)) this.wrapupPending = false;
    this.childrenDone = this.wakeTurn = this.wrappedUp = false;
    this.confirmAt = 0;
  }
  stale(now = Date.now()) { return this.childrenDone && (this.wrappedUp || (this.confirmAt > 0 && now >= this.confirmAt)); }
  busyNow(now = Date.now()) { return this.busy > 0 && !this.stale(now); }
  setBusy(active, now = Date.now()) {
    const wasBusy = this.busy > 0, stale = this.stale(now);
    this.busy = Math.max(0, this.busy + (active ? 1 : -1));
    if (stale && (active || !this.busy)) this.newWork(now); // its wrap-up is done: nothing to arm
    else if (!active && wasBusy && !this.busy) this.armWrapup(now);
  }
  setChildren(n, now = Date.now()) {
    if (n > 0) this.newWork(now);
    else if (this.children > 0) { this.armWrapup(now); this.childrenDone = true; this.wrappedUp = false; this.confirmAt = 0; }
    this.children = n;
  }
  // Waiting for the parent to wrap up: always while it runs, else for a grace period.
  wrappingUp(now = Date.now()) {
    return this.wrapupPending && !this.stale(now) && (this.parentActive || now - this.wrapupSince < WRAPUP_GRACE_MS);
  }
  setHuman(key, active) {
    const wasWaiting = this.human.size > 0;
    if (active) this.human.add(key); else this.human.delete(key);
    if (!wasWaiting && this.human.size) this.lastQuestion = `human-${++this.question}`;
  }
  // The parent's whole job is finished: its completion (done, or ended with a
  // problem), after delegated work and the wrap-up turn. Not while it waits for you.
  finished(now = Date.now()) { return ["idle", "unknown"].includes(this.desired(now).state); }
  desired(now = Date.now()) {
    const overdue = this.requests.filter(r => now - r.createdAt >= GRACE_MS).sort((a, b) => a.createdAt - b.createdAt || a.id.localeCompare(b.id));
    if (this.human.size) return { state: "blocked", attention: this.lastQuestion, title: "Pi needs your answer", activity: "Waiting for you" };
    if (overdue.length) return {
      state: "blocked", attention: `supervisor-${overdue[0].id}`,
      title: "60s unanswered: child → parent",
      activity: `${overdue[0].agent || "Child"} waited 60s for parent${overdue.length > 1 ? ` (+${overdue.length - 1})` : ""}`,
    };
    // Children are counted in the sidebar's tree under the parent, not here.
    const busy = this.busyNow(now);
    if (this.parentActive || busy || this.children || this.wrappingUp(now)) return {
      state: "working", attention: "", title: "",
      activity: this.requests.length ? `${plural(this.requests.length, "child")} asking parent`
        : this.parentActive || busy || this.children ? "Working" : "Finishing up",
    };
    return { state: this.problem ? "unknown" : "idle", attention: "", title: "",
      completionTitle: this.childIssues ? "Pi finished with child issues" : "",
      activity: this.problem || (this.childIssues ? "Done, with child issues" : "Ready") };
  }
}
