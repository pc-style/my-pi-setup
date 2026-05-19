#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Pi Coding Agent — Custom Setup Installer
# ---------------------------------------------------------------------------
# Run with:
#   curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/my-pi-setup/main/install.sh | bash
# ---------------------------------------------------------------------------

REPO_RAW="https://raw.githubusercontent.com/pcstyle/my-pi-setup/main"
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

prompt_yn() {
    local msg="$1"
    local default="${2:-y}"
    local ans
    while true; do
        if [[ "$default" == "y" ]]; then
            read -rp "${msg} [Y/n]: " ans
            ans=${ans:-Y}
        else
            read -rp "${msg} [y/N]: " ans
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
        bun add -g @mariozechner/pi-coding-agent || true
    elif command -v pnpm &>/dev/null; then
        info "Using PNPM..."
        pnpm add -g @mariozechner/pi-coding-agent || true
    elif command -v npm &>/dev/null; then
        info "Using NPM..."
        npm install -g @mariozechner/pi-coding-agent || true
    else
        err "No package manager found (tried: bun, pnpm, npm)."
        err "Please install Node.js + NPM or Bun first, then re-run this installer."
        exit 1
    fi

    # Re-check
    if ! command -v pi &>/dev/null && ! command -v pi-coding-agent &>/dev/null; then
        # Some package managers install as "pi-coding-agent" or put it in a non-standard path
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

    # npm/pnpm/bun global bins sometimes aren't on PATH in fresh shells
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
    # Core config
    pull_file "AGENTS.md"              "${AGENT_DIR}/AGENTS.md"
    pull_file "settings.json"          "${AGENT_DIR}/settings.json"
    pull_file "models.json"            "${AGENT_DIR}/models.json"
    pull_file "package.json"           "${AGENT_DIR}/package.json"
    pull_file "bun.lock"               "${AGENT_DIR}/bun.lock"
    pull_file ".env.example"           "${AGENT_DIR}/.env.example"

    # Themes
    pull_file "themes/github-dark-default.json" "${AGENT_DIR}/themes/github-dark-default.json"

    # Firecrawl skills
    pull_file ".firecrawl/pi-conventions.json"  "${AGENT_DIR}/.firecrawl/pi-conventions.json"
    pull_file ".firecrawl/pi-packages.json"     "${AGENT_DIR}/.firecrawl/pi-packages.json"
    pull_file ".firecrawl/pi-skillforge.json"   "${AGENT_DIR}/.firecrawl/pi-skillforge.json"
    pull_file ".firecrawl/pi-skillful.json"     "${AGENT_DIR}/.firecrawl/pi-skillful.json"

    # Extensions
    for f in cache-health.ts context-quarantine.ts context.ts copy-all.ts diff.ts \
             firecrawl-search.ts flow-title.ts git-status-widget.ts lg.ts \
             openai-codex-fast-mode.ts tps-tracker.ts update.ts usage.ts yeet.ts zsh-user-bash.ts; do
        pull_file "extensions/${f}" "${AGENT_DIR}/extensions/${f}"
    done

    # Ephemeral extensions
    for f in apply.ts catalog.ts index.ts manifest.ts mcp.ts preview.ts \
             project-state.ts types.ts ui.ts util.ts; do
        pull_file "extensions/ephemeral/${f}" "${AGENT_DIR}/extensions/ephemeral/${f}"
    done

    # pi-mcp extension
    pull_file "extensions/pi-mcp/package.json"  "${AGENT_DIR}/extensions/pi-mcp/package.json"
    pull_file "extensions/pi-mcp/cli.js"        "${AGENT_DIR}/extensions/pi-mcp/cli.js"
    pull_file "extensions/pi-mcp/pnpm-lock.yaml" "${AGENT_DIR}/extensions/pi-mcp/pnpm-lock.yaml"

    for f in app-bridge.bundle.js commands.ts config.ts consent-manager.ts direct-tools.ts \
             errors.ts glimpse-ui.ts host-html-template.ts index.ts init.ts lifecycle.ts \
             logger.ts mcp-auth.ts mcp-oauth-callback.ts mcp-oauth-provider.ts mcp-panel.ts \
             metadata-cache.ts npx-resolver.ts proxy-modes.ts resource-tools.ts server-manager.ts \
             state.ts tool-metadata.ts tool-registrar.ts types.ts ui-resource-handler.ts \
             ui-server.ts ui-session.ts ui-stream-types.ts utils.ts; do
        pull_file "extensions/pi-mcp/src/${f}" "${AGENT_DIR}/extensions/pi-mcp/src/${f}"
    done

    ok "All files downloaded."
}

# ---------------------------------------------------------------------------
# 4. Optional setup steps
# ---------------------------------------------------------------------------
setup_api_keys() {
    echo
    echo -e "${BOLD}--- Optional API Key / Service Setup ---${RESET}"

    local env_file="${AGENT_DIR}/.env"
    : > "$env_file"

    if prompt_yn "Set up Firecrawl API key? (used by firecrawl-search extension)" "n"; then
        read -rsp "  Firecrawl API key: " key
        echo
        echo "FIRECRAWL_API_KEY=${key}" >> "$env_file"
        ok "Firecrawl key saved."
    fi

    if prompt_yn "Set up Context7 MCP API key? (documentation lookup)" "n"; then
        read -rsp "  Context7 API key: " key
        echo
        # Write mcp.json
        cat > "${AGENT_DIR}/mcp.json" <<EOF
{
  "mcpServers": {
    "context7": {
      "type": "http",
      "url": "https://mcp.context7.com/mcp",
      "headers": {
        "CONTEXT7_API_KEY": "${key}"
      },
      "directTools": true
    }
  }
}
EOF
        ok "Context7 MCP configured."
    fi

    if prompt_yn "Set up OpenCode-Go API key? (default provider in this setup)" "n"; then
        read -rsp "  OpenCode-Go API key: " key
        echo
        # Write to auth.json
        cat > "${AGENT_DIR}/auth.json" <<EOF
{
  "opencode-go": {
    "type": "api_key",
    "key": "${key}"
  }
}
EOF
        ok "OpenCode-Go key saved to auth.json."
    fi
}

post_install() {
    echo
    echo -e "${BOLD}--- Post-Install Options ---${RESET}"

    if prompt_yn "Install recommended Pi packages now? (@dreki-gg/pi-questionnaire, @tintinweb/pi-subagents, @dreki-gg/pi-plan-mode)" "n"; then
        info "Installing packages..."
        pi package install @dreki-gg/pi-questionnaire || warn "Failed to install pi-questionnaire"
        pi package install @tintinweb/pi-subagents || warn "Failed to install pi-subagents"
        pi package install @dreki-gg/pi-plan-mode || warn "Failed to install pi-plan-mode"
        ok "Packages installed."
    fi

    if prompt_yn "Install extension dependencies with Bun now?" "n"; then
        if ensure_bun; then
            if [[ -f "${AGENT_DIR}/package.json" ]]; then
                (cd "$AGENT_DIR" && bun install) || warn "bun install failed in agent dir"
            fi
            if [[ -f "${AGENT_DIR}/extensions/pi-mcp/package.json" ]]; then
                (cd "${AGENT_DIR}/extensions/pi-mcp" && bun install) || warn "bun install failed in pi-mcp dir"
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
