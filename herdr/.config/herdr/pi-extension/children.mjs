// Background subagents as Herdr tabs: one read-only pi-subagents viewer per
// child, reported as a silent custom agent so it appears in the sidebar.
import fs from "node:fs";
import path from "node:path";
import { clean } from "./supervision.mjs";

export const MAX_TABS = 8;
const SOURCE = "dotfiles:subagent";
const LIVE = new Set(["queued", "running", "pending"]);
const TERMINAL_TEXT = { complete: "Finished", completed: "Finished", failed: "Failed", paused: "Paused", stopped: "Stopped" };

function readStatus(dir) {
  try { return JSON.parse(fs.readFileSync(path.join(dir, "status.json"), "utf8")); } catch { return undefined; }
}

// Children of this parent session, read from pi-subagents' lifecycle files.
// Workflow roots are containers: their steps point at each child's own run.
// Other roots (single/parallel/chain) contain their children as steps.
export function scanChildren(asyncRoot, sessionIds) {
  const owned = new Set(sessionIds.filter(Boolean));
  let dirs;
  try { dirs = fs.readdirSync(asyncRoot, { withFileTypes: true }).filter(d => d.isDirectory()); } catch { return []; }
  const children = [];
  for (const dir of dirs) {
    const root = readStatus(path.join(asyncRoot, dir.name));
    if (!root || !owned.has(root.sessionId) || root.parentWorkflowRunId) continue;
    const roots = typeof root.sessionRoot === "string" ? [root.sessionRoot] : [];
    (root.steps ?? []).forEach((step, index) => {
      if (root.mode === "workflow") {
        if (typeof step.runId !== "string" || !/^[A-Za-z0-9-]+$/.test(step.runId)) return;
        const asyncDir = path.join(asyncRoot, step.runId);
        const child = readStatus(asyncDir);
        children.push({
          key: step.runId, runId: step.runId, asyncDir, roots,
          name: clean(step.workflowKey || step.agent || "subagent", 40),
          agent: clean(step.agent || "subagent", 40), title: clean(step.label, 60),
          state: child?.state ?? step.status ?? "queued", index: 0,
        });
      } else {
        const several = (root.steps?.length ?? 0) > 1;
        children.push({
          key: several ? `${root.runId}#${index}` : root.runId, runId: root.runId,
          asyncDir: path.join(asyncRoot, dir.name), roots, index,
          name: clean(step.agent || "subagent", 40) + (several ? `-${index + 1}` : ""),
          agent: clean(step.agent || "subagent", 40), title: clean(step.label, 60),
          state: several ? (step.status ?? root.state) : root.state,
        });
      }
    });
  }
  return children.sort((a, b) => a.key.localeCompare(b.key));
}

export const isLive = state => LIVE.has(state);

export function childActivity(child, waiting) {
  if (TERMINAL_TEXT[child.state]) return TERMINAL_TEXT[child.state];
  if (waiting) return "Waiting on parent";
  return child.state === "running" ? "Working" : "Queued";
}

export class ChildTabs {
  // deps: cli(args) -> parsed JSON result, rpc(method, params), viewer: { launcher, env(child) }
  constructor({ cli, rpc, viewer, workspace, parentPane, cwd, max = MAX_TABS }) {
    Object.assign(this, { cli, rpc, viewer, workspace, parentPane, cwd, max });
    this.tabs = new Map(); // key -> { pane, tab, reported, seq, state }
    this.dismissed = new Set();
    this.seq = Date.now() * 1000;
  }

  // Re-attach to tabs a previous runtime of this parent opened (e.g. after /reload).
  adopt(snapshot) {
    for (const pane of snapshot.panes ?? []) {
      const t = pane.tokens ?? {};
      if (t["subagent-parent"] === this.parentPane && t["subagent-run"] && !this.tabs.has(t["subagent-run"])) {
        this.tabs.set(t["subagent-run"], { pane: pane.pane_id, tab: pane.tab_id, reported: "" });
      }
    }
  }

  // Shutdown: let the step in flight finish, start nothing new.
  stop() { this.stopping = true; }
  // Once shutdown returns: no further Herdr writes, even from a late reply.
  halt() { this.stopping = this.stopped = true; }
  guard() { if (this.stopped) throw new Error("child tabs stopped"); }

