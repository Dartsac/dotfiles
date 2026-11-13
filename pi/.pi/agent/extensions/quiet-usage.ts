/** Load pi-usage with only its startup informational report suppressed.
 * The npm package remains installed/updatable but its direct extension loading
 * is disabled in settings.json to avoid duplicate timers and commands.
 * Manual /usage reports, warnings, errors, status updates and polling are intact.
 */
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { getAgentDir, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";

// Resolve from the agent dir, not this file: this file is a stow symlink into
// ~/dotfiles, and pi loads extensions from their real path.
const usageExtensionPath = join(getAgentDir(), "npm/node_modules/@mtrojnar/pi-usage/index.ts");

export function quietStartupContext(ctx: ExtensionContext): ExtensionContext {
  const ui = new Proxy(ctx.ui, {
    get(target, property, receiver) {
      if (property === "notify") return (message: string, type?: "info" | "warning" | "error") => {
        if ((type === undefined || type === "info") &&
          (message.startsWith("⚡ Usage Limits") || message === "⚡ Checking usage limits...")) return;
        target.notify(message, type);
      };
      return Reflect.get(target, property, receiver);
    },
  });
  return new Proxy(ctx, {
    get(target, property, receiver) {
      return property === "ui" ? ui : Reflect.get(target, property, receiver);
    },
  });
}

export default async function (pi: ExtensionAPI) {
  const { default: usageExtension } = await import(pathToFileURL(usageExtensionPath).href);
  // Keep the upstream package unmodified so npm updates do not erase this change.
  const adapted = new Proxy(pi, {
    get(target, property, receiver) {
      if (property === "on") return (event: string, handler: (...args: any[]) => any) => {
        return (target.on as any)(event, event === "session_start"
          ? (data: unknown, ctx: ExtensionContext) => handler(data, quietStartupContext(ctx))
          : handler);
      };
      return Reflect.get(target, property, receiver);
    },
  });
  usageExtension(adapted);
}
