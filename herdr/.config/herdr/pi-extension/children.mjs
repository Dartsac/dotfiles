// A parent's subagents, read from pi-subagents' files and the parent's tool
// events, for the sidebar tree under the parent (treeTokens, faces.py), and
// background subagents as Herdr tabs: one read-only pi-subagents viewer per
// child while it runs. The tab is not a Herdr agent.
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
// A succeeded child shows only to hold a subagent of its own that is still shown.
const TREE_STATE = { running: "working", queued: "idle", pending: "idle", failed: "blocked", paused: "unknown", stopped: "unknown", complete: "done", completed: "done" };
const RUN_ID = /^[A-Za-z0-9_-]+$/;
// A subagent's own subagent's tree token starts with this (faces.py SUB).
const SUB = "sub ";
// The parent's own subagents; the rest are theirs, at depth 2.
const topLevel = c => (c.depth ?? 1) === 1;

function readStatus(dir) {
  try { return JSON.parse(fs.readFileSync(path.join(dir, "status.json"), "utf8")); } catch { return undefined; }
}

const nonEmpty = value => typeof value === "string" && value ? value : undefined;

// None when `parent` is missing or was not given.
const subfolders = parent => {
  try { return fs.readdirSync(parent, { withFileTypes: true }).filter(d => d.isDirectory()).map(d => path.join(parent, d.name)); } catch { return []; }
};
// [run folder, status] for each run in `parent`.
const statusesIn = parent => subfolders(parent).map(dir => [dir, readStatus(dir)]).filter(([, s]) => s);

// Children of this parent session, read from pi-subagents' lifecycle files,
// each with its depth: 1 for the parent's own subagents, 2 for theirs, which
// also name the subagent they belong to (`parent`, its key). A subagent's Pi
// takes its session file as its session id (pi-subagents'
// resolveCurrentSessionId), so its own runs name that file as their session.
// Depth stops at 2, pi-subagents' default nesting limit. A subagent's own
// background runs are not beside the parent's: pi-subagents writes them under
// `nestedRoot`, as <root run>/<run> (supervision.mjs nestedRunsRoot).
export function scanChildren(asyncRoot, sessionIds, nestedRoot) {
  const statuses = statusesIn(asyncRoot);
  const allRuns = [...statuses, ...subfolders(nestedRoot).flatMap(statusesIn)];
  const owned = new Set(sessionIds.filter(Boolean));
  const top = childrenOf(statuses, owned).map(c => ({ ...c, depth: 1 }));
  const keyBySessionFile = new Map(top.filter(c => c.sessionFile && !owned.has(c.sessionFile)).map(c => [c.sessionFile, c.key]));
  const keys = new Set(top.map(c => c.key));
  const nested = childrenOf(allRuns, new Set(keyBySessionFile.keys()))
    .filter(c => !keys.has(c.key)).map(c => ({ ...c, depth: 2, parent: keyBySessionFile.get(c.session) }));
  return [...top, ...nested].sort((a, b) => a.key.localeCompare(b.key));
}

