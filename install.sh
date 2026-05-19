#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Pi Coding Agent — Custom Setup Installer
# ---------------------------------------------------------------------------
# AUTO-GENERATED from manifest.json — do not edit by hand!
# Regenerate with:  bun run generate.ts
# ---------------------------------------------------------------------------
# macOS / Linux:
#   curl -fsSL https://raw.githubusercontent.com/pc-style/my-pi-setup/main/install.sh | bash
# ---------------------------------------------------------------------------

REPO_RAW="https://raw.githubusercontent.com/pc-style/my-pi-setup/main"
PI_DIR="${HOME}/.pi"
AGENT_DIR="${PI_DIR}/agent"
BACKUP_DIR="${PI_DIR}.bak/$(date +%Y%m%d_%H%M%S)"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { echo -e "${CYAN}[INFO]${RESET} $*"; }
ok()    { echo -e "${GREEN}[OK]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET} $*"; }
err()   { echo -e "${RED}[ERR]${RESET} $*" >&2; }

# Read from the controlling terminal so prompts work even when
# stdin is a pipe (e.g. curl ... | bash).
read_tty() {
    read "$@" < /dev/tty 2>/dev/null
}

prompt_yn() {
    local msg="$1"
    local default="${2:-y}"
    local ans
    while true; do
        if [[ "$default" == "y" ]]; then
            read_tty -rp "${msg} [Y/n]: " ans || return 0
            ans=${ans:-Y}
        else
            read_tty -rp "${msg} [y/N]: " ans || return 1
            ans=${ans:-N}
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
        bun add -g @earendil-works/pi-coding-agent || true
    elif command -v pnpm &>/dev/null; then
        info "Using PNPM..."
        pnpm add -g @earendil-works/pi-coding-agent || true
    elif command -v npm &>/dev/null; then
        info "Using NPM..."
        npm install -g @earendil-works/pi-coding-agent || true
    else
        err "No package manager found (tried: bun, pnpm, npm)."
        err "Please install Bun or Node.js first, then re-run this installer."
        exit 1
    fi

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
        "${HOME}/.bun/bin/pi"
        "${HOME}/.local/share/pnpm/pi"
        "${HOME}/.npm-global/bin/pi"
        "/usr/local/bin/pi"
    )
    for p in "${possible_bins[@]}"; do
        if [[ -x "$p" ]]; then
            ok "Pi found: $p"
            export PATH="$(dirname "$p"):${PATH}"
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
            ok "Backup saved to: ${BACKUP_DIR}"
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
    local url="${REPO_RAW}/agent/${rel_path}"
    local dir
    dir=$(dirname "$dest")
    mkdir -p "$dir"
    info "Downloading: ${rel_path}"
    if ! curl -fsSL "$url" -o "$dest"; then
        err "Failed to download: ${url}"
        return 1
    fi
}

