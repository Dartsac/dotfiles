// Background subagents as Herdr tabs: one read-only pi-subagents viewer per
// child while it runs. The tab is not a Herdr agent: the sidebar shows the
// child in a tree under its parent instead (treeTokens, faces.py).
import fs from "node:fs";
import path from "node:path";
import { clean } from "./supervision.mjs";

export const MAX_TABS = 8;
const SOURCE = "dotfiles:subagent";
const LIVE = new Set(["queued", "running", "pending"]);
const SUCCEEDED = new Set(["complete", "completed"]);
// The sidebar tree under a parent: at most this many rows, the last one
// "+N more" when there are more children. config.base.toml has a row per token.
export const TREE_ROWS = 6;
// Each child's state as the face it wears (faces/characters.py STATES).
const TREE_STATE = { running: "working", queued: "idle", pending: "idle", failed: "blocked", paused: "unknown", stopped: "unknown" };
const RUN_ID = /^[A-Za-z0-9_-]+$/;

function readStatus(dir) {
  try { return JSON.parse(fs.readFileSync(path.join(dir, "status.json"), "utf8")); } catch { return undefined; }
}

// Children of this parent session, read from pi-subagents' lifecycle files.
// Workflow roots are containers: their steps point at each child's own run.
// Other roots (single/parallel/chain) contain their children as steps.
// A foreground workflow has no root here, only its children's own runs, each
// naming the workflow in parentWorkflowRunId: those come back marked
// `foreground`, for the sidebar tree only (the parent is busy in that tool call).
export function scanChildren(asyncRoot, sessionIds) {
  const owned = new Set(sessionIds.filter(Boolean));
  let dirs;
  try { dirs = fs.readdirSync(asyncRoot, { withFileTypes: true }).filter(d => d.isDirectory()); } catch { return []; }
  const statuses = dirs.map(dir => [dir, readStatus(path.join(asyncRoot, dir.name))]).filter(([, s]) => s && owned.has(s.sessionId));
  // A workflow child's first status lacks parentWorkflowRunId, so for a
  // moment it also looks like a run of its own: list it once, by its workflow.
  const inWorkflow = new Set(statuses.flatMap(([, s]) => s.mode === "workflow" ? (s.steps ?? []).map(step => step.runId) : []));
  const children = [];
  for (const [dir, root] of statuses) {
    if (inWorkflow.has(root.runId)) continue;
    const parent = root.parentWorkflowRunId;
    if (parent && (!RUN_ID.test(parent) || readStatus(path.join(asyncRoot, parent)))) continue; // listed by its root
    const foreground = !!parent;
    const roots = typeof root.sessionRoot === "string" ? [root.sessionRoot] : [];
    (root.steps ?? []).forEach((step, index) => {
      if (root.mode === "workflow") {
        if (typeof step.runId !== "string" || !RUN_ID.test(step.runId)) return;
        const asyncDir = path.join(asyncRoot, step.runId);
        const child = readStatus(asyncDir);
        const state = child?.state ?? step.status ?? "queued";
        children.push({
          key: step.runId, runId: step.runId, asyncDir, roots,
          name: clean(step.workflowKey || step.agent || "subagent", 40),
          agent: clean(step.agent || "subagent", 40), title: clean(step.label, 60),
          state, index: 0,
          // The workflow's launch time first: the child's own arrives a scan
          // later and would reorder the tree's rows.
          startedAt: step.startedAt ?? child?.startedAt, foreground,
          endedAt: isLive(state) ? undefined : child?.endedAt ?? step.endedAt ?? child?.lastUpdate ?? root.lastUpdate,
        });
      } else {
        const several = (root.steps?.length ?? 0) > 1;
        const state = several ? (step.status ?? root.state) : root.state;
        children.push({
          key: several ? `${root.runId}#${index}` : root.runId, runId: root.runId,
          asyncDir: path.join(asyncRoot, dir.name), roots, index,
          name: clean((!several && root.workflowKey) || step.agent || "subagent", 40) + (several ? `-${index + 1}` : ""),
          agent: clean(step.agent || "subagent", 40), title: clean(step.label, 60),
          state,
          startedAt: step.startedAt ?? root.startedAt, foreground,
          endedAt: isLive(state) ? undefined : step.endedAt ?? root.endedAt ?? root.lastUpdate,
        });
      }
    });
  }
  const unique = new Map(children.map(c => [c.key, c]));
  return [...unique.values()].sort((a, b) => a.key.localeCompare(b.key));
}