// The children of runs whose session is in `owned`, each with `session`, the
// session that started it, and `sessionFile`, its own session, when recorded.
// Workflow roots are containers: their steps point at each child's own run.
// Other roots (single/parallel/chain) contain their children as steps.
// A foreground workflow has no root here, only its children's own runs, each
// naming the workflow in parentWorkflowRunId: those come back marked
// `foreground`, for the sidebar tree only (the parent is busy in that tool call).
// Each run's own runs (a workflow's children) are in the same folder as it.
function childrenOf(all, owned) {
  const statuses = all.filter(([, s]) => owned.has(s.sessionId));
  // A workflow child's first status lacks parentWorkflowRunId, so for a
  // moment it also looks like a run of its own: list it once, by its workflow.
  const inWorkflow = new Set(statuses.flatMap(([, s]) => s.mode === "workflow" ? (s.steps ?? []).map(step => step.runId) : []));
  const children = [];
  for (const [dir, root] of statuses) {
    const runsFolder = path.dirname(dir);
    if (inWorkflow.has(root.runId)) continue;
    const parent = root.parentWorkflowRunId;
    if (parent && (!RUN_ID.test(parent) || readStatus(path.join(runsFolder, parent)))) continue; // listed by its root
    const foreground = !!parent;
    const roots = typeof root.sessionRoot === "string" ? [root.sessionRoot] : [];
    (root.steps ?? []).forEach((step, index) => {
      if (root.mode === "workflow") {
        if (typeof step.runId !== "string" || !RUN_ID.test(step.runId)) return;
        const asyncDir = path.join(runsFolder, step.runId);
        const child = readStatus(asyncDir);
        const state = child?.state ?? step.status ?? "queued";
        children.push({
          key: step.runId, runId: step.runId, asyncDir, roots, session: root.sessionId,
          sessionFile: nonEmpty(child?.steps?.[0]?.sessionFile) ?? nonEmpty(child?.sessionFile) ?? nonEmpty(step.sessionFile),
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
          asyncDir: dir, roots, index, session: root.sessionId,
          sessionFile: nonEmpty(step.sessionFile) ?? (several ? undefined : nonEmpty(root.sessionFile)),
          name: clean((!several && root.workflowKey) || step.agent || "subagent", 40) + (several ? `-${index + 1}` : ""),
          agent: clean(step.agent || "subagent", 40), title: clean(step.label, 60),
          state,
          startedAt: step.startedAt ?? root.startedAt, foreground,
          endedAt: isLive(state) ? undefined : step.endedAt ?? root.endedAt ?? root.lastUpdate,
        });
      }
    });
  }
  return [...new Map(children.map(c => [c.key, c])).values()];
}

export const isLive = state => LIVE.has(state);
// An ended child that the parent's last finished job, at `doneAt` (0: none
// yet), has left behind: it ended by then. One with no end time recorded is
// left behind by the first finished job.
const leftBehind = (c, doneAt) => !isLive(c.state) && (c.endedAt === undefined ? doneAt !== 0 : c.endedAt <= doneAt);

// A subagent's foreground runs (async: false), at depth 2. They have no status
// file: pi-subagents writes an event for each as it starts and as it returns,
// in nested-subagent-events/<root run>-<token>/events/<ts>-<id>.json, naming
// the subagent that called it (parentRunId, its run id, and parentStepIndex,
// its step), as pi-subagents' writeNestedForegroundEvent writes them
// (foreground/subagent-executor.js). It looks under the subagents among
// `children` that the tree may still show: those the parent's last finished
// job has not left behind (leftBehind; a succeeded one stays to hold a failed
// run of its own). Event folders last written before the first of them
// started are skipped: pi-subagents never prunes them. Background runs'
// events (with an asyncDir) are left to their status files. A run whose
// subagent ended without reporting its end has stopped.
export function nestedForeground(eventsRoot, children, doneAt = 0) {
  const parents = children.filter(c => topLevel(c) && !leftBehind(c, doneAt));
  if (!parents.length) return [];
  // A step as the events name it: unlike a child's key, a single run's
  // has "#0".
  const stepOf = (runId, index) => `${runId}#${index ?? 0}`;
  const byStep = new Map(parents.map(p => [stepOf(p.runId, p.index), p]));
  const since = Math.min(...parents.map(p => p.startedAt ?? 0)) - 1000;
  const runs = new Map(); // run id -> [its subagent, its latest summary]
  for (const route of subfolders(eventsRoot)) {
    const folder = path.join(route, "events");
    let names;
    try {
      if (fs.statSync(folder).mtimeMs < since) continue;
      names = fs.readdirSync(folder).filter(n => n.endsWith(".json")).sort(); // in time order
    } catch { continue; }
    for (const name of names) {
      let lines;
      try { lines = fs.readFileSync(path.join(folder, name), "utf8").split("\n").filter(Boolean); } catch { continue; }
      for (const line of lines) {
        let event;
        try { event = JSON.parse(line); } catch { continue; }
        const run = event?.child, parent = byStep.get(stepOf(event?.parentRunId, event?.parentStepIndex));
        if (!parent || typeof run?.id !== "string" || run.asyncDir || run.mode !== "single") continue;
        const earlier = runs.get(run.id)?.[1];
        if (earlier && !isLive(earlier.state) && isLive(run.state)) continue; // an end is final
        runs.set(run.id, [parent, run]);
      }
    }
  }
  return [...runs.values()].map(([parent, run]) => {
    const orphaned = isLive(run.state) && !isLive(parent.state);
    const state = orphaned ? "stopped" : typeof run.state === "string" ? run.state : "running";
    const agent = clean(run.agent || "subagent", 40);
    return {
      key: run.id, runId: run.id, index: 0, depth: 2, parent: parent.key, foreground: true, name: agent, agent, title: "",
      state, startedAt: run.startedAt,
      endedAt: orphaned ? parent.endedAt : isLive(state) ? undefined : run.endedAt ?? run.lastUpdate,
    };
  }).sort((a, b) => a.key.localeCompare(b.key));
}

