// A short label for what a Pi session is about ("sidebar-tab-naming"), written
// once by a small model and stored as the session name. The terminal title
// carries it to Herdr, where herdr-automatic-rename names the tab "pi:<label>".
import { clean } from "./supervision.mjs";

// Longest label: herdr-automatic-rename's MAX_TITLE_LEN (22) minus the "pi:" it
// puts in front. A longer one would lose its last word there.
export const TOPIC_MAX = 19;
export const TOPIC_ATTEMPTS = 3;
// The small model of the provider the session already uses, so prompt text is
// never sent to another provider. Other providers use the session's model.
const SMALL_MODELS = { anthropic: "claude-haiku-5-5", google: "gemini-flash-lite-latest" };
const NO_TOPIC = new Set(["", "none", "unknown", "unclear", "n-a", "na", "label", "session", "task"]);

const SYSTEM = `You label coding-agent sessions for a narrow tab bar.
Reply with the label only: 2 or 3 lowercase words joined by hyphens, at most ${TOPIC_MAX} characters, naming the subject of the work, e.g. "sidebar-tab-naming", "deepgram-dictation", "gild-load-errors".
Prefer the specific thing being worked on over generic words such as "help", "question", "review" or "task". Do not repeat the folder name.
If the messages do not say what the work is about, reply with exactly: none`;

export function topicModel(context) {
  const id = SMALL_MODELS[context.model?.provider];
  const small = id && context.modelRegistry.find(context.model.provider, id);
  return small && context.modelRegistry.hasConfiguredAuth(small) ? small : context.model;
}

export function messageText(message) {
  const content = message?.content;
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content.filter(part => part?.type === "text" && typeof part.text === "string").map(part => part.text).join("\n");
}

// The model's reply as a label, or "" when it gave none.
export function normalizeTopic(reply, folder = "") {
  const line = String(reply ?? "").trim().split("\n")[0].toLowerCase().replace(/["'`]/g, "");
  let words = line.replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").split("-").filter(Boolean).slice(0, 4);
  while (words.length > 1 && words.join("-").length > TOPIC_MAX) words = words.slice(0, -1);
  const topic = words.join("-").slice(0, TOPIC_MAX);
  const same = folder.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
  return NO_TOPIC.has(topic) || topic === same ? "" : topic;
}

export function topicContext({ folder, first, latest, reply }) {
  const part = (tag, text) => clean(text, 600) ? `<${tag}>\n${clean(text, 600)}\n</${tag}>` : "";
  const text = [
    `Folder: ${clean(folder, 80)}`,
    part("first_user_message", first),
    clean(latest, 600) !== clean(first, 600) ? part("latest_user_message", latest) : "",
    part("assistant_reply", reply),
  ].filter(Boolean).join("\n");
  return { systemPrompt: SYSTEM, messages: [{ role: "user", content: [{ type: "text", text }], timestamp: Date.now() }] };
}

// Ask the model for a label. "" means it had nothing to go on; errors throw.
export async function generateTopic(context, input, signal) {
  const model = topicModel(context);
  if (!model) return "";
  const result = await context.modelRegistry.streamSimple(model, topicContext(input), { maxTokens: 30, cacheRetention: "none", signal }).result();
  if (result.stopReason === "error" || result.stopReason === "aborted") throw new Error(result.errorMessage || "topic request failed");
  return normalizeTopic(messageText(result), input.folder);
}
