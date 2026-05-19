import type { ExtensionAPI, ExtensionCommandContext, Theme } from "@earendil-works/pi-coding-agent";
import { matchesKey, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

type Row = { label: string; tokens: number; indent?: boolean };
type Snapshot = {
  modelName: string;
  contextWindow?: number;
  rows: Row[];
  used: number;
  free?: number;
};

type CapturedPromptOptions = {
  selectedTools?: unknown[];
  toolSnippets?: unknown[];
  contextFiles?: Array<{ path?: string; content?: string }>;
  skills?: unknown[];
};

let lastPromptOptions: CapturedPromptOptions | undefined;
let lastSystemPrompt = "";

const tokenEstimate = (text: string) => Math.ceil(text.length / 4);
const formatTokens = (tokens: number) => (tokens >= 1000 ? `${(tokens / 1000).toFixed(1)}k` : tokens.toLocaleString());
const percent = (tokens: number, total?: number) => (total ? `${((tokens / total) * 100).toFixed(1)}%` : "n/a");

function textFromContent(content: unknown): string {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content
      .map((part) => {
        if (part && typeof part === "object" && "text" in part && typeof part.text === "string") return part.text;
        return JSON.stringify(part);
      })
      .join("\n");
  }
  return JSON.stringify(content ?? "");
}

function isMessageEntry(entry: unknown): entry is { type: "message"; message: { content?: unknown } } {
  return Boolean(entry && typeof entry === "object" && "type" in entry && entry.type === "message" && "message" in entry);
}

function getContextWindow(model: unknown) {
  if (!model || typeof model !== "object") return undefined;
  const record = model as { contextWindow?: unknown; context_window?: unknown };
  const value = record.contextWindow ?? record.context_window;
  return typeof value === "number" ? value : undefined;
}

function getModelName(ctx: ExtensionCommandContext) {
  const model = ctx.model;
  if (!model) return "No model selected";
  const record = model as { name?: unknown; provider?: unknown; id?: unknown };
  const name = typeof record.name === "string" ? record.name : undefined;
  const provider = typeof record.provider === "string" ? record.provider : undefined;
  const id = typeof record.id === "string" ? record.id : undefined;
  return name ?? ([provider, id].filter(Boolean).join("/") || "Unknown model");
}

function estimateSkillsTokens(pi: ExtensionAPI) {
  const capturedSkills = lastPromptOptions?.skills ?? [];
  if (capturedSkills.length > 0) {
    return tokenEstimate(capturedSkills.map((skill) => (typeof skill === "string" ? skill : JSON.stringify(skill))).join("\n"));
  }

  const skillCommands = pi.getCommands().filter((command) => command.source === "skill");
  if (skillCommands.length === 0) return 0;

  // Pi puts skill names/descriptions in the system prompt, not full SKILL.md contents.
  // Reconstruct a close approximation from discovered skill commands so /context still
  // shows the category even when another extension strips skills for non-skill prompts.
  const skillPromptShape = skillCommands
    .map((command) => `<skill name="${command.name.replace(/^skill:/, "")}">${command.description ?? ""}</skill>`)
    .join("\n");
  return tokenEstimate(`<available_skills>\n${skillPromptShape}\n</available_skills>`);
}