// The parent's own foreground single runs, from Pi's tool events: they run in
// the parent's process and write no status file. A subagent call counts once
// pi-subagents streams its progress (details.mode "single" with the run's id),
// which a background launch, a workflow or a management call never does; it
// ends with the call: stopped, paused, failed on an error or a non-zero exit,
// else complete. One detached from its call (/subagents-detach) goes on
// running, marked `detached`, until pi-subagents reports its end
// (detachedEnded): no tool call holds the parent any more, so the parent's
// job waits for it as for a background child. One the session recorded before
// a /reload comes back ended (restore). What the parent will no longer show
// (forget) is dropped.
export class ForegroundRuns {
  constructor() { this.calls = new Map(); } // tool call id (or saved:<run id>) -> its start time, then its child

  start(event) {
    if (event.toolName === "subagent") this.calls.set(event.toolCallId, { startedAt: Date.now() });
  }

  update(event) {
    const call = this.calls.get(event.toolCallId), details = event.partialResult?.details;
    if (!call || call.child || details?.mode !== "single" || typeof details.runId !== "string" || !details.runId) return;
    const agent = clean(event.args?.agent || details.results?.[0]?.agent || "subagent", 40);
    call.child = { key: details.runId, runId: details.runId, index: 0, depth: 1, foreground: true,
      name: agent, agent, title: "", state: "running", startedAt: call.startedAt };
  }

  // The run this call ended, if any: not one detached from it, which goes on.
  end(event) {
    const call = this.calls.get(event.toolCallId);
    if (!call) return;
    if (!call.child) { this.calls.delete(event.toolCallId); return; }
    const results = event.result?.details?.results ?? [];
    if (results.some(r => r.detached)) { call.child.detached = true; return; }
    const failed = event.isError || event.result?.isError || results.some(r => r.exitCode !== undefined && r.exitCode !== 0);
    const state = results.some(r => r.stopped) ? "stopped" : results.some(r => r.interrupted) ? "paused" : failed ? "failed" : "complete";
    return Object.assign(call.child, { state, endedAt: Date.now() });
  }

  // pi-subagents' subagent:foreground-complete, sent only for a detached run.
  // The run it ended, if any.
  detachedEnded(data) {
    const child = this.list().find(c => c.runId === data?.runId && isLive(c.state));
    if (!child) return;
    const state = ["complete", "failed", "paused", "stopped"].includes(data.state) ? data.state : data.success ? "complete" : "failed";
    return Object.assign(child, { state, endedAt: Number.isFinite(data.timestamp) ? data.timestamp : Date.now() });
  }

  // An ended run the session recorded before a /reload, as `end` or
  // `detachedEnded` returned it.
  restore(child) { this.calls.set(`saved:${child.key}`, { child }); }

  // The runs that streamed progress, live or ended.
  list() { return [...this.calls.values()].flatMap(c => c.child ? [c.child] : []); }

  // Drop the runs the parent's last finished job, at `doneAt`, left behind:
  // the tree no longer shows them, nor looks under them.
  forget(doneAt) {
    for (const [id, c] of this.calls) if (c.child && leftBehind(c.child, doneAt)) this.calls.delete(id);
  }
}

// Shown in the tree: a live child, and one that ended without success (failed,
// paused, stopped) after `doneAt`, the last moment the parent's whole job was
// seen finished (0: not yet). A succeeded child leaves as soon as it ends.
// One with no end time is kept only until the first finished job. The same at
// depth 2; a subagent is also kept while one of its own is shown (treeTokens).
const shownInTree = (c, doneAt) => isLive(c.state) || (!SUCCEEDED.has(c.state) && !leftBehind(c, doneAt));