export const isLive = state => LIVE.has(state);

// Shown in the tree: a live child, and one that ended without success (failed,
// paused, stopped) after `doneAt`, the last moment the parent's whole job was
// seen finished (0: not yet). A succeeded child leaves as soon as it ends.
// One with no end time is kept only until the first finished job.
const shownInTree = (c, doneAt) => isLive(c.state)
  || (!SUCCEEDED.has(c.state) && (c.endedAt === undefined ? doneAt === 0 : c.endedAt > doneAt));

// The parent's tree tokens, child1..child<rows>: "<face state> <name>", or
// "more <n>" in the last row, or null for an unused row. It lists the children
// that still matter (shownInTree), in the order they started. faces.py draws them.
export function treeTokens(children, doneAt = 0, rows = TREE_ROWS) {
  const shown = children.filter(c => shownInTree(c, doneAt))
    .sort((a, b) => (a.startedAt ?? Infinity) - (b.startedAt ?? Infinity) || a.key.localeCompare(b.key));
  const line = c => `${TREE_STATE[c.state] ?? "unknown"} ${c.name}`;
  const lines = shown.length > rows ? [...shown.slice(0, rows - 1).map(line), `more ${shown.length - rows + 1}`] : shown.map(line);
  return Object.fromEntries(Array.from({ length: rows }, (_, i) => [`child${i + 1}`, lines[i] ?? null]));
}

// A child with a tab that sync is no longer given, read from its own run.
// pi-subagents writes a workflow step's first status without
// parentWorkflowRunId, then the runner adds it: a poll in that window opens a
// tab for a foreground workflow's child, which then counts as foreground and
// gets no tab. Without this the tab would never hear that the child ended.
export function readChild(asyncRoot, key) {
  const [runId, index] = key.split("#");
  if (!RUN_ID.test(runId)) return undefined;
  const status = readStatus(path.join(asyncRoot, runId));
  if (!status) return undefined;
  const state = index === undefined ? status.state : status.steps?.[Number(index)]?.status ?? status.state;
  return typeof state === "string" ? { key, runId, state } : undefined;
}

// Folders a child's viewer may read session files from: pi-subagents' own rule
// (extension/index.js trustedSessionRoots): the parent session file's folder
// (`<session>.jsonl` -> `<session>/`), the configured defaultSessionDir, plus a
// run's recorded sessionRoot. Single-step runs record none, so the parent-derived
// folder is what makes their sessions readable.
export function viewerSessionRoots(child, parentSessionFile, defaultSessionDir) {
  const roots = [...(child.roots ?? [])];
  if (typeof parentSessionFile === "string" && parentSessionFile.endsWith(".jsonl")) {
    roots.push(path.join(path.dirname(parentSessionFile), path.basename(parentSessionFile, ".jsonl")));
  }
  if (typeof defaultSessionDir === "string" && defaultSessionDir) roots.push(path.resolve(defaultSessionDir));
  return [...new Set(roots.map(root => path.resolve(root)))];
}

export class ChildTabs {
  // deps: cli(args) -> parsed JSON result, rpc(method, params), viewer: { launcher, env(child) }
  // lookup(key): a tracked child the scan doesn't list (readChild), or undefined.
  constructor({ cli, rpc, viewer, workspace, parentPane, cwd, max = MAX_TABS, lookup = () => undefined }) {
    Object.assign(this, { cli, rpc, viewer, workspace, parentPane, cwd, max, lookup });
    this.tabs = new Map(); // key -> { pane, tab, release }
    this.dismissed = new Set();
    this.seq = Date.now() * 1000;
  }

