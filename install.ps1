param(
    [string]$RepoRaw = 'https://raw.githubusercontent.com/pc-style/my-pi-setup/main'
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
        bun add -g @earendil-works/pi-coding-agent | Out-Host
    }
    elseif (Test-Command pnpm) {
        Write-Info 'Using PNPM...'
        pnpm add -g @earendil-works/pi-coding-agent | Out-Host
    }
    elseif (Test-Command npm) {
        Write-Info 'Using NPM...'
        npm install -g @earendil-works/pi-coding-agent | Out-Host
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
        Download-File '.firecrawl/pi-conventions.json' (Join-Path $AgentDir '.firecrawl/pi-conventions.json')
        Download-File '.firecrawl/pi-packages.json' (Join-Path $AgentDir '.firecrawl/pi-packages.json')
        Download-File '.firecrawl/pi-skillforge.json' (Join-Path $AgentDir '.firecrawl/pi-skillforge.json')
        Download-File '.firecrawl/pi-skillful.json' (Join-Path $AgentDir '.firecrawl/pi-skillful.json')
        Download-File 'extensions/cache-health.ts' (Join-Path $AgentDir 'extensions/cache-health.ts')
        Download-File 'extensions/context-quarantine.ts' (Join-Path $AgentDir 'extensions/context-quarantine.ts')
        Download-File 'extensions/context.ts' (Join-Path $AgentDir 'extensions/context.ts')
        Download-File 'extensions/copy-all.ts' (Join-Path $AgentDir 'extensions/copy-all.ts')
        Download-File 'extensions/diff.ts' (Join-Path $AgentDir 'extensions/diff.ts')
        Download-File 'extensions/firecrawl-search.ts' (Join-Path $AgentDir 'extensions/firecrawl-search.ts')
        Download-File 'extensions/flow-title.ts' (Join-Path $AgentDir 'extensions/flow-title.ts')
        Download-File 'extensions/git-status-widget.ts' (Join-Path $AgentDir 'extensions/git-status-widget.ts')
        Download-File 'extensions/lg.ts' (Join-Path $AgentDir 'extensions/lg.ts')
        Download-File 'extensions/openai-codex-fast-mode.ts' (Join-Path $AgentDir 'extensions/openai-codex-fast-mode.ts')
        Download-File 'extensions/tps-tracker.ts' (Join-Path $AgentDir 'extensions/tps-tracker.ts')
        Download-File 'extensions/update.ts' (Join-Path $AgentDir 'extensions/update.ts')
        Download-File 'extensions/usage.ts' (Join-Path $AgentDir 'extensions/usage.ts')
        Download-File 'extensions/yeet.ts' (Join-Path $AgentDir 'extensions/yeet.ts')
        Download-File 'extensions/zsh-user-bash.ts' (Join-Path $AgentDir 'extensions/zsh-user-bash.ts')
        Download-File 'extensions/ephemeral/apply.ts' (Join-Path $AgentDir 'extensions/ephemeral/apply.ts')
        Download-File 'extensions/ephemeral/catalog.ts' (Join-Path $AgentDir 'extensions/ephemeral/catalog.ts')
        Download-File 'extensions/ephemeral/index.ts' (Join-Path $AgentDir 'extensions/ephemeral/index.ts')
        Download-File 'extensions/ephemeral/manifest.ts' (Join-Path $AgentDir 'extensions/ephemeral/manifest.ts')
        Download-File 'extensions/ephemeral/mcp.ts' (Join-Path $AgentDir 'extensions/ephemeral/mcp.ts')
        Download-File 'extensions/ephemeral/preview.ts' (Join-Path $AgentDir 'extensions/ephemeral/preview.ts')
        Download-File 'extensions/ephemeral/project-state.ts' (Join-Path $AgentDir 'extensions/ephemeral/project-state.ts')
        Download-File 'extensions/ephemeral/types.ts' (Join-Path $AgentDir 'extensions/ephemeral/types.ts')
        Download-File 'extensions/ephemeral/ui.ts' (Join-Path $AgentDir 'extensions/ephemeral/ui.ts')
        Download-File 'extensions/ephemeral/util.ts' (Join-Path $AgentDir 'extensions/ephemeral/util.ts')
        Download-File 'extensions/pi-mcp/package.json' (Join-Path $AgentDir 'extensions/pi-mcp/package.json')
        Download-File 'extensions/pi-mcp/cli.js' (Join-Path $AgentDir 'extensions/pi-mcp/cli.js')
        Download-File 'extensions/pi-mcp/pnpm-lock.yaml' (Join-Path $AgentDir 'extensions/pi-mcp/pnpm-lock.yaml')
        Download-File 'extensions/pi-mcp/src/app-bridge.bundle.js' (Join-Path $AgentDir 'extensions/pi-mcp/src/app-bridge.bundle.js')
        Download-File 'extensions/pi-mcp/src/commands.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/commands.ts')
        Download-File 'extensions/pi-mcp/src/config.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/config.ts')
        Download-File 'extensions/pi-mcp/src/consent-manager.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/consent-manager.ts')
        Download-File 'extensions/pi-mcp/src/direct-tools.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/direct-tools.ts')
        Download-File 'extensions/pi-mcp/src/errors.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/errors.ts')
        Download-File 'extensions/pi-mcp/src/glimpse-ui.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/glimpse-ui.ts')
        Download-File 'extensions/pi-mcp/src/host-html-template.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/host-html-template.ts')
        Download-File 'extensions/pi-mcp/src/index.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/index.ts')
        Download-File 'extensions/pi-mcp/src/init.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/init.ts')
        Download-File 'extensions/pi-mcp/src/lifecycle.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/lifecycle.ts')
        Download-File 'extensions/pi-mcp/src/logger.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/logger.ts')
        Download-File 'extensions/pi-mcp/src/mcp-auth.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/mcp-auth.ts')
        Download-File 'extensions/pi-mcp/src/mcp-oauth-callback.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/mcp-oauth-callback.ts')
        Download-File 'extensions/pi-mcp/src/mcp-oauth-provider.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/mcp-oauth-provider.ts')
        Download-File 'extensions/pi-mcp/src/mcp-panel.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/mcp-panel.ts')
        Download-File 'extensions/pi-mcp/src/metadata-cache.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/metadata-cache.ts')
        Download-File 'extensions/pi-mcp/src/npx-resolver.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/npx-resolver.ts')
        Download-File 'extensions/pi-mcp/src/proxy-modes.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/proxy-modes.ts')
        Download-File 'extensions/pi-mcp/src/resource-tools.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/resource-tools.ts')
        Download-File 'extensions/pi-mcp/src/server-manager.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/server-manager.ts')
        Download-File 'extensions/pi-mcp/src/state.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/state.ts')
        Download-File 'extensions/pi-mcp/src/tool-metadata.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/tool-metadata.ts')
        Download-File 'extensions/pi-mcp/src/tool-registrar.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/tool-registrar.ts')
        Download-File 'extensions/pi-mcp/src/types.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/types.ts')
        Download-File 'extensions/pi-mcp/src/ui-resource-handler.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/ui-resource-handler.ts')
        Download-File 'extensions/pi-mcp/src/ui-server.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/ui-server.ts')
        Download-File 'extensions/pi-mcp/src/ui-session.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/ui-session.ts')
        Download-File 'extensions/pi-mcp/src/ui-stream-types.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/ui-stream-types.ts')
        Download-File 'extensions/pi-mcp/src/utils.ts' (Join-Path $AgentDir 'extensions/pi-mcp/src/utils.ts')

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
                    'context7' = @{
                        type = 'http'
                        url = 'https://mcp.context7.com/mcp'
                        headers = @{ 'CONTEXT7_API_KEY' = $key }
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

    if (Test-YesNo 'Install recommended Pi packages now? (pi-questionnaire, pi-subagents, pi-plan-mode)' $false) {
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
                        try { bun install | Out-Host }
                        finally { Pop-Location }
                    }
                    if (Test-Path (Join-Path Join-Path $AgentDir 'extensions/pi-mcp' 'package.json')) {
                        Push-Location Join-Path $AgentDir 'extensions/pi-mcp'
                        try { bun install | Out-Host }
                        finally { Pop-Location }
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