// The parent's tree tokens, child1..child<rows>: "<face state> <name>", or
// "sub <face state> <name>" for a subagent's own subagent, or "more <n>" in the
// last row, or null for an unused row. It lists the children that still matter
// (shownInTree), in the order they started, each subagent followed by its own.
// faces.py draws them.
export function treeTokens(children, doneAt = 0, rows = TREE_ROWS) {
  const byStart = (a, b) => (a.startedAt ?? Infinity) - (b.startedAt ?? Infinity) || a.key.localeCompare(b.key);
  const shownBelow = key => children.filter(c => !topLevel(c) && c.parent === key && shownInTree(c, doneAt)).sort(byStart);
  const shown = children.filter(topLevel).sort(byStart)
    .flatMap(c => { const below = shownBelow(c.key); return below.length || shownInTree(c, doneAt) ? [c, ...below] : []; });
  const line = c => `${topLevel(c) ? "" : SUB}${TREE_STATE[c.state] ?? "unknown"} ${c.name}`;
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
  // opened: the children earlier runtimes of this parent opened a tab for (the
  // session keeps them); record(key) is called once for each new tagged tab.
  constructor({ cli, rpc, viewer, workspace, parentPane, cwd, max = MAX_TABS, lookup = () => undefined, opened = [], record = () => {} }) {
    Object.assign(this, { cli, rpc, viewer, workspace, parentPane, cwd, max, lookup, record });
    this.tabs = new Map(); // key -> { pane, tab, release }
    // The children this parent won't open a tab for (again). One whose tab was
    // tagged is never opened again, even after /reload, whether it ended or the
    // owner closed it. One whose tab failed to open is not retried by this
    // runtime; the next one tries once more.
    this.tried = new Set(opened);
    this.seq = Date.now() * 1000;
  }

  // Re-attach to tabs a previous runtime of this parent opened (e.g. after
  // /reload), from Herdr's panes by id. One that runtime reported as a Herdr
  // agent is released (see sync).
  adopt(panes) {
    for (const pane of panes.values()) {
      const t = pane.tokens ?? {}, key = t["subagent-run"];
      if (t["subagent-parent"] === this.parentPane && key && !this.tabs.has(key)) {
        this.tabs.set(key, { pane: pane.pane_id, tab: pane.tab_id, release: !!pane.agent });
        if (!this.tried.has(key)) { this.tried.add(key); this.record(key); }
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
      if (panes.get(entry.pane)?.tokens?.["subagent-run"] !== key) this.tabs.delete(key);
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

  // One reconciliation pass: open a tab for each new live background subagent
  // (none for a subagent's own subagents), close the tab of each child that
  // ended, whatever the outcome. Errors for a single tab never block the others.
  async sync(children) {
    if (this.stopping) return;
    const byKey = new Map(children.map(c => [c.key, c]));
    let panes; // one snapshot per pass, fetched only when needed
    const live = () => (panes ??= this.livePanes());
    // The first pass takes over the tabs an earlier runtime left before it opens
    // or closes anything; until Herdr's layout has been read, it does nothing.
    if (!this.adopted) {
      try { this.adopt(await live()); } catch { return; }
      this.adopted = true;
    }
    const wanted = [...byKey.values()].filter(c => !c.foreground && topLevel(c) && !this.tried.has(c.key) && isLive(c.state));
    if (wanted.length && this.tabs.size >= this.max) {
      try { this.forgetClosed(await live()); } catch { panes = undefined; }
    }
    for (const child of wanted) {
      if (this.tabs.size >= this.max || this.stopping) break;
      // Tried once in this runtime whatever happens; recorded for later ones
      // only when tagged, so a tab shutdown cuts short is opened again after.
      this.tried.add(child.key);
      if (await this.open(child).then(() => true, () => false)) this.record(child.key);
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
      } catch (error) {
        // A tab the owner closed is gone for good.
        if (/not_found/.test(String(error?.message ?? error))) this.tabs.delete(key);
        panes = undefined; // read the layout afresh for the next tab
      }
    }
  }
}