  // Re-attach to tabs a previous runtime of this parent opened (e.g. after /reload).
  // One that runtime reported as a Herdr agent is released (see sync).
  adopt(snapshot) {
    for (const pane of snapshot.panes ?? []) {
      const t = pane.tokens ?? {};
      if (t["subagent-parent"] === this.parentPane && t["subagent-run"] && !this.tabs.has(t["subagent-run"])) {
        this.tabs.set(t["subagent-run"], { pane: pane.pane_id, tab: pane.tab_id, release: !!pane.agent });
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
      // Tokens only, no agent report: the child is in its parent's tree, not
      // an entry of its own in the sidebar.
      await this.rpc("pane.report_metadata", {
        pane_id: pane, source: SOURCE, tokens: { "subagent-run": child.key, "subagent-parent": this.parentPane }, seq: ++this.seq,
      });
    } catch (error) {
      // Remove the half-made viewer; the caller won't retry this child. Same
      // rule as cleanup: the whole tab only if the viewer is alone in it, and
      // nothing at all if Herdr's layout can't be read.
      if (!this.stopped) await this.livePanes().then(panes => this.closeViewer({ pane }, panes)).catch(() => {});
      throw error;
    }
    const entry = { pane, tab, release: false };
    this.tabs.set(child.key, entry);
    return entry;
  }

  // Herdr's panes by id, for the checks below that need the real layout.
  async livePanes() {
    const { snapshot } = await this.rpc("session.snapshot", {});
    return new Map((snapshot?.panes ?? []).map(p => [p.pane_id, p]));
  }

  // Forget tabs the owner closed: the pane is gone, or its id now belongs to a
  // pane that isn't this child's viewer. Unchanged children make no API call,
  // so without this a tab closed while its child runs would hold its slot.
  forgetClosed(panes) {
    for (const [key, entry] of [...this.tabs]) {
      if (panes.get(entry.pane)?.tokens?.["subagent-run"] !== key) { this.tabs.delete(key); this.dismissed.add(key); }
    }
  }

  // Remove an ended child's viewer. Close the whole tab only if the viewer
  // is alone in it; panes the owner added to the tab are left running.
  async closeViewer(entry, panes) {
    const viewer = panes.get(entry.pane);
    if (!viewer) return;
    const shared = [...panes.values()].some(p => p.tab_id === viewer.tab_id && p.pane_id !== entry.pane);
    this.guard();
    await this.cli(shared ? ["pane", "close", entry.pane] : ["tab", "close", viewer.tab_id]);
  }

  // One reconciliation pass: open a tab for each new live background child,
  // close the tab of each child that ended, whatever the outcome. Errors for
  // a single tab never block the others.
  async sync(children) {
    if (this.stopping) return;
    const byKey = new Map(children.map(c => [c.key, c]));
    let panes; // one snapshot per pass, fetched only when needed
    const live = () => (panes ??= this.livePanes());
    const wanted = [...byKey.values()].filter(c => !c.foreground && !this.tabs.has(c.key) && !this.dismissed.has(c.key) && isLive(c.state));
    if (wanted.length && this.tabs.size >= this.max) {
      try { this.forgetClosed(await live()); } catch { panes = undefined; }
    }
    for (const child of wanted) {
      if (this.tabs.size >= this.max || this.stopping) break;
      try { await this.open(child); } catch { this.dismissed.add(child.key); }
    }
    for (const [key, entry] of [...this.tabs]) {
      if (this.stopping) break;
      try {
        if (entry.release) {
          this.guard();
          await this.rpc("pane.release_agent", { pane_id: entry.pane, source: SOURCE, agent: "subagent", seq: ++this.seq });
          entry.release = false;
        }
        const child = byKey.get(key) ?? this.lookup(key);
        if (!child || isLive(child.state)) continue;
        await this.closeViewer(entry, await live());
        this.tabs.delete(key);
        this.dismissed.add(key);
      } catch (error) {
        // A tab the owner closed is gone for good; don't reopen it.
        if (/not_found/.test(String(error?.message ?? error))) { this.tabs.delete(key); this.dismissed.add(key); }
        panes = undefined; // read the layout afresh for the next tab
      }
    }
  }
}