pull_all() {
        pull_file "AGENTS.md" "${AGENT_DIR}/AGENTS.md"
        pull_file "settings.json" "${AGENT_DIR}/settings.json"
        pull_file "models.json" "${AGENT_DIR}/models.json"
        pull_file "package.json" "${AGENT_DIR}/package.json"
        pull_file "bun.lock" "${AGENT_DIR}/bun.lock"
        pull_file ".env.example" "${AGENT_DIR}/.env.example"
        pull_file "themes/github-dark-default.json" "${AGENT_DIR}/themes/github-dark-default.json"
        pull_file ".firecrawl/pi-conventions.json" "${AGENT_DIR}/.firecrawl/pi-conventions.json"
        pull_file ".firecrawl/pi-packages.json" "${AGENT_DIR}/.firecrawl/pi-packages.json"
        pull_file ".firecrawl/pi-skillforge.json" "${AGENT_DIR}/.firecrawl/pi-skillforge.json"
        pull_file ".firecrawl/pi-skillful.json" "${AGENT_DIR}/.firecrawl/pi-skillful.json"
        pull_file "extensions/cache-health.ts" "${AGENT_DIR}/extensions/cache-health.ts"
        pull_file "extensions/context-quarantine.ts" "${AGENT_DIR}/extensions/context-quarantine.ts"
        pull_file "extensions/context.ts" "${AGENT_DIR}/extensions/context.ts"
        pull_file "extensions/copy-all.ts" "${AGENT_DIR}/extensions/copy-all.ts"
        pull_file "extensions/diff.ts" "${AGENT_DIR}/extensions/diff.ts"
        pull_file "extensions/firecrawl-search.ts" "${AGENT_DIR}/extensions/firecrawl-search.ts"
        pull_file "extensions/flow-title.ts" "${AGENT_DIR}/extensions/flow-title.ts"
        pull_file "extensions/git-status-widget.ts" "${AGENT_DIR}/extensions/git-status-widget.ts"
        pull_file "extensions/lg.ts" "${AGENT_DIR}/extensions/lg.ts"
        pull_file "extensions/openai-codex-fast-mode.ts" "${AGENT_DIR}/extensions/openai-codex-fast-mode.ts"
        pull_file "extensions/tps-tracker.ts" "${AGENT_DIR}/extensions/tps-tracker.ts"
        pull_file "extensions/update.ts" "${AGENT_DIR}/extensions/update.ts"
        pull_file "extensions/usage.ts" "${AGENT_DIR}/extensions/usage.ts"
        pull_file "extensions/yeet.ts" "${AGENT_DIR}/extensions/yeet.ts"
        pull_file "extensions/zsh-user-bash.ts" "${AGENT_DIR}/extensions/zsh-user-bash.ts"
        pull_file "extensions/ephemeral/apply.ts" "${AGENT_DIR}/extensions/ephemeral/apply.ts"
        pull_file "extensions/ephemeral/catalog.ts" "${AGENT_DIR}/extensions/ephemeral/catalog.ts"
        pull_file "extensions/ephemeral/index.ts" "${AGENT_DIR}/extensions/ephemeral/index.ts"
        pull_file "extensions/ephemeral/manifest.ts" "${AGENT_DIR}/extensions/ephemeral/manifest.ts"
        pull_file "extensions/ephemeral/mcp.ts" "${AGENT_DIR}/extensions/ephemeral/mcp.ts"
        pull_file "extensions/ephemeral/preview.ts" "${AGENT_DIR}/extensions/ephemeral/preview.ts"
        pull_file "extensions/ephemeral/project-state.ts" "${AGENT_DIR}/extensions/ephemeral/project-state.ts"
        pull_file "extensions/ephemeral/types.ts" "${AGENT_DIR}/extensions/ephemeral/types.ts"
        pull_file "extensions/ephemeral/ui.ts" "${AGENT_DIR}/extensions/ephemeral/ui.ts"
        pull_file "extensions/ephemeral/util.ts" "${AGENT_DIR}/extensions/ephemeral/util.ts"
        pull_file "extensions/pi-mcp/package.json" "${AGENT_DIR}/extensions/pi-mcp/package.json"
        pull_file "extensions/pi-mcp/cli.js" "${AGENT_DIR}/extensions/pi-mcp/cli.js"
        pull_file "extensions/pi-mcp/pnpm-lock.yaml" "${AGENT_DIR}/extensions/pi-mcp/pnpm-lock.yaml"
        pull_file "extensions/pi-mcp/src/app-bridge.bundle.js" "${AGENT_DIR}/extensions/pi-mcp/src/app-bridge.bundle.js"
        pull_file "extensions/pi-mcp/src/commands.ts" "${AGENT_DIR}/extensions/pi-mcp/src/commands.ts"
        pull_file "extensions/pi-mcp/src/config.ts" "${AGENT_DIR}/extensions/pi-mcp/src/config.ts"
        pull_file "extensions/pi-mcp/src/consent-manager.ts" "${AGENT_DIR}/extensions/pi-mcp/src/consent-manager.ts"
        pull_file "extensions/pi-mcp/src/direct-tools.ts" "${AGENT_DIR}/extensions/pi-mcp/src/direct-tools.ts"
        pull_file "extensions/pi-mcp/src/errors.ts" "${AGENT_DIR}/extensions/pi-mcp/src/errors.ts"
        pull_file "extensions/pi-mcp/src/glimpse-ui.ts" "${AGENT_DIR}/extensions/pi-mcp/src/glimpse-ui.ts"
        pull_file "extensions/pi-mcp/src/host-html-template.ts" "${AGENT_DIR}/extensions/pi-mcp/src/host-html-template.ts"
        pull_file "extensions/pi-mcp/src/index.ts" "${AGENT_DIR}/extensions/pi-mcp/src/index.ts"
        pull_file "extensions/pi-mcp/src/init.ts" "${AGENT_DIR}/extensions/pi-mcp/src/init.ts"
        pull_file "extensions/pi-mcp/src/lifecycle.ts" "${AGENT_DIR}/extensions/pi-mcp/src/lifecycle.ts"
        pull_file "extensions/pi-mcp/src/logger.ts" "${AGENT_DIR}/extensions/pi-mcp/src/logger.ts"
        pull_file "extensions/pi-mcp/src/mcp-auth.ts" "${AGENT_DIR}/extensions/pi-mcp/src/mcp-auth.ts"
        pull_file "extensions/pi-mcp/src/mcp-oauth-callback.ts" "${AGENT_DIR}/extensions/pi-mcp/src/mcp-oauth-callback.ts"
        pull_file "extensions/pi-mcp/src/mcp-oauth-provider.ts" "${AGENT_DIR}/extensions/pi-mcp/src/mcp-oauth-provider.ts"
        pull_file "extensions/pi-mcp/src/mcp-panel.ts" "${AGENT_DIR}/extensions/pi-mcp/src/mcp-panel.ts"
        pull_file "extensions/pi-mcp/src/metadata-cache.ts" "${AGENT_DIR}/extensions/pi-mcp/src/metadata-cache.ts"
        pull_file "extensions/pi-mcp/src/npx-resolver.ts" "${AGENT_DIR}/extensions/pi-mcp/src/npx-resolver.ts"
        pull_file "extensions/pi-mcp/src/proxy-modes.ts" "${AGENT_DIR}/extensions/pi-mcp/src/proxy-modes.ts"
        pull_file "extensions/pi-mcp/src/resource-tools.ts" "${AGENT_DIR}/extensions/pi-mcp/src/resource-tools.ts"
        pull_file "extensions/pi-mcp/src/server-manager.ts" "${AGENT_DIR}/extensions/pi-mcp/src/server-manager.ts"
        pull_file "extensions/pi-mcp/src/state.ts" "${AGENT_DIR}/extensions/pi-mcp/src/state.ts"
        pull_file "extensions/pi-mcp/src/tool-metadata.ts" "${AGENT_DIR}/extensions/pi-mcp/src/tool-metadata.ts"
        pull_file "extensions/pi-mcp/src/tool-registrar.ts" "${AGENT_DIR}/extensions/pi-mcp/src/tool-registrar.ts"
        pull_file "extensions/pi-mcp/src/types.ts" "${AGENT_DIR}/extensions/pi-mcp/src/types.ts"
        pull_file "extensions/pi-mcp/src/ui-resource-handler.ts" "${AGENT_DIR}/extensions/pi-mcp/src/ui-resource-handler.ts"
        pull_file "extensions/pi-mcp/src/ui-server.ts" "${AGENT_DIR}/extensions/pi-mcp/src/ui-server.ts"
        pull_file "extensions/pi-mcp/src/ui-session.ts" "${AGENT_DIR}/extensions/pi-mcp/src/ui-session.ts"
        pull_file "extensions/pi-mcp/src/ui-stream-types.ts" "${AGENT_DIR}/extensions/pi-mcp/src/ui-stream-types.ts"
        pull_file "extensions/pi-mcp/src/utils.ts" "${AGENT_DIR}/extensions/pi-mcp/src/utils.ts"

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

    export PATH="${HOME}/.bun/bin:${PATH}"
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
    echo -e "${BOLD}--- Optional API Key / Service Setup ---${RESET}"

    local env_file="${AGENT_DIR}/.env"
    : > "$env_file"

        if prompt_yn "Set up Firecrawl API key? (used by firecrawl-search extension)" "n"; then
            read_tty -rsp "  Firecrawl API key: " val
            echo
            echo "FIRECRAWL_API_KEY=${val}" >> "$env_file"
            ok "Firecrawl key saved."
        fi

        if prompt_yn "Set up Context7 MCP API key? (documentation lookup)" "n"; then
            read_tty -rsp "  Context7 API key: " val
            echo
            escaped_val=$(printf '%s' "$val" | sed 's/[&/\\]/\\&/g')
            printf '%s\n' '{"mcpServers":{"context7":{"type":"http","url":"https://mcp.context7.com/mcp","headers":{"CONTEXT7_API_KEY":"__PLACEHOLDER__"},"directTools":true}}}' | sed "s/__PLACEHOLDER__/$escaped_val/g" > "$AGENT_DIR/mcp.json"
            ok "Context7 MCP configured."
        fi

        if prompt_yn "Set up OpenCode-Go API key? (default provider in this setup)" "n"; then
            read_tty -rsp "  OpenCode-Go API key: " val
            echo
            escaped_val=$(printf '%s' "$val" | sed 's/[&/\\]/\\&/g')
            printf '%s\n' '{"opencode-go":{"type":"api_key","key":"__PLACEHOLDER__"}}' | sed "s/__PLACEHOLDER__/$escaped_val/g" > "$AGENT_DIR/auth.json"
            ok "OpenCode-Go key saved to auth.json."
        fi
}

