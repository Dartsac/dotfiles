import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { AgentSession, initTheme, parseSkillBlock, stripFrontmatter } from "@earendil-works/pi-coding-agent";
import multiSkill, { expandSkills } from "./index.ts";

type Skill = { name: string; description: string; filePath: string; baseDir: string };

const root = mkdtempSync(join(tmpdir(), "multi-skill-test-"));
test.after(() => rmSync(root, { recursive: true, force: true }));

function skill(name: string, content = `---\nname: ${name}\ndescription: ${name} skill\n---\n# ${name}\n\nBody of ${name}.\n`): Skill {
  const baseDir = join(root, name);
  mkdirSync(baseDir, { recursive: true });
  const filePath = join(baseDir, "SKILL.md");
  writeFileSync(filePath, content);
  return { name, description: `${name} skill`, filePath, baseDir };
}

const alpha = skill("alpha");
const beta = skill("beta");
const skills = new Map([alpha, beta].map((s) => [s.name, s]));

/** The block pi builds for `/skill:name`, given the body it should contain. */
function block(s: Skill, body = `# ${s.name}\n\nBody of ${s.name}.`): string {
  return `<skill name="${s.name}" location="${s.filePath}">\nReferences are relative to ${s.baseDir}.\n\n${body}\n</skill>`;
}

// pi's own expansion of a leading `/skill:name`. It is private, so these comparisons skip if pi drops it.
const piExpand = (AgentSession.prototype as any)._expandSkillCommand as ((text: string) => string) | undefined;
const noNative = piExpand ? false : "pi no longer has AgentSession._expandSkillCommand";
function native(text: string): string {
  const session = { resourceLoader: { getSkills: () => ({ skills: [...skills.values()] }) }, _extensionRunner: { emitError() {} } };
  return piExpand!.call(session, text);
}

function inline(text: string, known = skills): string {
  const expansion = expandSkills(text, known);
  assert.equal(expansion?.kind, "inline");
  return expansion!.text;
}

// ---------------------------------------------------------------------------------------------
// Expansion
// ---------------------------------------------------------------------------------------------

test("a lone leading /skill:name is left for pi to expand", { skip: noNative }, () => {
  for (const text of ["/skill:alpha", "/skill:alpha do the thing"]) {
    assert.equal(expandSkills(text, skills), undefined);
    assert.ok(native(text).startsWith(block(alpha)), `pi expands ${JSON.stringify(text)}`);
  }
});

test("a skill mid-prompt becomes exactly the block pi builds natively", { skip: noNative }, () => {
  assert.equal(inline("please use /skill:alpha now"), native("/skill:alpha please use alpha now"));
});

test("a line break or tab after a leading skill is expanded here, because pi does not", { skip: noNative }, () => {
  for (const gap of ["\n", "\t"]) {
    const text = `/skill:alpha${gap}fix it`;
    assert.equal(native(text), text, "pi leaves it unexpanded");
    assert.equal(inline(text), `${block(alpha)}\n\nalpha${gap}fix it`);
  }
});

test("several skills become one block that pi shows as a single skill row", () => {
  const text = inline("a /skill:alpha b /skill:beta.");
  const parsed = parseSkillBlock(text);
  assert.equal(parsed?.name, "alpha, beta");
  assert.equal(parsed?.userMessage, "a alpha b beta.");
  assert.match(text, /The user invoked 2 skills for this request\. Follow all of them\./);
  for (const s of [alpha, beta]) {
    assert.ok(text.includes(`<skill-content name="${s.name}" location="${s.filePath}">`));
    assert.ok(text.includes(`Body of ${s.name}.\n</skill-content>`));
  }
});

test("a skill named twice is loaded once", () => {
  assert.equal(inline("x /skill:alpha y /skill:alpha"), `${block(alpha)}\n\nx alpha y alpha`);
});

test("sentence punctuation is not part of the name, and unknown names are left alone", () => {
  assert.equal(inline("use /skill:alpha."), `${block(alpha)}\n\nuse alpha.`);
  assert.equal(expandSkills("use /skill:nope", skills), undefined);
  assert.equal(inline("use /skill:alpha and /skill:nope"), `${block(alpha)}\n\nuse alpha and /skill:nope`);
});

