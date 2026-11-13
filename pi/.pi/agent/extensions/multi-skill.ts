/**
 * multi-skill — use several skills anywhere in one prompt.
 *
 * Autocomplete (anywhere in the prompt, not just at the start):
 *   $gri        → dropdown of matching skills; picking one inserts `/skill:grill-me `
 *   /gri + Tab  → same, for a `/` typed mid-prompt (pi only auto-opens `/` at the start)
 *   Picking with Enter only inserts the skill; it never sends the prompt.
 *
 * Expansion (on send):
 *   Every `/skill:name` in the prompt is loaded. Pi natively expands only a single
 *   `/skill:name` at the very start, so this handles the other cases:
 *     - one skill mid-prompt  → standard pi skill block + your text
 *     - several skills        → one combined skill block (shows as `[skill] a, b`) + your text
 *     - prompt starts with a prompt template (`/review-loop … /skill:x`) → the template still
 *       expands normally; the skills are attached as a separate message (also `[skill] …`)
 *   Unknown names are left untouched.
 */
import { readFileSync } from "node:fs";
import { dirname } from "node:path";
import { type ExtensionAPI, getMarkdownTheme } from "@earendil-works/pi-coding-agent";
import {
  type AutocompleteItem,
  type AutocompleteProvider,
  type AutocompleteSuggestions,
  Box,
  Markdown,
  Text,
} from "@earendil-works/pi-tui";

interface SkillInfo {
  name: string;
  description?: string;
  filePath: string;
  baseDir: string;
}

