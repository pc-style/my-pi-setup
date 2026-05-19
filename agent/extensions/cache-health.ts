import type { ExtensionAPI, ExtensionCommandContext, ExtensionContext, Theme } from "@mariozechner/pi-coding-agent";
import { matchesKey, truncateToWidth, visibleWidth } from "@mariozechner/pi-tui";

type Usage = { input?: number; output?: number; cacheRead?: number; cacheWrite?: number };
let lastUsage: Usage | undefined;
let totalCacheRead = 0;
let totalCacheWrite = 0;
let totalInput = 0;
let totalOutput = 0;
let budgetWarned = new Set<number>();

const BUDGET_THRESHOLDS = [
  { pct: 60, level: "info" as const, message: "Context at 60%: consider compacting if conversation gets long" },
  { pct: 75, level: "warning" as const, message: "Context at 75%: suggest running /compact soon" },
  { pct: 85, level: "warning" as const, message: "Context at 85%: compact recommended, /compact to summarize history" },
  { pct: 95, level: "error" as const, message: "Context at 95%: risk of overflow, /compact or /new strongly recommended" },
];

const formatTokens = (tokens: number) => (tokens >= 1000 ? `${(tokens / 1000).toFixed(1)}k` : `${tokens}`);

function usageFromMessage(message: unknown): Usage | undefined {
  if (!message || typeof message !== "object" || !("usage" in message)) return undefined;
  const usage = message.usage as Usage | undefined;
  if (!usage) return undefined;
  return usage;
}

function showCacheStatus(ctx: { ui: { setStatus: (key: string, value: string | undefined) => void; theme: Theme } }) {
  const theme = ctx.ui.theme;
  const read = lastUsage?.cacheRead ?? 0;
  const write = lastUsage?.cacheWrite ?? 0;
  const input = lastUsage?.input ?? 0;
  const promptTotal = input + read + write;
  const ratio = promptTotal > 0 ? Math.round((read / promptTotal) * 100) : 0;
  const label = `cache ${formatTokens(read)}r/${formatTokens(write)}w${ratio ? ` ${ratio}%` : ""}`;
  const color = read > 0 ? "success" : write > 0 ? "warning" : "dim";
  ctx.ui.setStatus("cache-health", theme.fg(color, label));
}

function checkBudget(ctx: ExtensionContext) {
  const usage = ctx.getContextUsage();
  if (!usage || !usage.tokens) return;
  const model = ctx.model as { contextWindow?: number } | undefined;
  const limit = model?.contextWindow ?? 0;
  if (!limit) return;
  const pct = Math.round((usage.tokens / limit) * 100);
  for (const threshold of BUDGET_THRESHOLDS) {
    if (pct >= threshold.pct && !budgetWarned.has(threshold.pct)) {
      budgetWarned.add(threshold.pct);
      ctx.ui.notify(threshold.message, threshold.level);
    }
  }
}

export default function (pi: ExtensionAPI) {
  pi.on("session_start", (_event, ctx) => {
    showCacheStatus(ctx);
  });

  pi.on("message_end", (event, ctx) => {
    if (event.message.role !== "assistant") return;
    const usage = usageFromMessage(event.message);
    if (usage) {
      lastUsage = usage;
      totalCacheRead += usage.cacheRead ?? 0;
      totalCacheWrite += usage.cacheWrite ?? 0;
      totalInput += usage.input ?? 0;
      totalOutput += usage.output ?? 0;
    }
    showCacheStatus(ctx);
    checkBudget(ctx);
  });

  pi.registerCommand("cache-health", {
    description: "Show prompt cache read/write token stats",
    handler: async (_args: string, ctx: ExtensionCommandContext) => {
      await ctx.ui.custom<void>((_tui, theme, _keybindings, done) => new CacheHealthDialog(theme, done), {
        overlay: true,
        overlayOptions: { width: 72, minWidth: 54, maxHeight: "70%", anchor: "center" },
      });
    },
  });
}

class CacheHealthDialog {
  constructor(
    private theme: Theme,
    private done: () => void,
  ) {}

  handleInput(data: string) {
    if (matchesKey(data, "escape") || matchesKey(data, "enter") || matchesKey(data, "ctrl+c")) this.done();
  }

  render(width: number) {
    const w = Math.min(72, Math.max(54, width));
    const inner = w - 2;
    const th = this.theme;
    const pad = (text: string) => text + " ".repeat(Math.max(0, inner - visibleWidth(text)));
    const row = (text = "") => th.fg("border", "│") + truncateToWidth(pad(text), inner, "") + th.fg("border", "│");
    const line = (label: string, value: string) => row(` ${label}${" ".repeat(Math.max(1, inner - label.length - value.length - 2))}${value}`);
    const lines: string[] = [];
    lines.push(th.fg("border", `╭─ Cache Health ${"─".repeat(Math.max(0, inner - 15))}╮`));
    lines.push(row());
    line;
    lines.push(line("Last input", formatTokens(lastUsage?.input ?? 0)));
    lines.push(line("Last output", formatTokens(lastUsage?.output ?? 0)));
    lines.push(line("Last cache read", formatTokens(lastUsage?.cacheRead ?? 0)));
    lines.push(line("Last cache write", formatTokens(lastUsage?.cacheWrite ?? 0)));
    lines.push(row());
    lines.push(line("Session input", formatTokens(totalInput)));
    lines.push(line("Session output", formatTokens(totalOutput)));
    lines.push(line("Session cache read", formatTokens(totalCacheRead)));
    lines.push(line("Session cache write", formatTokens(totalCacheWrite)));
    lines.push(row());
    lines.push(row(` ${th.fg("dim", "Thresholds: 60%/75%/85%/95% warn → /compact or /new")}`));
    lines.push(row(` ${th.fg("dim", "Status widget shows: cache <read>r/<write>w <read/prompt-total%>")}`));
    const footer = " Esc close ";
    lines.push(th.fg("border", `╰${"─".repeat(Math.max(0, inner - footer.length))}${footer}╯`));
    return lines;
  }

  invalidate() {}
}