test("a leading prompt template keeps its place so pi still expands it", () => {
  const expansion = expandSkills("/review check it with /skill:alpha", skills, new Set(["review"]));
  assert.deepEqual(expansion, { kind: "attach", text: "/review check it with alpha", block: block(alpha) });
  // Without a template of that name, the same text is an ordinary inline expansion.
  assert.equal(expandSkills("/review check it with /skill:alpha", skills)?.kind, "inline");
});

test("frontmatter is stripped the way pi strips it", () => {
  const cases: Record<string, string> = {
    plain: "---\nname: a\n---\nBody",
    bom: "\uFEFF---\nname: a\n---\nBody",
    crlf: "---\r\nname: a\r\n---\r\nLine1\r\nLine2",
    closer: "---\nname: a\n---foo\nBody",
    empty: "---\n---\nBody",
    none: "# Just a body\n",
  };
  for (const [name, content] of Object.entries(cases)) {
    const s = skill(`fm-${name}`, content);
    const text = inline(`x /skill:${s.name}`, new Map([[s.name, s]]));
    assert.equal(text, `${block(s, stripFrontmatter(content).trim())}\n\nx ${s.name}`, name);
  }
});

test("a skill with malformed frontmatter still loads", () => {
  const content = "---\nname: [unclosed\n---\nBody";
  assert.throws(() => stripFrontmatter(content), "pi's own stripping parses the YAML and throws");
  const s = skill("fm-malformed", content);
  assert.equal(inline(`x /skill:${s.name}`, new Map([[s.name, s]])), `${block(s, "Body")}\n\nx ${s.name}`);
});

// ---------------------------------------------------------------------------------------------
// The extension: input handling, autocomplete, rendering
// ---------------------------------------------------------------------------------------------

function harness(known: Skill[] = [alpha, beta], templates: string[] = ["review"]) {
  const handlers: Record<string, (...args: any[]) => any> = {};
  const notices: string[] = [];
  const delegated = { prefix: "", items: [] };
  let provider: any;
  let renderer: any;
  multiSkill({
    on: (event: string, handler: (...args: any[]) => any) => { handlers[event] = handler; },
    registerMessageRenderer: (_type: string, render: any) => { renderer = render; },
    getCommands: () => [
      ...known.map((s) => ({ name: `skill:${s.name}`, description: s.description, source: "skill", sourceInfo: { path: s.filePath } })),
      ...templates.map((name) => ({ name, source: "prompt", sourceInfo: { path: `/prompts/${name}.md` } })),
    ],
  } as any);
  handlers.session_start({}, {
    hasUI: true,
    ui: {
      addAutocompleteProvider: (factory: any) => {
        provider = factory({ getSuggestions: async () => delegated, applyCompletion: () => "delegated" });
      },
    },
  });
  const ctx = { ui: { notify: (message: string) => notices.push(message) } };
  return {
    notices,
    delegated,
    provider,
    render: (message: any, options: any) => renderer(message, options),
    input: (text: string, extra: object = {}) => handlers.input({ text, source: "interactive", ...extra }, ctx),
    start: (messageType = "user") => handlers.before_agent_start({ messageType }),
    /** Suggestions with the cursor at the end of the last line. */
    suggest: (...lines: string[]) =>
      provider.getSuggestions(lines, lines.length - 1, lines[lines.length - 1].length, { signal: new AbortController().signal }),
  };
}

const labels = (suggestions: any): string[] => suggestions.items.map((item: any) => item.label);

test("the input handler expands skills and leaves other prompts alone", () => {
  const h = harness();
  assert.deepEqual(h.input("no skills here"), { action: "continue" });
  assert.deepEqual(h.input("/skill:alpha handled by pi"), { action: "continue" });
  assert.deepEqual(h.input("x /skill:alpha"), { action: "transform", text: `${block(alpha)}\n\nx alpha` });
  assert.equal(h.start(), undefined, "nothing is attached for an inline expansion");
});

