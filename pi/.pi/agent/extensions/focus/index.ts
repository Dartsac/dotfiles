/**
 * focus — toggle a clutter-free transcript.
 *
 *   /focus   on:  show your messages, the assistant's text replies, failed tool calls,
 *                 and "card" tools (subagents, questions). Thinking and routine tool calls are hidden.
 *            off: everything is back
 *
 * Presentation only: tools still run, and thinking/tool results stay in the
 * session and model context. Turning focus off re-renders what was hidden.
 *
 * Works by wrapping pi's AssistantMessageComponent.updateContent (to drop
 * thinking blocks) and ToolExecutionComponent.render (to draw nothing).
 * The wrappers are installed once per process and call `state.hooks`, which
 * every load of this file replaces, so edits take effect after /reload.
 */
import type { AssistantMessage } from "@earendil-works/pi-ai";
import {
  AssistantMessageComponent,
  type ExtensionAPI,
  type ExtensionContext,
  ToolExecutionComponent,
} from "@earendil-works/pi-coding-agent";
import type { TUI } from "@earendil-works/pi-tui";

const STATUS_ID = "focus";
const WIDGET_ID = "focus-tui-handle";
const PATCHED = Symbol.for("pi-focus-extension.patched.v2");
const ORIGINAL = Symbol.for("pi-focus-extension.original-message");

/** Tools whose rendered card is the point (not clutter): always shown, even in focus mode. */
const ALWAYS_VISIBLE_TOOLS = new Set(["subagent", "subagent_supervisor", "ask_user_question"]);

type Message = AssistantMessage & { [ORIGINAL]?: AssistantMessage };
type ToolComponent = { toolName?: string; result?: { isError?: boolean } };

interface Hooks {
  /** Message to actually render for an assistant component. */
  assistantMessage(message: Message): Message;
  /** Whether a tool component should draw nothing. */
  hideTool(tool: ToolComponent): boolean;
}

// Shared across /reload: prototype patches are installed once and must see the current state.
interface FocusState {
  focusOn: boolean;
  tui?: TUI;
  tracked: WeakSet<object>; // live assistant components, so toggling can rebuild their content
  assistants: WeakRef<AssistantMessageComponent>[];
  hooks?: Hooks;
}
const STATE_KEY = Symbol.for("pi-focus-extension.state");
const state: FocusState = ((globalThis as any)[STATE_KEY] ??= {
  focusOn: false,
  tracked: new WeakSet<object>(),
  assistants: [],
});

function withoutThinking(message: AssistantMessage): Message {
  const copy: Message = { ...message, content: message.content.filter((c) => c.type !== "thinking") };
  Object.defineProperty(copy, ORIGINAL, { value: message, enumerable: false });
  return copy;
}

// Replaced on every load of this file.
state.hooks = {
  assistantMessage(message) {
    // pi re-calls updateContent with its stored (possibly filtered) message; always start from the original.
    const original = message?.[ORIGINAL] ?? message;
    return state.focusOn && original?.content ? withoutThinking(original) : original;
  },
  hideTool(tool) {
    if (!state.focusOn) return false;
    if (tool.result?.isError) return false; // failures (including aborted/errored turns) stay visible
    return !ALWAYS_VISIBLE_TOOLS.has(tool.toolName ?? "");
  },
};

function installPatches(): void {
  const assistantProto = AssistantMessageComponent.prototype as any;
  const toolProto = ToolExecutionComponent.prototype as any;
  if (assistantProto[PATCHED]) return;
  assistantProto[PATCHED] = true;

  const originalUpdate = assistantProto.updateContent;
  assistantProto.updateContent = function (message: Message, ...rest: unknown[]) {
    if (!state.tracked.has(this)) {
      state.tracked.add(this);
      state.assistants.push(new WeakRef(this));
    }
    const shown = state.hooks ? state.hooks.assistantMessage(message) : message;
    return originalUpdate.call(this, shown, ...rest);
  };

  const originalRender = toolProto.render;
  toolProto.render = function (width: number) {
    if (state.hooks?.hideTool(this)) return [];
    return originalRender.call(this, width);
  };
}

function refresh(): void {
  state.assistants = state.assistants.filter((ref) => {
    const component = ref.deref();
    if (!component) return false;
    component.invalidate(); // re-runs updateContent with the original message
    return true;
  });
  state.tui?.requestRender(true);
}

function applyStatus(ctx: ExtensionContext): void {
  ctx.ui.setStatus(STATUS_ID, state.focusOn ? ctx.ui.theme.fg("accent", "◎ focus") : undefined);
}

export default function (pi: ExtensionAPI) {
  installPatches();

  pi.on("session_start", async (_event, ctx) => {
    if (!ctx.hasUI) return;
    // Invisible widget, used only to get a handle on the TUI for full redraws.
    ctx.ui.setWidget(WIDGET_ID, (handle) => {
      state.tui = handle;
      return { render: () => [], invalidate: () => {} };
    });
    applyStatus(ctx);
  });

  pi.registerCommand("focus", {
    description: "Toggle focus mode: hide thinking and routine tool calls",
    handler: async (_args, ctx) => {
      state.focusOn = !state.focusOn;
      refresh();
      applyStatus(ctx);
      ctx.ui.notify(
        state.focusOn ? "Focus on — thinking and routine tool calls hidden" : "Focus off — full transcript",
        "info",
      );
    },
  });
}
