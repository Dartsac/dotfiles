import { clampThinkingLevel, getSupportedThinkingLevels } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Input, SelectList, truncateToWidth } from "@earendil-works/pi-tui";

type Level = ReturnType<ExtensionAPI["getThinkingLevel"]>;

const modelKey = (model: { provider: string; id: string }) => `${model.provider}/${model.id}`;

const MODEL_ROWS = 9;
const DESCRIPTION = "Pick model and thinking level (Command+M in Ghostty)";

const descriptions: Record<Level, string> = {
  off: "No thinking budget",
  minimal: "Smallest thinking budget",
  low: "Lower thinking budget",
  medium: "Balanced thinking budget",
  high: "Higher thinking budget",
  xhigh: "Extra-high thinking budget",
  max: "Maximum thinking budget",
};

export default function modelPicker(pi: ExtensionAPI) {
  let open = false;

  async function show(ctx: ExtensionContext) {
    if (ctx.mode !== "tui" || open) return;
    if (!ctx.isIdle()) {
      ctx.ui.notify("Wait for the current response to finish before changing model and thinking.", "info");
      return;
    }
    open = true;
    try {
      const available = ctx.modelRegistry.getAvailable();
      const availableKeys = new Set(available.map(modelKey));
      const scoped = ctx.scopedModels ?? [];
      const models = scoped.length
        ? scoped.filter(({ model }) => availableKeys.has(modelKey(model)))
        : available.map(model => ({ model, thinkingLevel: undefined }));
      if (!models.length) {
        ctx.ui.notify("No authenticated models available in the current scope. Check /login and /scoped-models.", "warning");
        return;
      }
      const current = ctx.model && modelKey(ctx.model);
      const initialLevel = pi.getThinkingLevel();
      const result = await ctx.ui.custom<{ index: number; level: Level } | undefined>((tui, theme, kb, done) => {
        const input = new Input({ prompt: "Search: ", placeholder: "model name or provider" });
        const listTheme = {
          selectedPrefix: (text: string) => theme.fg("accent", text),
          selectedText: (text: string) => theme.fg("accent", text),
          description: (text: string) => theme.fg("muted", text),
          scrollInfo: (text: string) => theme.fg("dim", text),
          noMatch: (text: string) => theme.fg("warning", text),
        };
        const keys = models.map(({ model }) => modelKey(model));
        const items = models.map(({ model }, index) => ({
          value: String(index),
          label: keys[index] === current ? `${keys[index]} (current)` : keys[index],
          description: model.name,
        }));
        // Lowercased once so each keystroke only does substring checks.
        const haystacks = items.map(item => `${item.label} ${item.description}`.toLowerCase());
        let visibleItems = items;
        let modelList = new SelectList(visibleItems, MODEL_ROWS, listTheme);
        modelList.setSelectedIndex(Math.max(0, keys.indexOf(current ?? "")));
        let stage: "model" | "thinking" = "model";
        let selectedIndex = 0;
        let thinkingList: SelectList;
        let thinkingItems: typeof items = [];
        function selectModel(value: string) {
          selectedIndex = Number(value);
          const { model, thinkingLevel } = models[selectedIndex];
          const levels = getSupportedThinkingLevels(model);
          if (!levels.length) return;
          const suggested = clampThinkingLevel(model, thinkingLevel ?? initialLevel);
          thinkingItems = levels.map(level => ({
            value: level,
            label: level,
            description: descriptions[level] + (level === suggested ? " (selected)" : ""),
          }));
          thinkingList = new SelectList(thinkingItems, 7, listTheme);
          thinkingList.setSelectedIndex(Math.max(0, levels.indexOf(suggested)));
          stage = "thinking";
        }
        const component = {
          capturesViewportInput: true,
          get focused() { return input.focused; },
          set focused(value: boolean) { input.focused = value; },
          render(width: number) {
            const lines = stage === "model" ? [
              theme.fg("accent", theme.bold("Model + thinking · 1/2 Choose model")),
              ...input.render(width),
              ...modelList.render(width),
              theme.fg("dim", "Type to search · ↑↓ move · Enter next · Esc cancel"),
            ] : [
              theme.fg("accent", theme.bold("Model + thinking · 2/2 Choose thinking level")),
              theme.fg("muted", items[selectedIndex].label),
              ...thinkingList.render(width),
              theme.fg("dim", "↑↓ move · Enter apply · Esc cancel · Tab back to models"),
            ];
            return lines.map(line => truncateToWidth(line, width));
          },
          invalidate() { input.invalidate(); modelList.invalidate(); thinkingList?.invalidate(); },
          handleInput(data: string) {
            if (kb.matches(data, "tui.select.cancel")) { done(undefined); return; }
            if (stage === "thinking" && kb.matches(data, "tui.input.tab")) {
              stage = "model";
            } else {
              const list = stage === "model" ? modelList : thinkingList;
              const choices = stage === "model" ? visibleItems : thinkingItems;
              // Resolve selection keys with Pi's injected manager, not a module-global copy.
              const selected = list.getSelectedItem();
              const index = choices.findIndex(item => item.value === selected?.value);
              const up = kb.matches(data, "tui.select.up");
              const down = kb.matches(data, "tui.select.down");
              const pageUp = kb.matches(data, "tui.select.pageUp");
              const pageDown = kb.matches(data, "tui.select.pageDown");
              if (kb.matches(data, "tui.select.confirm")) {
                if (selected) {
                  if (stage === "model") selectModel(selected.value);
                  else done({ index: selectedIndex, level: selected.value as Level });
                }
              } else if (choices.length && (up || down || pageUp || pageDown)) {
                const next = up ? (index - 1 + choices.length) % choices.length
                  : down ? (index + 1) % choices.length
                  : Math.max(0, Math.min(choices.length - 1, index + (pageUp ? -MODEL_ROWS : MODEL_ROWS)));
                list.setSelectedIndex(next);
              } else if (stage === "model") {
                input.handleInput(data);
                const terms = input.getValue().toLowerCase().split(/\s+/).filter(Boolean);
                visibleItems = items.filter((_, i) => terms.every(term => haystacks[i].includes(term)));
                modelList = new SelectList(visibleItems, MODEL_ROWS, listTheme);
              }
            }
            tui.requestRender();
          },
        };
        return component;
      }, { blocked: { kind: "question", message: "Choose model and thinking level" } });
      if (!result) return;
      // Do not apply a stale selection if work started while the picker was visible.
      if (!ctx.isIdle()) {
        ctx.ui.notify("Model selection cancelled because a response started. Reopen with Command+M when idle.", "warning");
        return;
      }
      const { model } = models[result.index];
      if (!await pi.setModel(model)) {
        ctx.ui.notify(`Cannot select ${modelKey(model)}: authentication is unavailable.`, "error");
        return;
      }
      pi.setThinkingLevel(result.level);
      ctx.ui.notify(`${modelKey(model)} · thinking: ${pi.getThinkingLevel()}`, "info");
    } catch (error) {
      ctx.ui.notify(`Model picker failed: ${error instanceof Error ? error.message : String(error)}`, "error");
    } finally {
      open = false;
    }
  }

  // Ghostty sends this unused chord for Command+M; tmux drops native Super modifiers.
  // Do not bind Alt+M: Option+M must no longer open the picker.
  pi.registerShortcut("ctrl+shift+alt+m", { description: DESCRIPTION, handler: show });
  pi.registerCommand("model-picker", {
    description: DESCRIPTION,
    handler: async (_args, ctx) => show(ctx),
  });
}
