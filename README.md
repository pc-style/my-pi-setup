# My Pi Setup

One-command installer for my custom [Pi](https://github.com/mariozechner/pi) coding agent configuration.

## Quick Install

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/pc-style/my-pi-setup/main/install.sh | bash
```

### Windows (PowerShell)

```powershell
curl.exe -fsSL https://raw.githubusercontent.com/pc-style/my-pi-setup/main/install.ps1 | powershell -NoProfile -ExecutionPolicy Bypass -Command -
```

## What it does

1. **Installs Pi** if it's not already installed (tries `bun`, then `pnpm`, then `npm`)
2. **Backs up** any existing `~/.pi/agent` config to `~/.pi.bak/<timestamp>/`
3. **Downloads** all custom extensions, themes, skills, and config from this repo
4. **Prompts** for API keys and optional post-install steps
5. **Uses Bun for extension dependencies** (`bun install` in both the agent root and `extensions/pi-mcp`)

## What's included

- **`AGENTS.md`** — Custom agent rules and best practices
- **`settings.json`** — Default model, provider, thinking level, packages, etc.
- **`models.json`** — Custom provider definitions (Venice AI, Azure OpenAI)
- **`themes/`** — Custom theme(s)
- **`.firecrawl/`** — Firecrawl skill definitions
- **`extensions/`** — Custom TypeScript extensions
- **`package.json`** — Extension dependencies
- **`bun.lock`** — Bun lockfile for the agent root

## Manual sync

If you already cloned this repo and just want to copy files locally:

```bash
rsync -av --delete agent/ ~/.pi/agent/
```

Then install deps with Bun:

```bash
cd ~/.pi/agent && bun install
cd ~/.pi/agent/extensions/pi-mcp && bun install
```

## License

MIT (or whatever you want)