const MESSAGE_TYPE = "multi-skill";
const MAX_SUGGESTIONS = 20;
const SKILL_TOKEN = /(^|[\s([{<"'`])\/skill:([A-Za-z0-9][\w.-]*)/g;
// Token being typed at the cursor. `$` needs at least one letter so plain `$`, `$5`, `$10` never open it.
const DOLLAR_AT_CURSOR = /(?:^|[\s([{<"'`])(\$[A-Za-z][\w.:-]*)$/;
const SLASH_AT_CURSOR = /(?:^|[\s([{<"'`])\/((?:skill:)?[\w.-]*)$/;

type Commands = ReturnType<ExtensionAPI["getCommands"]>;

function listSkills(commands: Commands): Map<string, SkillInfo> {
  const skills = new Map<string, SkillInfo>();
  for (const command of commands) {
    if (command.source !== "skill") continue; // pi names these `skill:<name>`
    const name = command.name.slice("skill:".length);
    if (skills.has(name)) continue;
    const filePath = command.sourceInfo.path;
    skills.set(name, { name, description: command.description, filePath, baseDir: dirname(filePath) });
  }
  return skills;
}

function listTemplateNames(commands: Commands): Set<string> {
  return new Set(commands.filter((c) => c.source === "prompt").map((c) => c.name));
}

function stripFrontmatter(content: string): string {
  const match = content.match(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/);
  return match ? content.slice(match[0].length) : content;
}

/** One skill wrapped in `tag`, matching the body pi builds for a native `/skill:name`. */
function skillSection(skill: SkillInfo, tag: string): string {
  const body = stripFrontmatter(readFileSync(skill.filePath, "utf-8")).trim();
  return `<${tag} name="${skill.name}" location="${skill.filePath}">\nReferences are relative to ${skill.baseDir}.\n\n${body}\n</${tag}>`;
}

/** Resolve a typed token to a known skill, tolerating trailing sentence punctuation (`/skill:foo.`). */
function resolveToken(raw: string, skills: Map<string, SkillInfo>): SkillInfo | undefined {
  return skills.get(raw) ?? skills.get(raw.replace(/[.,;:!?]+$/, ""));
}

/** Skill block in pi's format, so the transcript shows it as a collapsed `[skill] …` row. */
function buildSkillBlock(used: SkillInfo[]): string {
  if (used.length === 1) return skillSection(used[0], "skill");
  const sections = used.map((skill) => skillSection(skill, "skill-content"));
  return (
    `<skill name="${used.map((s) => s.name).join(", ")}" location="${used[0].filePath}">\n` +
    `The user invoked ${used.length} skills for this request. Follow all of them.\n\n` +
    `${sections.join("\n\n")}\n</skill>`
  );
}

export type Expansion =
  /** Replace the prompt with this text. */
  | { kind: "inline"; text: string }
  /** Keep `text` as the prompt (a prompt template expands it) and attach `block` as a separate message. */
  | { kind: "attach"; text: string; block: string; names: string[] };

export function expandSkills(
  text: string,
  skills: Map<string, SkillInfo>,
  templateNames: Set<string> = new Set(),
): Expansion | undefined {
  const used: SkillInfo[] = [];
  const userText = text
    .replace(SKILL_TOKEN, (match, lead: string, raw: string) => {
      const skill = resolveToken(raw, skills);
      if (!skill) return match;
      if (!used.includes(skill)) used.push(skill);
      // Keep the sentence readable: `/skill:grill-me` → `grill-me` (plus any trailing punctuation).
      return lead + skill.name + raw.slice(skill.name.length);
    })
    .trim();

  if (used.length === 0) return undefined;
  // Pi already handles a lone `/skill:name` at the very start, but it finds the name by splitting on a
  // space only (`/skill:x` + newline + text is not expanded by pi), so hand off only for a space or the end.
  const lone = `/skill:${used[0].name}`;
  if (used.length === 1 && (text === lone || text.startsWith(`${lone} `))) return undefined;

  const block = buildSkillBlock(used);
  // A leading prompt template only expands if the prompt still starts with `/name`.
  const leading = text.match(/^\/([^\s]+)/)?.[1];
  if (leading && templateNames.has(leading)) {
    return { kind: "attach", text: userText, block, names: used.map((s) => s.name) };
  }
  return { kind: "inline", text: userText ? `${block}\n\n${userText}` : block };
}

/** Prefix match on the whole name or any hyphen-separated part (`test` → build-test-first). */
function matchesSkill(name: string, query: string): boolean {
  const q = query.toLowerCase();
  const lower = name.toLowerCase();
  return lower.startsWith(q) || lower.split(/[-_.]/).some((part) => part.startsWith(q));
}

function skillItems(
  skills: Map<string, SkillInfo>,
  query: string,
  valuePrefix: string,
  isMatch: (name: string, query: string) => boolean = matchesSkill,
): AutocompleteItem[] {
  // Filter before capping at MAX_SUGGESTIONS, so every skill is reachable.
  const matches = [...skills.values()].filter((s) => isMatch(s.name, query));
  // Whole-name prefix matches first.
  matches.sort((a, b) => Number(!a.name.startsWith(query)) - Number(!b.name.startsWith(query)));
  return matches.slice(0, MAX_SUGGESTIONS).map((s) => ({
    value: `${valuePrefix}skill:${s.name}`,
    label: s.name,
    description: s.description,
  }));
}

function createProvider(current: AutocompleteProvider, getSkills: () => Map<string, SkillInfo>): AutocompleteProvider {
  const mine = new WeakSet<AutocompleteItem>();
  const claim = (items: AutocompleteItem[]) => items.forEach((item) => mine.add(item));

  return {
    triggerCharacters: ["$"],

    async getSuggestions(lines, cursorLine, cursorCol, options): Promise<AutocompleteSuggestions | null> {
      const before = (lines[cursorLine] ?? "").slice(0, cursorCol);

      const dollar = before.match(DOLLAR_AT_CURSOR);
      if (dollar) {
        const token = dollar[1]; // `$gri` — replaced entirely by `/skill:grill-me`
        const items = skillItems(getSkills(), token.slice(1).replace(/^skill:/, ""), "/");
        if (items.length > 0) {
          claim(items);
          return { prefix: token, items };
        }
      }

      // `/…` mid-prompt (pi's own slash menu owns the very start of the prompt).
      const slash = before.match(SLASH_AT_CURSOR);
      if (slash && !(cursorLine === 0 && before.trimStart() === `/${slash[1]}`)) {
        // The prefix deliberately excludes the `/`: pi's editor submits the prompt when Enter picks an
        // item whose prefix starts with `/`. The `/` stays in the text; we replace only what follows it.
        const token = slash[1];
        const query = token.replace(/^skill:/, "");
        // Whole-name prefix only, so ordinary paths like `/src` still get file completion.
        const items = skillItems(getSkills(), query, "", (name, q) => name.startsWith(q));
        if (items.length > 0) {
          claim(items);
          return { prefix: token, items };
        }
      }

      return current.getSuggestions(lines, cursorLine, cursorCol, options);
    },

    applyCompletion(lines, cursorLine, cursorCol, item, prefix) {
      if (!mine.has(item)) return current.applyCompletion(lines, cursorLine, cursorCol, item, prefix);
      const line = lines[cursorLine] ?? "";
      const head = line.slice(0, cursorCol - prefix.length) + item.value;
      const tail = line.slice(cursorCol);
      const newLines = [...lines];
      newLines[cursorLine] = head + (tail.startsWith(" ") ? "" : " ") + tail;
      return { lines: newLines, cursorLine, cursorCol: head.length + 1 };
    },

    shouldTriggerFileCompletion(lines, cursorLine, cursorCol) {
      return current.shouldTriggerFileCompletion?.(lines, cursorLine, cursorCol) ?? true;
    },
  };
}

export default function (pi: ExtensionAPI) {
  // Skills attached to a prompt-template run, waiting for before_agent_start.
  let pending: { block: string; names: string[] } | undefined;

  pi.registerMessageRenderer(MESSAGE_TYPE, (message, { expanded, outputPad, keyHint }, theme) => {
    const names = (message.details as { names?: string[] } | undefined)?.names ?? [];
    const box = new Box(outputPad, 1, (t) => theme.bg("customMessageBg", t));
    const label = theme.fg("customMessageLabel", "\x1b[1m[skill]\x1b[22m ");
    if (!expanded) {
      box.addChild(
        new Text(label + theme.fg("customMessageText", names.join(", ")) + ` (${keyHint("app.tools.expand", "to expand")})`, 0, 0),
      );
      return box;
    }
    const content = typeof message.content === "string" ? message.content : "";
    box.addChild(new Text(label, 0, 0));
    box.addChild(new Markdown(content, 0, 0, getMarkdownTheme(), { color: (t: string) => theme.fg("customMessageText", t) }));
    return box;
  });

  pi.on("session_start", (_event, ctx) => {
    pending = undefined;
    if (!ctx.hasUI) return;
    ctx.ui.addAutocompleteProvider((current) => createProvider(current, () => listSkills(pi.getCommands())));
  });

  pi.on("input", (event, ctx) => {
    pending = undefined; // never let skills leak into a later, unrelated run
    if (!event.text.includes("/skill:")) return { action: "continue" };
    try {
      const commands = pi.getCommands();
      const expansion = expandSkills(event.text, listSkills(commands), listTemplateNames(commands));
      if (!expansion) return { action: "continue" };
      if (expansion.kind === "inline") return { action: "transform", text: expansion.text };
      if (event.streamingBehavior) {
        // Queued messages don't start their own run, so there is no before_agent_start to attach to.
        ctx.ui.notify("multi-skill: skills after a prompt template aren't loaded for queued messages", "warning");
        return { action: "continue" };
      }
      pending = { block: expansion.block, names: expansion.names };
      return { action: "transform", text: expansion.text };
    } catch (err) {
      ctx.ui.notify(`multi-skill: ${err instanceof Error ? err.message : String(err)}`, "error");
      return { action: "continue" };
    }
  });

  pi.on("before_agent_start", (event) => {
    if (!pending || event.messageType !== "user") return;
    const { block, names } = pending;
    pending = undefined;
    return { message: { customType: MESSAGE_TYPE, content: block, display: true, details: { names } } };
  });
}