# ---------------------------------------------------------------------------
# 6. Post-install
# ---------------------------------------------------------------------------
post_install() {
    echo
    echo -e "${BOLD}--- Post-Install Options ---${RESET}"

    if prompt_yn "Install recommended Pi packages now? (pi-questionnaire, pi-subagents, pi-plan-mode)" "n"; then
        info "Installing packages..."
                pi package install @dreki-gg/pi-questionnaire || warn "Failed to install @dreki-gg/pi-questionnaire"
                pi package install @tintinweb/pi-subagents || warn "Failed to install @tintinweb/pi-subagents"
                pi package install @dreki-gg/pi-plan-mode || warn "Failed to install @dreki-gg/pi-plan-mode"
        ok "Packages installed."
    fi

    if prompt_yn "Install extension dependencies with Bun now?" "n"; then
        if ensure_bun; then
                        if [[ -f "${AGENT_DIR}/package.json" ]]; then
                            (cd "$AGENT_DIR" && bun install) || warn "bun install failed in agent root"
                        fi
                        if [[ -f "$AGENT_DIR/extensions/pi-mcp/package.json" ]]; then
                            (cd "$AGENT_DIR/extensions/pi-mcp" && bun install) || warn "bun install failed in extensions/pi-mcp"
                        fi
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
    echo -e "${BOLD}${CYAN}"
    cat <<'BANNER'
    ____  _       __
   / __ \(_)___  / /_  ____  ____  ___  _____
  / /_/ / / __ \/ __ \/ __ \/ __ \/ _ \/ ___/
 / ____/ / /_/ / / / / /_/ / /_/ /  __/ /
/_/   /_/ .___/_/ /_/\____/ .___/\___/_/
       /_/               /_/
BANNER
    echo -e "${RESET}"

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
    ok "Setup complete! Your Pi config is in: ${AGENT_DIR}"
    if [[ -d "$BACKUP_DIR" ]]; then
        info "Backup location: ${BACKUP_DIR}"
    fi
    echo
    info "To start Pi, run: pi"
}

main "$@"
