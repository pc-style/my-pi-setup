param(
    [string]$RepoRaw = 'https://raw.githubusercontent.com/pcstyle/my-pi-setup/main'
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
        (Join-Path $HOME '.bun\bin\pi.exe'),
        (Join-Path $HOME '.bun\bin\pi'),
        (Join-Path $HOME 'AppData\Local\pnpm\pi.cmd'),
        (Join-Path $HOME 'AppData\Roaming\npm\pi.cmd'),
        'C:\Program Files\nodejs\pi.cmd'
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
    Download-File 'AGENTS.md' (Join-Path $AgentDir 'AGENTS.md')
    Download-File 'settings.json' (Join-Path $AgentDir 'settings.json')
    Download-File 'models.json' (Join-Path $AgentDir 'models.json')
    Download-File 'package.json' (Join-Path $AgentDir 'package.json')
    Download-File 'bun.lock' (Join-Path $AgentDir 'bun.lock')
    Download-File '.env.example' (Join-Path $AgentDir '.env.example')

    Download-File 'themes/github-dark-default.json' (Join-Path $AgentDir 'themes/github-dark-default.json')

    foreach ($file in @('pi-conventions.json', 'pi-packages.json', 'pi-skillforge.json', 'pi-skillful.json')) {
        Download-File ".firecrawl/$file" (Join-Path $AgentDir ".firecrawl/$file")
    }

    foreach ($file in @(
        'cache-health.ts', 'context-quarantine.ts', 'context.ts', 'copy-all.ts', 'diff.ts',
        'firecrawl-search.ts', 'flow-title.ts', 'git-status-widget.ts', 'lg.ts',
        'openai-codex-fast-mode.ts', 'tps-tracker.ts', 'update.ts', 'usage.ts', 'yeet.ts', 'zsh-user-bash.ts'
    )) {
        Download-File "extensions/$file" (Join-Path $AgentDir "extensions/$file")
    }

    foreach ($file in @('apply.ts', 'catalog.ts', 'index.ts', 'manifest.ts', 'mcp.ts', 'preview.ts', 'project-state.ts', 'types.ts', 'ui.ts', 'util.ts')) {
        Download-File "extensions/ephemeral/$file" (Join-Path $AgentDir "extensions/ephemeral/$file")
    }

    Download-File 'extensions/pi-mcp/package.json' (Join-Path $AgentDir 'extensions/pi-mcp/package.json')
    Download-File 'extensions/pi-mcp/cli.js' (Join-Path $AgentDir 'extensions/pi-mcp/cli.js')
    Download-File 'extensions/pi-mcp/pnpm-lock.yaml' (Join-Path $AgentDir 'extensions/pi-mcp/pnpm-lock.yaml')

    foreach ($file in @(
        'app-bridge.bundle.js', 'commands.ts', 'config.ts', 'consent-manager.ts', 'direct-tools.ts',
        'errors.ts', 'glimpse-ui.ts', 'host-html-template.ts', 'index.ts', 'init.ts', 'lifecycle.ts',
        'logger.ts', 'mcp-auth.ts', 'mcp-oauth-callback.ts', 'mcp-oauth-provider.ts', 'mcp-panel.ts',
        'metadata-cache.ts', 'npx-resolver.ts', 'proxy-modes.ts', 'resource-tools.ts', 'server-manager.ts',
        'state.ts', 'tool-metadata.ts', 'tool-registrar.ts', 'types.ts', 'ui-resource-handler.ts',
        'ui-server.ts', 'ui-session.ts', 'ui-stream-types.ts', 'utils.ts'
    )) {
        Download-File "extensions/pi-mcp/src/$file" (Join-Path $AgentDir "extensions/pi-mcp/src/$file")
    }

    Write-Ok 'All files downloaded.'
}

function Setup-ApiKeys {
    Write-Host ''
    Write-Host '--- Optional API Key / Service Setup ---' -ForegroundColor White

    $envFile = Join-Path $AgentDir '.env'
    Set-Content -Path $envFile -Value ''

    if (Test-YesNo 'Set up Firecrawl API key? (used by firecrawl-search extension)' $false) {
        $key = Read-Host '  Firecrawl API key'
        Add-Content -Path $envFile -Value "FIRECRAWL_API_KEY=$key"
        Write-Ok 'Firecrawl key saved.'
    }

    if (Test-YesNo 'Set up Context7 MCP API key? (documentation lookup)' $false) {
        $key = Read-Host '  Context7 API key'
        $mcpJson = @{
            mcpServers = @{
                context7 = @{
                    type = 'http'
                    url = 'https://mcp.context7.com/mcp'
                    headers = @{ CONTEXT7_API_KEY = $key }
                    directTools = $true
                }
            }
        } | ConvertTo-Json -Depth 10
        Set-Content -Path (Join-Path $AgentDir 'mcp.json') -Value $mcpJson
        Write-Ok 'Context7 MCP configured.'
    }

    if (Test-YesNo 'Set up OpenCode-Go API key? (default provider in this setup)' $false) {
        $key = Read-Host '  OpenCode-Go API key'
        $authJson = @{
            'opencode-go' = @{ type = 'api_key'; key = $key }
        } | ConvertTo-Json -Depth 10
        Set-Content -Path (Join-Path $AgentDir 'auth.json') -Value $authJson
        Write-Ok 'OpenCode-Go key saved to auth.json.'
    }
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

    if (Test-YesNo 'Install recommended Pi packages now? (@dreki-gg/pi-questionnaire, @tintinweb/pi-subagents, @dreki-gg/pi-plan-mode)' $false) {
        Write-Info 'Installing packages...'
        pi package install @dreki-gg/pi-questionnaire | Out-Host
        pi package install @tintinweb/pi-subagents | Out-Host
        pi package install @dreki-gg/pi-plan-mode | Out-Host
        Write-Ok 'Packages installed.'
    }

    if (Test-YesNo 'Install extension dependencies with Bun now?' $false) {
        if (Ensure-Bun) {
            if (Test-Path (Join-Path $AgentDir 'package.json')) {
                Push-Location $AgentDir
                try {
                    bun install | Out-Host
                }
                finally {
                    Pop-Location
                }
            }

            $piMcpDir = Join-Path $AgentDir 'extensions/pi-mcp'
            if (Test-Path (Join-Path $piMcpDir 'package.json')) {
                Push-Location $piMcpDir
                try {
                    bun install | Out-Host
                }
                finally {
                    Pop-Location
                }
            }

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
Write-Host '   / __ \(_)___  / /_  ____  ____  ___  _____' -ForegroundColor Cyan
Write-Host '  / /_/ / / __ \/ __ \/ __ \/ __ \/ _ \/ ___/' -ForegroundColor Cyan
Write-Host ' / ____/ / /_/ / / / / /_/ / /_/ /  __/ /' -ForegroundColor Cyan
Write-Host '/_/   /_/ .___/_/ /_/\____/ .___/\___/_/' -ForegroundColor Cyan
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
