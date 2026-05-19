import { readFileSync, writeFileSync } from "fs";
import { resolve, dirname } from "path";

const __dirname = dirname(new URL(import.meta.url).pathname);
const manifest = JSON.parse(readFileSync(resolve(__dirname, "manifest.json"), "utf-8"));

const { repoRaw, files, apiKeys, packages, bunInstallDirs } = manifest;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function indent(str: string, spaces: number): string {
  const pad = " ".repeat(spaces);
  return str
    .split("\n")
    .map((line) => (line.trim() === "" ? "" : pad + line))
    .join("\n");
}

function escDQ(s: string): string {
  return s.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

function escSQ(s: string): string {
  return s.replace(/\\/g, "\\\\").replace(/'/g, "'\\''");
}

// ---------------------------------------------------------------------------
// Generate install.sh (Bash)
// ---------------------------------------------------------------------------

function generateBash(): string {
  const fileEntries = files
    .map((f: string) => {
      const basename = f.replace(/[/.-]/g, "_");
      return `    pull_file "${f}" "\${AGENT_DIR}/${f}"`;
    })
    .join("\n");

  const envKeyBlocks: string[] = [];
  const mcpKeyBlocks: string[] = [];
  const authKeyBlocks: string[] = [];

  for (const key of apiKeys) {
    const defaultFlag = key.defaultNo ? '"n"' : '"y"';
    const prompt = escDQ(key.prompt);

    if (key.write.type === "env") {
      envKeyBlocks.push(
        `    if prompt_yn "${prompt}" ${defaultFlag}; then
        read -rsp "  ${key.label} API key: " val
        echo
        echo "${key.write.variable}=\${val}" >> "\$env_file"
        ok "${key.label} key saved."
    fi`
      );
    } else if (key.write.type === "mcp") {
      mcpKeyBlocks.push(
        `    if prompt_yn "${prompt}" ${defaultFlag}; then
        read -rsp "  ${key.label} API key: " val
        echo
        cat > "\${AGENT_DIR}/mcp.json" <<'MCPEOF'
{
  "mcpServers": {
    "${key.write.serverId}": {
      "type": "http",
      "url": "${key.write.url}",
      "headers": {
        "${key.write.headerKey}": ""
      },
      "directTools": true
    }
  }
}
MCPEOF
        # Inject the real key (JSON-safe)
        python3 -c "
import json, sys
with open('\${AGENT_DIR}/mcp.json') as f: d = json.load(f)
d['mcpServers']['${key.write.serverId}']['headers']['${key.write.headerKey}'] = '\${val}'
with open('\${AGENT_DIR}/mcp.json','w') as f: json.dump(d, f, indent=2)
" 2>/dev/null || sed -i.bak "s/\"${key.write.headerKey}\": \"\"/\"${key.write.headerKey}\": \"\${val}\"/" "\${AGENT_DIR}/mcp.json" && rm -f "\${AGENT_DIR}/mcp.json.bak"
        ok "${key.label} MCP configured."
    fi`
      );
    } else if (key.write.type === "auth") {
      authKeyBlocks.push(
        `    if prompt_yn "${prompt}" ${defaultFlag}; then
        read -rsp "  ${key.label} API key: " val
        echo
        cat > "\${AGENT_DIR}/auth.json" <<AUTHEOF
{
  "${key.write.providerId}": {
    "type": "${key.write.authType}",
    "key": ""
  }
}
AUTHEOF
        # Inject the real key
        python3 -c "
import json, sys
with open('\${AGENT_DIR}/auth.json') as f: d = json.load(f)
d['${key.write.providerId}']['key'] = '\${val}'
with open('\${AGENT_DIR}/auth.json','w') as f: json.dump(d, f, indent=2)
" 2>/dev/null || sed -i.bak "s/\"key\": \"\"/\"key\": \"\${val}\"/" "\${AGENT_DIR}/auth.json" && rm -f "\${AGENT_DIR}/auth.json.bak"
        ok "${key.label} key saved to auth.json."
    fi`
      );
    }
  }

  const allKeyBlocks = [...envKeyBlocks, ...mcpKeyBlocks, ...authKeyBlocks];

  const packageInstallCmds = packages
    .map((pkg: string) => `        pi package install ${pkg} || warn "Failed to install ${pkg}"`)
    .join("\n");

  const bunInstallCmds = bunInstallDirs
    .map((dir: string) => {
      const fullPath = dir === "." ? "$AGENT_DIR" : "$AGENT_DIR/" + dir;
      const checkPath = dir === "." ? '"${AGENT_DIR}/package.json"' : `"${fullPath}/package.json"`;
      return `            if [[ -f ${checkPath} ]]; then
                (cd "${fullPath}" && bun install) || warn "bun install failed in ${dir === "." ? "agent root" : dir}"
            fi`;
    })
    .join("\n");

  return `#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Pi Coding Agent — Custom Setup Installer
# ---------------------------------------------------------------------------
# ⚡  AUTO-GENERATED from manifest.json — do not edit by hand!
#     Regenerate with:  bun run generate.ts
# ---------------------------------------------------------------------------
# macOS / Linux:
#   curl -fsSL https://raw.githubusercontent.com/pcstyle/my-pi-setup/main/install.sh | bash
# ---------------------------------------------------------------------------

REPO_RAW="${repoRaw}"
PI_DIR="\${HOME}/.pi"
AGENT_DIR="\${PI_DIR}/agent"
BACKUP_DIR="\${PI_DIR}.bak/$(date +%Y%m%d_%H%M%S)"

CYAN='\\033[0;36m'
GREEN='\\033[0;32m'
YELLOW='\\033[1;33m'
RED='\\033[0;31m'
BOLD='\\033[1m'
RESET='\\033[0m'

info()  { echo -e "\${CYAN}[INFO]\${RESET} $*"; }
ok()    { echo -e "\${GREEN}[OK]\${RESET} $*"; }
warn()  { echo -e "\${YELLOW}[WARN]\${RESET} $*"; }
err()   { echo -e "\${RED}[ERR]\${RESET} $*" >&2; }

prompt_yn() {
    local msg="$1"
    local default="\${2:-y}"
    local ans
    while true; do
        if [[ "$default" == "y" ]]; then
            read -rp "\${msg} [Y/n]: " ans
            ans=\${ans:-Y}
        else
            read -rp "\${msg} [y/N]: " ans
            ans=\${ans:-N}
        fi
        case "$ans" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# 1. Detect / install Pi
# ---------------------------------------------------------------------------
install_pi() {
    info "Pi is not installed. Attempting to install..."

    if command -v bun &>/dev/null; then
        info "Using Bun..."
        bun add -g @mariozechner/pi-coding-agent || true
    elif command -v pnpm &>/dev/null; then
        info "Using PNPM..."
        pnpm add -g @mariozechner/pi-coding-agent || true
    elif command -v npm &>/dev/null; then
        info "Using NPM..."
        npm install -g @mariozechner/pi-coding-agent || true
    else
        err "No package manager found (tried: bun, pnpm, npm)."
        err "Please install Bun or Node.js first, then re-run this installer."
        exit 1
    fi

    # Re-check
    if ! command -v pi &>/dev/null && ! command -v pi-coding-agent &>/dev/null; then
        if command -v npx &>/dev/null; then
            info "npx fallback available."
        else
            err "Pi installation failed or binary is not on PATH."
            exit 1
        fi
    fi
}

check_pi() {
    if command -v pi &>/dev/null; then
        ok "Pi found: $(command -v pi)"
        return 0
    fi

    local possible_bins=(
        "\${HOME}/.bun/bin/pi"
        "\${HOME}/.local/share/pnpm/pi"
        "\${HOME}/.npm-global/bin/pi"
        "/usr/local/bin/pi"
    )
    for p in "\${possible_bins[@]}"; do
        if [[ -x "$p" ]]; then
            ok "Pi found: $p"
            export PATH="$(dirname "$p"):\${PATH}"
            return 0
        fi
    done

    return 1
}

# ---------------------------------------------------------------------------
# 2. Backup existing config
# ---------------------------------------------------------------------------
backup_existing() {
    if [[ -d "$AGENT_DIR" ]]; then
        if prompt_yn "Existing Pi config found. Back it up before overwriting?" "y"; then
            mkdir -p "$BACKUP_DIR"
            cp -a "$AGENT_DIR" "$BACKUP_DIR/"
            ok "Backup saved to: \${BACKUP_DIR}"
        fi
        info "Clearing existing agent directory..."
        rm -rf "$AGENT_DIR"
    fi
    mkdir -p "$AGENT_DIR"
}

# ---------------------------------------------------------------------------
# 3. Pull files from GitHub
# ---------------------------------------------------------------------------
pull_file() {
    local rel_path="$1"
    local dest="$2"
    local url="\${REPO_RAW}/agent/\${rel_path}"
    local dir
    dir=$(dirname "$dest")
    mkdir -p "$dir"
    info "Downloading: \${rel_path}"
    if ! curl -fsSL "$url" -o "$dest"; then
        err "Failed to download: \${url}"
        return 1
    fi
}

pull_all() {
${indent(fileEntries, 4)}

    ok "All files downloaded."
}

# ---------------------------------------------------------------------------
# 4. Ensure Bun is available
# ---------------------------------------------------------------------------
ensure_bun() {
    if command -v bun &>/dev/null; then
        return 0
    fi

    if ! prompt_yn "Bun is not installed. Install it now for extension dependencies?" "y"; then
        return 1
    fi

    info "Installing Bun..."
    if command -v curl &>/dev/null; then
        curl -fsSL https://bun.sh/install | bash
    elif command -v wget &>/dev/null; then
        wget -qO- https://bun.sh/install | bash
    else
        warn "Neither curl nor wget was found, so Bun could not be installed automatically."
        return 1
    fi

    export PATH="\${HOME}/.bun/bin:\${PATH}"
    if command -v bun &>/dev/null; then
        ok "Bun installed successfully."
        return 0
    fi

    warn "Bun install finished, but bun is not on PATH yet. You may need to reopen your terminal."
    return 0
}

# ---------------------------------------------------------------------------
# 5. Optional API key / service setup
# ---------------------------------------------------------------------------
setup_api_keys() {
    echo
    echo -e "\${BOLD}--- Optional API Key / Service Setup ---\${RESET}"

    local env_file="\${AGENT_DIR}/.env"
    : > "$env_file"

${indent(allKeyBlocks.join("\n\n"), 4)}
}

# ---------------------------------------------------------------------------
# 6. Post-install
# ---------------------------------------------------------------------------
post_install() {
    echo
    echo -e "\${BOLD}--- Post-Install Options ---\${RESET}"

    if prompt_yn "Install recommended Pi packages now? (${packages.map((p: string) => p.split("/").pop()).join(", ")})" "n"; then
        info "Installing packages..."
${indent(packageInstallCmds, 8)}
        ok "Packages installed."
    fi

    if prompt_yn "Install extension dependencies with Bun now?" "n"; then
        if ensure_bun; then
${indent(bunInstallCmds, 12)}
            ok "Bun dependencies installed."
        else
            warn "Bun setup was skipped, so extension deps were skipped."
        fi
    fi

    if prompt_yn "Open Pi to verify the setup?" "n"; then
        pi || true
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo -e "\${BOLD}\${CYAN}"
    cat <<'BANNER'
    ____  _       __
   / __ \\(_)___  / /_  ____  ____  ___  _____
  / /_/ / / __ \\/ __ \\/ __ \\/ __ \\/ _ \\/ ___/
 / ____/ / /_/ / / / / /_/ / /_/ /  __/ /
/_/   /_/ .___/_/ /_/\\____/ .___/\\___/_/
       /_/               /_/
BANNER
    echo -e "\${RESET}"

    info "Checking for Pi installation..."
    if ! check_pi; then
        install_pi
        check_pi || { err "Pi still not found after installation."; exit 1; }
    fi

    backup_existing
    pull_all
    setup_api_keys
    post_install

    echo
    ok "Setup complete! Your Pi config is in: \${AGENT_DIR}"
    if [[ -d "$BACKUP_DIR" ]]; then
        info "Backup location: \${BACKUP_DIR}"
    fi
    echo
    info "To start Pi, run: pi"
}

main "$@"
`;
}

// ---------------------------------------------------------------------------
// Generate install.ps1 (PowerShell)
// ---------------------------------------------------------------------------

function generatePowerShell(): string {
  const fileEntries = files.map((f: string) => {
    const psPath = f === "." ? "Join-Path $AgentDir '.'" : `Join-Path $AgentDir '${f}'`;
    return `    Download-File '${f}' (${psPath})`;
  }).join("\n");

  const envKeyBlocks: string[] = [];
  const mcpKeyBlocks: string[] = [];
  const authKeyBlocks: string[] = [];

  for (const key of apiKeys) {
    const defaultNo = key.defaultNo ? "$false" : "$true";
    const prompt = key.prompt;

    if (key.write.type === "env") {
      envKeyBlocks.push(
        `    if (Test-YesNo '${prompt}' ${defaultNo}) {
        $key = Read-Host '  ${key.label} API key'
        Add-Content -Path $envFile -Value "${key.write.variable}=$key"
        Write-Ok '${key.label} key saved.'
    }`
      );
    } else if (key.write.type === "mcp") {
      mcpKeyBlocks.push(
        `    if (Test-YesNo '${prompt}' ${defaultNo}) {
        $key = Read-Host '  ${key.label} API key'
        $mcpJson = @{
            mcpServers = @{
                '${key.write.serverId}' = @{
                    type = 'http'
                    url = '${key.write.url}'
                    headers = @{ '${key.write.headerKey}' = $key }
                    directTools = $true
                }
            }
        } | ConvertTo-Json -Depth 10
        Set-Content -Path (Join-Path $AgentDir 'mcp.json') -Value $mcpJson
        Write-Ok '${key.label} MCP configured.'
    }`
      );
    } else if (key.write.type === "auth") {
      authKeyBlocks.push(
        `    if (Test-YesNo '${prompt}' ${defaultNo}) {
        $key = Read-Host '  ${key.label} API key'
        $authJson = @{
            '${key.write.providerId}' = @{ type = '${key.write.authType}'; key = $key }
        } | ConvertTo-Json -Depth 10
        Set-Content -Path (Join-Path $AgentDir 'auth.json') -Value $authJson
        Write-Ok '${key.label} key saved to auth.json.'
    }`
      );
    }
  }

  const allKeyBlocks = [...envKeyBlocks, ...mcpKeyBlocks, ...authKeyBlocks];

  const packageInstallCmds = packages.map((pkg: string) =>
    `        pi package install ${pkg} | Out-Host`
  ).join("\n");

  const bunPushPop = bunInstallDirs.map((dir: string) => {
    const dirLabel = dir === "." ? "agent root" : dir;
    const fullPath = dir === "." ? "$AgentDir" : `Join-Path $AgentDir '${dir}'`;
    return `        if (Test-Path (Join-Path ${fullPath} 'package.json')) {
            Push-Location ${fullPath}
            try { bun install | Out-Host }
            finally { Pop-Location }
        }`;
  }).join("\n");

  return `param(
    [string]$RepoRaw = '${repoRaw}'
)

$ErrorActionPreference = 'Stop'

$PiDir = Join-Path $HOME '.pi'
$AgentDir = Join-Path $PiDir 'agent'
$BackupRoot = Join-Path $HOME '.pi.bak'
$BackupDir = Join-Path $BackupRoot (Get-Date -Format 'yyyyMMdd_HHmmss')

function Write-Info { param([string]$Msg) Write-Host "[INFO] $Msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "[OK]   $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "[WARN] $Msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$Msg) Write-Host "[ERR]  $Msg" -ForegroundColor Red }

function Test-YesNo {
    param(
        [string]$Prompt,
        [bool]$Default = $true
    )

    while ($true) {
        $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
        $answer = Read-Host "$Prompt $suffix"
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $Default
        }

        switch ($answer.Trim().ToLowerInvariant()) {
            'y' { return $true }
            'yes' { return $true }
            'n' { return $false }
            'no' { return $false }
        }
    }
}

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Install-Pi {
    Write-Info 'Pi is not installed. Attempting to install...'

    if (Test-Command bun) {
        Write-Info 'Using Bun...'
        bun add -g @mariozechner/pi-coding-agent | Out-Host
    }
    elseif (Test-Command pnpm) {
        Write-Info 'Using PNPM...'
        pnpm add -g @mariozechner/pi-coding-agent | Out-Host
    }
    elseif (Test-Command npm) {
        Write-Info 'Using NPM...'
        npm install -g @mariozechner/pi-coding-agent | Out-Host
    }
    else {
        throw 'No package manager found (tried bun, pnpm, npm). Install Bun or Node.js first.'
    }

    if (-not (Test-Command pi) -and -not (Test-Command pi-coding-agent)) {
        Write-Warn 'Pi binary is not on PATH yet. You may need to open a new shell.'
    }
}

function Test-PiInstalled {
    if (Test-Command pi) {
        Write-Ok "Pi found: $(Get-Command pi).Source"
        return $true
    }

    $candidateBins = @(
        (Join-Path $HOME '.bun\\bin\\pi.exe'),
        (Join-Path $HOME '.bun\\bin\\pi'),
        (Join-Path $HOME 'AppData\\Local\\pnpm\\pi.cmd'),
        (Join-Path $HOME 'AppData\\Roaming\\npm\\pi.cmd'),
        'C:\\Program Files\\nodejs\\pi.cmd'
    )

    foreach ($bin in $candidateBins) {
        if (Test-Path $bin) {
            Write-Ok "Pi found: $bin"
            return $true
        }
    }

    return $false
}

function Backup-Existing {
    if (Test-Path $AgentDir) {
        if (Test-YesNo 'Existing Pi config found. Back it up before overwriting?') {
            New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
            New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
            Copy-Item -Path $AgentDir -Destination $BackupDir -Recurse -Force
            Write-Ok "Backup saved to: $BackupDir"
        }

        Write-Info 'Clearing existing agent directory...'
        Remove-Item -Path $AgentDir -Recurse -Force
    }

    New-Item -ItemType Directory -Force -Path $AgentDir | Out-Null
}

function Download-File {
    param(
        [string]$RelativePath,
        [string]$Destination
    )

    $url = "$RepoRaw/agent/$RelativePath"
    $parent = Split-Path $Destination -Parent
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Write-Info "Downloading: $RelativePath"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $Destination
}

function Pull-All {
${indent(fileEntries, 4)}

    Write-Ok 'All files downloaded.'
}

function Setup-ApiKeys {
    Write-Host ''
    Write-Host '--- Optional API Key / Service Setup ---' -ForegroundColor White

    $envFile = Join-Path $AgentDir '.env'
    Set-Content -Path $envFile -Value ''

${indent(allKeyBlocks.join("\n\n"), 4)}
}

function Ensure-Bun {
    if (Test-Command bun) {
        return $true
    }

    if (-not (Test-YesNo 'Bun is not installed. Install it now for extension dependencies?' $true)) {
        return $false
    }

    if (Test-Command winget) {
        Write-Info 'Installing Bun via winget...'
        winget install --id Oven-sh.Bun -e --accept-package-agreements --accept-source-agreements | Out-Host
    }
    else {
        Write-Info 'Installing Bun via official install script...'
        Invoke-Expression (Invoke-RestMethod 'https://bun.sh/install.ps1')
    }

    Start-Sleep -Seconds 2
    return (Test-Command bun)
}

function Post-Install {
    Write-Host ''
    Write-Host '--- Post-Install Options ---' -ForegroundColor White

    if (Test-YesNo 'Install recommended Pi packages now? (${packages.map((p: string) => p.split("/").pop()).join(", ")})' $false) {
        Write-Info 'Installing packages...'
${indent(packageInstallCmds, 8)}
        Write-Ok 'Packages installed.'
    }

    if (Test-YesNo 'Install extension dependencies with Bun now?' $false) {
        if (Ensure-Bun) {
${indent(bunPushPop, 12)}
            Write-Ok 'Bun dependencies installed.'
        }
        else {
            Write-Warn 'Bun was not installed, so extension deps were skipped.'
        }
    }

    if (Test-YesNo 'Open Pi to verify the setup?' $false) {
        pi
    }
}

Write-Host ''
Write-Host '    ____  _       __' -ForegroundColor Cyan
Write-Host '   / __ \\(_)___  / /_  ____  ____  ___  _____' -ForegroundColor Cyan
Write-Host '  / /_/ / / __ \\/ __ \\/ __ \\/ __ \\/ _ \\/ ___/' -ForegroundColor Cyan
Write-Host ' / ____/ / /_/ / / / / /_/ / /_/ /  __/ /' -ForegroundColor Cyan
Write-Host '/_/   /_/ .___/_/ /_/\\____/ .___/\\___/_/' -ForegroundColor Cyan
Write-Host '       /_/               /_/' -ForegroundColor Cyan
Write-Host ''

Write-Info 'Checking for Pi installation...'
if (-not (Test-PiInstalled)) {
    Install-Pi
    if (-not (Test-PiInstalled)) {
        throw 'Pi still not found after installation.'
    }
}

Backup-Existing
Pull-All
Setup-ApiKeys
Post-Install

Write-Host ''
Write-Ok "Setup complete! Your Pi config is in: $AgentDir"
if (Test-Path $BackupDir) {
    Write-Info "Backup location: $BackupDir"
}
Write-Host ''
Write-Info 'To start Pi, run: pi'
`;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

const bashOut = generateBash();
const ps1Out = generatePowerShell();

const shPath = resolve(__dirname, "install.sh");
const ps1Path = resolve(__dirname, "install.ps1");

writeFileSync(shPath, bashOut, "utf-8");
writeFileSync(ps1Path, ps1Out, "utf-8");

// Make install.sh executable
import { chmodSync } from "fs";
chmodSync(shPath, 0o755);

console.log(`Generated:`);
console.log(`  ${shPath}`);
console.log(`  ${ps1Path}`);