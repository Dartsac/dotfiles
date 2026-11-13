# Compact footer

Personal Pi footer. Run `/reload` to load changes. `/compact-footer` toggles the default footer.

Named sessions show `[session name]` before the model and directory. Unnamed sessions keep the existing layout; renames appear on the next render.

## Data sources

- Uses the `pi-usage` extension's existing footer status. No new credentials or network requests.
- Selects data by the active provider, not by hardcoded model names.
- Recognizes Codex, Claude, Copilot, OpenCode Go/Zen, Kimi Coding, Z.AI/global/CN, Xiaomi token plans, and OpenRouter.
- Only displays data the installed usage extension actually supplies. Provider support does not guarantee numerical quota availability.
- Premium/request/rolling/weekly/monthly percentages retain their labels. OpenRouter spending/credit text is labelled `account`, not converted to a quota percentage.
- Codex/Claude two-window summaries retain the installed extension's usual 5h/7d convention. A lone available window is labelled `quota` because its identity is ambiguous. Nonstandard Codex window lengths cannot be recovered from the upstream footer text.
- Unknown providers (including Google Gemini and Vertex) show `quota: unavailable` and a provider-specific parent-session cost estimate when pricing and usage are available. This is NOT account-wide spend, a vendor invoice, or an aggregate of all child sessions. Free/unpriced models show cost unavailable rather than a misleading zero.

## Optional budget fallback

Select a provider with no quota data, then run `/footer-budget 5` for a USD 5 estimated session budget. `/footer-budget off` removes it. Positive finite amounts only.

Budget limits are stored by provider in `~/.pi/agent/compact-footer.json` (or Pi's configured agent directory). The limit persists, but usage comes from the current parent session, including entries before compaction. New sessions start their own totals. This is a display-only target, not an enforced spending cap. It is not a daily/monthly budget or account quota. Models of the same provider share this estimate.

## Limitations

The installed pi-usage extension has no public structured quota event, so this adapter parses its compact display status. Changed upstream formats remain visible as raw text; rounded reset durations remain approximate. It cannot obtain Gemini account quota from this data source. No fabricated account limits are used.

pi-rewind's checkpoint count is shown right-aligned on the second line with a ↺ icon (replacing its `◆`) instead of taking its own row; it is hidden if the terminal is too narrow to fit it. Other extensions' operational statuses remain visible below the two main lines. Narrow terminals truncate lines safely. The normal Pi footer can be restored with `/compact-footer` or by removing this extension directory.

Tests: `node --test ~/.pi/agent/extensions/compact-footer/format.test.ts` (Node with TypeScript stripping).
