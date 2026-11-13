/** Durable completion timing in the transcript, excluded from model context. */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { ENTRY_TYPE, formatTiming, registerTimer, type TimingEntry } from "./timer.ts";

export default function (pi: ExtensionAPI) {
  pi.registerEntryRenderer<TimingEntry>(ENTRY_TYPE, (entry, _options, theme) => {
    if (!entry.data) return new Text("", 0, 0);
    return new Text(theme.fg("muted", formatTiming(entry.data)), 1, 0);
  });
  registerTimer(pi);
}