test("skills after a prompt template are attached to that run, once", () => {
  const h = harness();
  assert.deepEqual(h.input("/review go /skill:alpha"), { action: "transform", text: "/review go alpha" });
  assert.deepEqual(h.start(), { message: { customType: "multi-skill", content: block(alpha), display: true } });
  assert.equal(h.start(), undefined);
});

test("attached skills never leak into a later prompt", () => {
  const h = harness();
  h.input("/review go /skill:alpha");
  h.input("an unrelated prompt");
  assert.equal(h.start(), undefined);
});

test("a queued template prompt is sent unchanged, with a warning", () => {
  const h = harness();
  assert.deepEqual(h.input("/review go /skill:alpha", { streamingBehavior: "followUp" }), { action: "continue" });
  assert.equal(h.notices.length, 1);
  assert.equal(h.start(), undefined);
});

test("$ opens the skill dropdown only when a letter follows", async () => {
  const h = harness();
  for (const text of ["it costs $", "costs $5", "$10.00", "echo $PATH"]) {
    assert.equal(await h.suggest(text), h.delegated, text);
  }
  const suggestions = await h.suggest("use $al");
  assert.equal(suggestions.prefix, "$al");
  assert.deepEqual(suggestions.items, [{ value: "/skill:alpha", label: "alpha", description: "alpha skill" }]);
});

test("$ matches any part of a skill name, whole-name matches first, ignoring case", async () => {
  const h = harness([skill("build-test-first"), skill("test-runner"), alpha]);
  for (const text of ["x $test", "x $Test"]) {
    assert.deepEqual(labels(await h.suggest(text)), ["test-runner", "build-test-first"], text);
  }
});

test("a mid-prompt / completes with a prefix that has no slash, so Enter does not send", async () => {
  const h = harness();
  const suggestions = await h.suggest("hello /al");
  // pi's editor submits the prompt when Enter picks an item whose prefix starts with "/".
  assert.equal(suggestions.prefix, "al");
  assert.deepEqual(labels(suggestions), ["alpha"]);
  assert.deepEqual(h.provider.applyCompletion(["hello /al"], 0, 9, suggestions.items[0], suggestions.prefix), {
    lines: ["hello /skill:alpha "],
    cursorLine: 0,
    cursorCol: 19,
  });
});

test("the start of the prompt and ordinary paths are left to pi", async () => {
  const h = harness();
  for (const text of ["/al", "  /al", "see /src", "x /beta-not-a-skill"]) {
    assert.equal(await h.suggest(text), h.delegated, text);
  }
  assert.deepEqual(labels(await h.suggest("first line", "/al")), ["alpha"], "a later line is mid-prompt");
});

test("every skill is reachable from a mid-prompt /, past the 20-row cap", async () => {
  const many = Array.from({ length: 25 }, (_, i) => skill(`s${String(i + 1).padStart(2, "0")}`));
  const h = harness(many);
  assert.equal((await h.suggest("x /s")).items.length, 20);
  for (const s of many) {
    assert.deepEqual(labels(await h.suggest(`x /${s.name}`)), [s.name]);
  }
});

test("picking a skill inserts it with one space; other items go to pi", async () => {
  const h = harness();
  const [item] = (await h.suggest("use $al")).items;
  assert.equal(h.provider.applyCompletion(["use $al tail"], 0, 7, item, "$al").lines[0], "use /skill:alpha tail");
  assert.equal(h.provider.applyCompletion(["use $al"], 0, 7, { value: "x", label: "x" }, "$al"), "delegated");
});

test("attached skills are drawn as pi's own skill row", () => {
  initTheme("dark");
  const h = harness();
  h.input("/review a /skill:alpha b /skill:beta");
  const { message } = h.start();
  const text = (expanded: boolean) =>
    h.render(message, { expanded, outputPad: 1 })
      .render(100).join("\n").replace(/\x1b\[[0-9;]*m/g, "");
  assert.match(text(false), /\[skill\] alpha, beta/);
  assert.doesNotMatch(text(false), /Body of alpha/);
  assert.match(text(true), /Body of alpha/);
  assert.equal(h.render({ content: "not a skill block" }, { expanded: false, outputPad: 1 }), undefined);
});
