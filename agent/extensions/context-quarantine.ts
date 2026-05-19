import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { createHash } from "node:crypto";

type TextPart = { type: "text"; text: string };

const MAX_INLINE_CHARS = 12_000;
const PREVIEW_CHARS = 2_000;
const CACHE_DIR = ".pi/context-cache";

function isTextPart(part: unknown): part is TextPart {
  return Boolean(part && typeof part === "object" && "type" in part && part.type === "text" && "text" in part && typeof part.text === "string");
}

function textFromContent(content: unknown) {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content.filter(isTextPart).map((part) => part.text).join("\n");
}

function summarize(text: string) {
  const lines = text.split("\n");
  const nonEmpty = lines.filter((line) => line.trim());
  const headings = nonEmpty.filter((line) => /^(#{1,6}\s|[-*]\s|\d+\.\s|[A-Z][\w /-]{2,}:\s*$)/.test(line.trim())).slice(0, 12);
  const errors = nonEmpty.filter((line) => /error|warning|failed|exception|traceback|denied|not found/i.test(line)).slice(0, 12);
  const preview = text.slice(0, PREVIEW_CHARS).trim();

  return [
    `Original output quarantined because it was large: ${text.length.toLocaleString()} chars, ${lines.length.toLocaleString()} lines.`,
    headings.length ? `\nLikely structure / important headings:\n${headings.map((line) => `- ${line.trim().slice(0, 180)}`).join("\n")}` : "",
    errors.length ? `\nPotential errors/warnings:\n${errors.map((line) => `- ${line.trim().slice(0, 180)}`).join("\n")}` : "",
    `\nPreview:\n${preview}`,
  ].filter(Boolean).join("\n");
}

function retrievalInstructions(path: string) {
  return `\n\nFull output saved at: ${path}\n\nContext-saving instruction: do NOT read the whole cached file unless absolutely necessary. Prefer targeted shell access such as:\n- grep -n "keyword" "${path}"\n- sed -n '120,180p' "${path}"\n- head -80 "${path}" or tail -80 "${path}"\n- wc -l "${path}" first, then read only relevant ranges\nUse the cached file path as the source of truth if more detail is needed.`;
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_result", async (event, ctx) => {
    const text = textFromContent(event.content);
    if (text.length <= MAX_INLINE_CHARS) return;

    const dir = join(ctx.cwd, CACHE_DIR);
    await mkdir(dir, { recursive: true });

    const hash = createHash("sha256").update(`${event.toolName}\n${Date.now()}\n${text}`).digest("hex").slice(0, 12);
    const safeTool = event.toolName.replace(/[^a-z0-9_-]/gi, "-").toLowerCase();
    const relativePath = `${CACHE_DIR}/${Date.now()}-${safeTool}-${hash}.txt`;
    const absolutePath = join(ctx.cwd, relativePath);
    await writeFile(absolutePath, text, "utf8");

    const summary = summarize(text) + retrievalInstructions(relativePath);

    return {
      content: [{ type: "text", text: summary }],
      details: {
        ...(event.details && typeof event.details === "object" ? event.details : {}),
        quarantined: true,
        originalChars: text.length,
        originalLines: text.split("\n").length,
        cachePath: relativePath,
      },
    };
  });
}
