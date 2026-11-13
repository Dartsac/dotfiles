/**
 * Custom Header Extension
 *
 * Replaces the built-in startup header with a custom logo and the pi version.
 * Edit the `buildHeader()` function below to change what's shown at startup.
 *
 * Usage: Just edit this file and run /reload in pi.
 * /builtin-header shows the built-in header for the current session only.
 * To restore it for good: rename/delete this file and /reload.
 */

import { VERSION, type ExtensionAPI, type Theme } from "@earendil-works/pi-coding-agent";
import { truncateToWidth } from "@earendil-works/pi-tui";

const LOGO = [
  "   ███████████████████████████╗  ",
  "   ╚══██████╔════════██████╔══╝  ",
  "      ██████║        ██████║     ",
  "      ██████║        ██████║     ",
  "      ██████║        ██████║     ",
  "      ██████║        ██████║     ",
  "      ██████║        ██████║     ",
  "      ██████║        ██████║     ",
  "   ████████████╗  ████████████╗  ",
  "   ╚═══════════╝  ╚═══════════╝  ",
];

/**
 * Header lines: the custom logo and the pi version. Use /builtin-header for
 * Pi's default header and its current keybinding hints.
 */
function buildHeader(theme: Theme): string[] {
  return [
    "",
    ...LOGO.map(line => theme.bold(theme.fg("accent", line))),
    "",
    theme.bold(theme.fg("accent", "pi")) + theme.fg("dim", ` v${VERSION}`),
  ];
}

export default function(pi: ExtensionAPI) {
  pi.on("session_start", async (_event, ctx) => {
    if (ctx.mode !== "tui") return;

    ctx.ui.setHeader((_tui, theme) => {
      // The header only changes with width or theme; invalidate() covers theme changes.
      let cache: { width: number; lines: string[] } | undefined;
      return {
        render(width: number): string[] {
          if (cache?.width !== width) {
            cache = { width, lines: buildHeader(theme).map(line => truncateToWidth(line, width)) };
          }
          return cache.lines;
        },
        invalidate() { cache = undefined; },
      };
    });
  });

  // The custom header returns with the next session: session_start sets it again.
  pi.registerCommand("builtin-header", {
    description: "Show the built-in startup header for this session",
    handler: async (_args, ctx) => {
      ctx.ui.setHeader(undefined);
      ctx.ui.notify("Built-in header shown for this session", "info");
    },
  });
}