function buildSnapshot(pi: ExtensionAPI, ctx: ExtensionCommandContext): Snapshot {
  const systemPrompt = lastSystemPrompt || ctx.getSystemPrompt();
  const contextWindow = getContextWindow(ctx.model);
  const contextUsage = ctx.getContextUsage();
  const rows: Row[] = [];

  const toolText = [lastPromptOptions?.selectedTools, lastPromptOptions?.toolSnippets]
    .flatMap((value) => (Array.isArray(value) ? value : []))
    .map((value) => (typeof value === "string" ? value : JSON.stringify(value)))
    .join("\n");

  const contextFiles = lastPromptOptions?.contextFiles ?? [];
  const contextFileTokens = contextFiles.reduce((sum, file) => sum + tokenEstimate(file.content ?? ""), 0);
  const toolTokens = tokenEstimate(toolText);
  const skillTokens = estimateSkillsTokens(pi);
  const systemTokens = Math.max(0, tokenEstimate(systemPrompt) - toolTokens - contextFileTokens - skillTokens);

  rows.push({ label: "System prompt", tokens: systemTokens });
  if (toolTokens > 0) rows.push({ label: "Tools", tokens: toolTokens });
  if (skillTokens > 0) rows.push({ label: "Skills", tokens: skillTokens });
  if (contextFileTokens > 0) {
    rows.push({ label: "AGENTS.md files", tokens: contextFileTokens });
    for (const file of contextFiles) rows.push({ label: file.path ?? "context file", tokens: tokenEstimate(file.content ?? ""), indent: true });
  }

  const messageText = (ctx.sessionManager.getBranch() as unknown[])
    .filter(isMessageEntry)
    .map((entry) => textFromContent(entry.message.content))
    .join("\n");
  const estimatedMessages = tokenEstimate(messageText);
  const messages = contextUsage?.tokens ? Math.max(0, contextUsage.tokens - rows.reduce((sum, row) => sum + row.tokens, 0)) : estimatedMessages;
  rows.push({ label: "Messages", tokens: messages });

  const used = contextUsage?.tokens ?? rows.reduce((sum, row) => sum + row.tokens, 0);
  return {
    modelName: getModelName(ctx),
    contextWindow,
    rows,
    used,
    free: contextWindow ? Math.max(0, contextWindow - used) : undefined,
  };
}

export default function (pi: ExtensionAPI) {
  pi.on("before_agent_start", (event) => {
    lastSystemPrompt = event.systemPrompt;
    const record = event as unknown as { systemPromptOptions?: CapturedPromptOptions };
    lastPromptOptions = record.systemPromptOptions;
  });

  pi.registerCommand("context", {
    description: "Show context usage breakdown",
    handler: async (_args, ctx) => {
      const snapshot = buildSnapshot(pi, ctx);
      await ctx.ui.custom<void>((_tui, theme, _keybindings, done) => new ContextDialog(theme, snapshot, done), {
        overlay: true,
        overlayOptions: { width: 82, minWidth: 60, maxHeight: "80%", anchor: "center" },
      });
    },
  });
}

class ContextDialog {
  constructor(
    private theme: Theme,
    private snapshot: Snapshot,
    private done: () => void,
  ) {}

  handleInput(data: string) {
    if (matchesKey(data, "escape") || matchesKey(data, "enter") || matchesKey(data, "ctrl+c")) this.done();
  }

  render(width: number) {
    const w = Math.min(82, Math.max(54, width));
    const inner = w - 2;
    const lines: string[] = [];
    const th = this.theme;
    const pad = (text: string) => text + " ".repeat(Math.max(0, inner - visibleWidth(text)));
    const row = (text = "") => th.fg("border", "│") + truncateToWidth(pad(text), inner, "") + th.fg("border", "│");
    const title = " Context Usage Analysis ";
    const titleRight = Math.max(0, inner - title.length);

    lines.push(th.fg("border", `╭─${title}${"─".repeat(Math.max(0, titleRight - 1))}╮`));
    lines.push(row());
    const windowText = this.snapshot.contextWindow ? ` (${formatTokens(this.snapshot.contextWindow)} context)` : "";
    lines.push(row(` Model: ${th.fg("accent", this.snapshot.modelName)}${windowText}`));
    lines.push(row());

    for (const item of this.snapshot.rows) {
      const label = `${item.indent ? "  " : ""}${item.label}`;
      const tokenText = formatTokens(item.tokens).padStart(8);
      const pct = `(${percent(item.tokens, this.snapshot.contextWindow)})`;
      const left = ` ${label}`;
      const gap = " ".repeat(Math.max(1, inner - visibleWidth(left) - visibleWidth(tokenText) - visibleWidth(pct) - 2));
      lines.push(row(`${left}${gap}${tokenText}  ${pct}`));
    }

    lines.push(row());
    lines.push(row(` Used: ${formatTokens(this.snapshot.used)} tokens (${percent(this.snapshot.used, this.snapshot.contextWindow)} used)`));
    if (this.snapshot.free !== undefined) lines.push(row(` Free: ${formatTokens(this.snapshot.free)} tokens`));
    lines.push(row());

    const footer = " Esc close ";
    lines.push(th.fg("border", `╰${"─".repeat(Math.max(0, inner - footer.length))}${footer}╯`));
    return lines;
  }

  invalidate() {}
}
