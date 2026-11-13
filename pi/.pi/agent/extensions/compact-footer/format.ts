import { stripVTControlCharacters } from "node:util";

// pi-usage's footer is a display-only compatibility interface, not a structured API.
// Keep unknown formats visible rather than guessing or reporting zero usage.
export function plain(text: string): string {
  return stripVTControlCharacters(text).replace(/[\r\n\t]/g, " ");
}

export function bar(percent: number, size = 8): string {
  const count = Math.floor(Math.max(0, Math.min(100, percent)) / 100 * size);
  return "█".repeat(count) + "░".repeat(size - count);
}

export function readableDuration(value: string): string {
  const match = /^(\d+(?:\.\d+)?)([dhms])$/.exec(value);
  if (!match) return value;
  const minutes = Math.round(Number(match[1]) * { d: 1440, h: 60, m: 1, s: 1 / 60 }[match[2]]!);
  if (minutes >= 1440) return `${Math.floor(minutes / 1440)}d ${Math.floor(minutes % 1440 / 60)}h`;
  if (minutes >= 60) return `${Math.floor(minutes / 60)}h ${minutes % 60}m`;
  return `${minutes}m`;
}

const PROVIDER_LABELS: Record<string, string> = {
  "openai-codex": "Codex", anthropic: "Claude", "github-copilot": "Copilot",
  "opencode-go": "Go", opencode: "Zen", "kimi-coding": "Kimi", zai: "Z.AI",
  "zai-coding-cn": "Z.AI CN", "xiaomi-token-plan-ams": "Xiaomi AMS",
  "xiaomi-token-plan-cn": "Xiaomi CN", "xiaomi-token-plan-sgp": "Xiaomi SGP",
  openrouter: "OpenRouter",
};

// Cumulative parent-session estimates, including pre-compaction entries.
// No claim that these are provider invoices or account-wide totals.
export function sessionSpend(entries: readonly any[], provider: string): number | undefined {
  let total = 0;
  let found = false;
  for (const entry of entries) {
    const record = entry.type === "message" && entry.message?.role === "assistant" ? entry.message
      : entry.type === "usage" ? entry : undefined;
    if (record?.provider !== provider) continue;
    const cost = record.usage?.cost?.total;
    if (Number.isFinite(cost) && cost >= 0) {
      found = true;
      total += cost;
    }
  }
  return found ? total : undefined;
}

export type Quota = { label: string; percent?: number; reset?: string; raw?: string };
export function selectedQuota(status: string, provider: string): { limited: boolean; windows: Quota[] } | undefined {
  const label = PROVIDER_LABELS[provider];
  if (!label) return;
  const limitedPrefix = `${label} limited:`;
  const part = plain(status).replace(/^⚡\s*/, "").split(/\s*│\s*/).find(p => p.startsWith(`${label}:`) || p.startsWith(limitedPrefix));
  if (!part) return;
  const summary = part.slice(part.indexOf(":") + 1);
  const pieces = summary.split(",");
  const suffixLabel: Record<string, string> = { p: "premium", r: provider === "github-copilot" ? "requests" : "rolling", w: "weekly", m: "monthly" };
  // One available window is ambiguous: pi-usage omits missing windows.
  // Never label a lone weekly value as 5h. Two slots preserve expired '--'.
  const windows = pieces.map((piece, i) => {
    const name = (provider === "openai-codex" || provider === "anthropic") && pieces.length === 2 ? ["5h", "7d"][i] : "quota";
    const match = /^(\d+(?:\.\d+)?)%([prwm]?)(?:\/([^\s]+))?$/.exec(piece);
    return match ? { label: suffixLabel[match[2]] ?? name, percent: Number(match[1]), reset: match[3] ? readableDuration(match[3]) : undefined } : { label: provider === "openrouter" ? "account" : name, raw: piece };
  });
  return { limited: part.startsWith(limitedPrefix), windows };
}
