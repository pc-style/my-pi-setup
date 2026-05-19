import type { ExtensionAPI, ExtensionCommandContext, ExtensionContext } from "@earendil-works/pi-coding-agent";

const LATEST_VERSION_URL = "https://pi.dev/api/latest-version";
const VERSION_PATTERN = /\d+(?:\.\d+)+(?:[-+][\w.-]+)?/;
const SKILL_RELATED_PATTERN = /(^|\W)(skill|skills|skil|SKILL\.md|\/skill:)(\W|$)/i;

let updateChecked = false;
let updateInProgress = false;
let restartRecommended = false;
let skillsContextEnabled = false;

function extractVersion(text: string) {
  return text.match(VERSION_PATTERN)?.[0];
}

function normalizeVersion(version: string) {
  return version.replace(/^v/i, "").trim();
}

function compareVersions(a: string, b: string) {
  const [aMain, aPre = ""] = normalizeVersion(a).split("-");
  const [bMain, bPre = ""] = normalizeVersion(b).split("-");
  const aParts = aMain.split(".").map((part) => Number.parseInt(part, 10) || 0);
  const bParts = bMain.split(".").map((part) => Number.parseInt(part, 10) || 0);
  const length = Math.max(aParts.length, bParts.length);

  for (let i = 0; i < length; i++) {
    const diff = (aParts[i] ?? 0) - (bParts[i] ?? 0);
    if (diff !== 0) return diff;
  }

  if (aPre === bPre) return 0;
  if (!aPre) return 1;
  if (!bPre) return -1;
  return aPre.localeCompare(bPre);
}

async function currentVersion(pi: ExtensionAPI) {
  const result = await pi.exec("pi", ["--version"], { timeout: 10_000 });
  return extractVersion(`${result.stdout}\n${result.stderr}`) ?? "unknown";
}

async function latestVersion() {
  const response = await fetch(LATEST_VERSION_URL);
  if (!response.ok) throw new Error(`latest-version request failed: ${response.status}`);

  const text = await response.text();
  const fromText = extractVersion(text);
  if (fromText) return fromText;

  const json = JSON.parse(text) as { version?: string; latest?: string; latestVersion?: string };
  const candidate = json.version ?? json.latest ?? json.latestVersion;
  if (!candidate) throw new Error("latest-version response did not include a version");
  return normalizeVersion(candidate);
}

async function runPiUpdate(pi: ExtensionAPI, ctx: ExtensionContext, reason: string) {
  if (updateInProgress) return;
  updateInProgress = true;

  try {
    const before = await currentVersion(pi).catch(() => "unknown");
    ctx.ui.notify(`${reason} Running pi update…`, "info");

    const result = await pi.exec("pi", ["update"], { timeout: 300_000 });
    const output = [result.stdout, result.stderr].filter(Boolean).join("\n").trim();

    if (result.code !== 0) {
      ctx.ui.notify(`pi update failed.${output ? `\n${output}` : ""}`, "error");
      return;
    }

    const after = await currentVersion(pi).catch(() => "unknown");
    restartRecommended = true;

    if (ctx.hasUI) {
      const restartNow = await ctx.ui.confirm(
        "Pi update complete",
        `Pi update complete: ${before} → ${after}. Restart this Pi process now?`,
      );
      if (restartNow) {
        ctx.ui.notify("Restarting Pi: this process will exit. Run pi again to use the updated version.", "info");
        ctx.shutdown();
        return;
      }
    }

    ctx.ui.notify(`Pi update complete: ${before} → ${after}. Run /restart when you're ready to exit this Pi process, then start Pi again to use the new version.`, "info");
  } finally {
    updateInProgress = false;
  }
}

async function runPiUpdateWhenIdle(pi: ExtensionAPI, ctx: ExtensionCommandContext, reason: string) {
  await ctx.waitForIdle();
  await runPiUpdate(pi, ctx, reason);
}

function stripSkillContext(systemPrompt: string) {
  return systemPrompt
    .replace(/\n?\s*<available_skills>[\s\S]*?<\/available_skills>\s*/gi, "\n")
    .replace(/\n?\s*<skills>[\s\S]*?<\/skills>\s*/gi, "\n")
    .replace(/\n?#{1,6}\s*Available Skills[\s\S]*?(?=\n#{1,6}\s|$)/gi, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

export default function (pi: ExtensionAPI) {
  pi.registerCommand("update", {
    description: "Run pi update and recommend /restart when it finishes",
    handler: async (_args, ctx) => {
      await runPiUpdateWhenIdle(pi, ctx, "Manual update requested.");
    },
  });

  pi.registerCommand("restart", {
    description: "Exit Pi so the next pi launch uses the updated installation",
    handler: async (_args, ctx) => {
      const message = restartRecommended
        ? "Restarting Pi: this process will exit. Run pi again to use the updated version."
        : "No completed update was recorded in this session, but this will exit Pi. Run pi again to start fresh.";
      ctx.ui.notify(message, "info");
      ctx.shutdown();
    },
  });

  pi.on("session_start", async (_event, ctx) => {
    if (updateChecked || process.env.PI_OFFLINE === "1" || process.env.PI_SKIP_VERSION_CHECK === "1") return;
    updateChecked = true;

    try {
      const [current, latest] = await Promise.all([currentVersion(pi), latestVersion()]);
      if (current !== "unknown" && compareVersions(latest, current) > 0) {
        await runPiUpdate(pi, ctx, `Pi ${latest} is available (current ${current}).`);
      }
    } catch (error) {
      ctx.ui.notify(`Pi update check skipped: ${error instanceof Error ? error.message : String(error)}`, "warning");
    }
  });

  pi.on("before_agent_start", async (event) => {
    // Prompt caches are prefix based. If we include skills for one turn and then
    // remove them on the next turn, the stable system-prompt prefix changes and
    // cache reads get worse. So skill context is lazy, but sticky for this Pi
    // process/session runtime: once a prompt asks about skills, keep the skills
    // block in later turns.
    if (SKILL_RELATED_PATTERN.test(event.prompt)) {
      skillsContextEnabled = true;
      return;
    }

    if (skillsContextEnabled) return;

    const systemPrompt = stripSkillContext(event.systemPrompt);
    if (systemPrompt === event.systemPrompt) return;
    return { systemPrompt };
  });
}