  // A tab counts only once its viewer runs and it is tagged for adoption. The
  // tag goes last, so a reloaded parent never adopts a tab with no viewer.
  async open(child) {
    const created = await this.cli(["tab", "create", "--workspace", this.workspace, "--cwd", this.cwd,
      "--label", child.name, "--no-focus", ...Object.entries(this.viewer.env(child)).flatMap(([k, v]) => ["--env", `${k}=${v}`])]);
    const pane = created.root_pane.pane_id, tab = created.tab.tab_id;
    try {
      this.guard();
      // The pane stays unnamed: Herdr draws pane names as border titles.
      await this.cli(["pane", "run", pane, `exec sh '${this.viewer.launcher}'`]);
      this.guard();
      await this.rpc("pane.report_metadata", {
        pane_id: pane, source: SOURCE, applies_to_source: SOURCE, display_agent: child.agent,
        tokens: { "subagent-run": child.key, "subagent-parent": this.parentPane }, seq: ++this.seq,
      });
    } catch (error) {
      // Remove the half-made viewer; the caller won't retry this child. Same
      // rule as cleanup: the whole tab only if the viewer is alone in it, and
      // nothing at all if Herdr's layout can't be read.
      if (!this.stopped) await this.livePanes().then(panes => this.closeViewer({ pane }, panes)).catch(() => {});
      throw error;
    }
    const entry = { pane, tab, reported: "" };
    this.tabs.set(child.key, entry);
    return entry;
  }

  async report(entry, child, waiting) {
    const activity = childActivity(child, waiting);
    const terminal = !!TERMINAL_TEXT[child.state];
    const signature = `${terminal ? "done" : "live"}:${activity}`;
    if (entry.reported === signature) return;
    this.guard();
    await this.rpc("pane.report_metadata", {
      pane_id: entry.pane, source: SOURCE, applies_to_source: SOURCE, tokens: { activity }, seq: ++this.seq,
    });
    const states = !terminal ? ["working"] : entry.reported.startsWith("done") ? [] : ["unknown", "idle"];
    // Herdr sounds only for ->blocked and working/blocked->idle. unknown->idle
    // is silent, so a finished child never produces its own notification.
    for (const state of states) {
      this.guard();
      await this.rpc("pane.report_agent", { pane_id: entry.pane, source: SOURCE, agent: "subagent", state, message: activity, seq: ++this.seq });
    }
    entry.reported = signature;
  }

  // Herdr's panes by id, for the checks below that need the real layout.
  async livePanes() {
    const { snapshot } = await this.rpc("session.snapshot", {});
    return new Map((snapshot?.panes ?? []).map(p => [p.pane_id, p]));
  }

  // Forget tabs the owner closed: the pane is gone, or its id now belongs to a
  // pane that isn't this child's viewer. Unchanged children make no API call,
  // so without this a closed failed tab would hold its slot for good.
  forgetClosed(panes) {
    for (const [key, entry] of [...this.tabs]) {
      if (panes.get(entry.pane)?.tokens?.["subagent-run"] !== key) { this.tabs.delete(key); this.dismissed.add(key); }
    }
  }

  // Remove a finished child's viewer. Close the whole tab only if the viewer
  // is alone in it; panes the owner added to the tab are left running.
  async closeViewer(entry, panes) {
    const viewer = panes.get(entry.pane);
    if (!viewer) return;
    const shared = [...panes.values()].some(p => p.tab_id === viewer.tab_id && p.pane_id !== entry.pane);
    this.guard();
    await this.cli(shared ? ["pane", "close", entry.pane] : ["tab", "close", viewer.tab_id]);
  }

  // One reconciliation pass. Errors for a single tab never block the others.
  async sync(children, { waitingRunIds = new Set(), wrapUp = false } = {}) {
    if (this.stopping) return;
    const byKey = new Map(children.map(c => [c.key, c]));
    let panes; // one snapshot per pass, fetched only when needed
    const live = () => (panes ??= this.livePanes());
    const wanted = children.filter(c => !this.tabs.has(c.key) && !this.dismissed.has(c.key) && isLive(c.state));
    if (wanted.length && this.tabs.size >= this.max) {
      try { this.forgetClosed(await live()); } catch { panes = undefined; }
    }
    for (const child of wanted) {
      if (this.tabs.size >= this.max || this.stopping) break;
      try { await this.open(child); } catch { this.dismissed.add(child.key); }
    }
    for (const [key, entry] of [...this.tabs]) {
      const child = byKey.get(key);
      if (!child) continue;
      if (this.stopping) break;
      try {
        await this.report(entry, child, waitingRunIds.has(child.key.includes("#") ? child.key : child.runId));
        if (wrapUp && (child.state === "complete" || child.state === "completed")) {
          await this.closeViewer(entry, await live());
          this.tabs.delete(key);
          this.dismissed.add(key);
        }
      } catch (error) {
        // A tab the owner closed is gone for good; don't reopen it.
        if (/not_found/.test(String(error?.message ?? error))) { this.tabs.delete(key); this.dismissed.add(key); }
      }
    }
  }
}
