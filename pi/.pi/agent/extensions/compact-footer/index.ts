/** Compact account quota + context footer. Reuses @mtrojnar/pi-usage's status.
 * /compact-footer toggles back to the standard footer.
 * No credentials, polling, or vendor calls. pi-usage still owns quota refresh.
 */
import { homedir } from "node:os";
import { relative, isAbsolute, sep, join } from "node:path";
import { readFileSync, writeFileSync } from "node:fs";
import { getAgentDir, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import { bar, plain, selectedQuota, sessionSpend } from "./format.ts";

// Statuses this footer renders itself; all others are passed through on their own lines.
const USAGE_STATUS = "pi-usage";
const REWIND_STATUS = "rewind";

function displayCwd(cwd: string): string {
  const rel = relative(homedir(), cwd);
  if (rel === "") return "~";
  return !isAbsolute(rel) && rel !== ".." && !rel.startsWith(`..${sep}`) ? `~${sep}${rel}` : cwd;
}

export default function (pi: ExtensionAPI) {
  let enabled = true;
  const configPath = join(getAgentDir(), "compact-footer.json");
  let budgets: Record<string, number> = {};
  /** Budgets saved in the config file; none if there is no file. Throws if the file cannot be read. */
  function readBudgets(): Record<string, number> {
    let text: string;
    try { text = readFileSync(configPath, "utf8"); }
    catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") return {};
      throw error;
    }
    const value = JSON.parse(text);
    return Object.fromEntries(Object.entries(value.sessionBudgetsUSD ?? {}).filter(([, n]) => typeof n === "number" && Number.isFinite(n) && n > 0)) as Record<string, number>;
  }
  function loadBudgets(ctx: ExtensionContext) {
    try { budgets = readBudgets(); }
    catch (error) { ctx.ui.notify(`Cannot read ${configPath}: ${error}`, "warning"); }
  }
  function install(ctx: ExtensionContext) {
    if (ctx.mode !== "tui") return;
    if (!enabled) { ctx.ui.setFooter(undefined); return; }
    // Fixed for the session: install() re-runs on every session_start.
    const cwd = displayCwd(ctx.cwd);
    // Session entries are append-only, so the spend total only changes when they grow.
    let spend: { count: number; provider: string; cost: number | undefined } | undefined;
    const cachedSpend = (provider: string) => {
      const entries = ctx.sessionManager.getEntries();
      if (!spend || spend.count !== entries.length || spend.provider !== provider) {
        spend = { count: entries.length, provider, cost: sessionSpend(entries, provider) };
      }
      return spend.cost;
    };
    ctx.ui.setFooter((tui, theme, footerData) => {
      const unsubscribe = footerData.onBranchChange(() => tui.requestRender());
      return {
        dispose: unsubscribe,
        invalidate() {},
        render(width: number): string[] {
          const model = ctx.model;
          const provider = model?.provider ?? "";
          const statuses = footerData.getExtensionStatuses();
          const usage = statuses.get(USAGE_STATUS) ?? "";
          const quota = selectedQuota(usage, provider);
          const gauge = (label: string, percent: number | undefined, context = false) => {
            if (percent === undefined || !Number.isFinite(percent)) return theme.fg("dim", `${label}: N/A`);
            const color = context ? (percent > 80 ? "error" : percent >= 70 ? "warning" : "success") : (percent >= 90 ? "error" : percent >= 80 ? "warning" : "success");
            return `${label}: ${theme.fg(color, `${bar(percent)} ${Math.round(percent)}%`)}`;
          };
          const parts: string[] = [];
          if (quota) {
            if (quota.limited) parts.push(theme.fg("error", "limited"));
            for (const window of quota.windows) {
              parts.push(window.raw !== undefined
                ? theme.fg("dim", `${window.label}: ${window.raw}`)
                : gauge(window.label, window.percent) + (window.reset ? theme.fg("dim", ` reset ${window.reset}`) : ""));
            }
          } else {
            parts.push(theme.fg("dim", "quota: unavailable"));
            const cost = cachedSpend(provider);
            // Zero-priced or unpriced registry models do not supply a useful USD estimate.
            const pricing = model?.cost;
            const priced = pricing && Object.values(pricing).some(n => typeof n === "number" && n > 0);
            const budget = budgets[provider];
            if (cost !== undefined && priced) {
              parts.push(budget
                ? gauge("session budget (est.)", cost / budget * 100) + theme.fg("dim", ` $${cost.toFixed(3)}/$${budget}`)
                : theme.fg("dim", `session cost (est.): $${cost.toFixed(3)}`));
            } else {
              parts.push(theme.fg("dim", "session cost: unavailable"));
            }
          }
          parts.push(gauge("ctx", ctx.getContextUsage()?.percent ?? undefined, true));
          const thinking = model?.reasoning ? ` ${pi.getThinkingLevel()}` : "";
          const sessionName = ctx.sessionManager.getSessionName();
          const session = sessionName ? theme.fg("accent", `[${plain(sessionName)}]`) + theme.fg("dim", " · ") : "";
          const details = session + theme.fg("accent", `${model?.id ?? "no-model"}${thinking} (${model?.provider ?? "unknown"})`) + theme.fg("dim", ` · ${cwd}`);
          // pi-rewind's checkpoint count sits right-aligned on the details line, not its own row.
          const rewindStatus = statuses.get(REWIND_STATUS);
          const rewind = rewindStatus ? theme.fg("muted", "↺ " + plain(rewindStatus).replace(/^\s*◆\s*/, "")) : "";
          const rw = rewind ? visibleWidth(rewind) : 0;
          let second: string;
          if (rewind && rw + 2 <= width) {
            const left = truncateToWidth(details, width - rw - 2, "…");
            second = left + " ".repeat(width - visibleWidth(left) - rw) + rewind;
          } else {
            second = truncateToWidth(details, width, "…");
          }
          const lines = [truncateToWidth(parts.join(theme.fg("dim", " | ")), width, "…"), second];
          // Keep other extensions' operational statuses visible (e.g. watchdog).
          for (const [key, value] of statuses) if (key !== USAGE_STATUS && key !== REWIND_STATUS) lines.push(truncateToWidth(plain(value), width, "…"));
          return lines;
        },
      };
    });
  }
  pi.on("session_start", (_event, ctx) => { loadBudgets(ctx); install(ctx); });
  pi.registerCommand("footer-budget", {
    description: "Set current provider's estimated session USD budget: /footer-budget 5 (or off)",
    handler: async (args, ctx) => {
      const provider = ctx.model?.provider;
      if (!provider) return;
      const input = args.trim();
      const amount = input === "off" ? undefined : Number(input);
      if (amount !== undefined && (!Number.isFinite(amount) || amount <= 0)) {
        ctx.ui.notify("Usage: /footer-budget 5 or /footer-budget off. This is a display-only session budget, not an account quota or spending cap.", "info");
        return;
      }
      // Start from the file, not this session's copy: another running pi may have saved a budget
      // since this one loaded. A file that cannot be read is left alone rather than overwritten.
      let next: Record<string, number>;
      try { next = readBudgets(); }
      catch (error) { ctx.ui.notify(`Budget not saved: cannot read ${configPath}: ${error}`, "error"); return; }
      if (amount === undefined) delete next[provider]; else next[provider] = amount;
      try { writeFileSync(configPath, JSON.stringify({ sessionBudgetsUSD: next }, null, 2) + "\n", { mode: 0o600 }); }
      catch (error) { ctx.ui.notify(`Budget not saved: ${error}`, "error"); return; }
      budgets = next;
      install(ctx);
      ctx.ui.notify(`Session budget for ${provider}: ${amount === undefined ? "off" : `$${amount}`}. Display only; does not enforce a spending cap.`, "info");
    },
  });
  pi.on("model_select", (_event, ctx) => install(ctx));
  pi.registerCommand("compact-footer", {
    description: "Toggle the compact quota/context footer",
    handler: async (_args, ctx) => { enabled = !enabled; install(ctx); },
  });
}
