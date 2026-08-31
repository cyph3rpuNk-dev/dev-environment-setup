#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# bootstrap-wsl.sh : dev environment for razer-control-secureblue
# Target: Fedora inside WSL2 (WSLg). Safe to run more than once.
#
#   bash bootstrap-wsl.sh              # do everything
#   bash bootstrap-wsl.sh --no-dnf     # skip system packages (no sudo needed)
#   bash bootstrap-wsl.sh --check      # report what's installed, change nothing
#   bash bootstrap-wsl.sh --doctor     # check WSL, agents, credentials, and extensions
#
# It never deletes anything and never touches your repositories.
# ---------------------------------------------------------------------------
set -u

CHECK_ONLY=0
SKIP_DNF=0
DOCTOR=0
for arg in "$@"; do
  case "$arg" in
    --check)   CHECK_ONLY=1 ;;
    --doctor)  CHECK_ONLY=1; DOCTOR=1 ;;
    --no-dnf)  SKIP_DNF=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg"; exit 1 ;;
  esac
done

FAIL=0
say()  { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
ok()   { printf '  \033[32mok\033[0m    %s\n' "$1"; }
skip() { printf '  \033[90mskip\033[0m  %s\n' "$1"; }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$1"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL + 1)); }
have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
say "1. System packages (dnf)"
# gtk4/libadwaita: the desktop crate.  dbus: the ksni tray.  systemd-devel:
# libudev, needed by hidapi when you build --features hidraw-backend.
# jq: required by the Claude Code hooks.  ImageMagick + xdotool: the
# run-desktop-ui skill's screenshot/drive steps. curl downloads the official
# rustup installer on a first run.
PKGS="gcc pkg-config gtk4-devel libadwaita-devel dbus-devel systemd-devel jq ImageMagick xdotool curl git gh"

if [ "$CHECK_ONLY" = 1 ] || [ "$SKIP_DNF" = 1 ]; then
  skip "not installing system packages"
  for p in $PKGS; do
    rpm -q "$p" >/dev/null 2>&1 && ok "$p" || warn "$p is missing"
  done
elif ! have dnf; then
  bad "dnf not found. This script expects a Fedora WSL distro."
else
  MISSING=""
  for p in $PKGS; do rpm -q "$p" >/dev/null 2>&1 || MISSING="$MISSING $p"; done
  if [ -z "$MISSING" ]; then
    ok "all system packages already present"
  else
    echo "  installing:$MISSING"
    echo "  (you will be asked for your sudo password)"
    if sudo dnf install -y $MISSING; then ok "system packages installed"
    else bad "dnf install failed; rerun with --no-dnf to continue without them"; fi
  fi
fi

# ---------------------------------------------------------------------------
say "2. Rust toolchain"
if have rustup; then
  ok "rustup $(rustup --version 2>/dev/null | head -1)"
elif [ "$CHECK_ONLY" = 1 ]; then
  warn "rustup not installed"
else
  echo "  installing rustup from https://rustup.rs ..."
  if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path; then
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
    ok "rustup installed"
  else
    bad "rustup install failed"
  fi
fi

# Make sure this shell can see cargo even on a first run.
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

if have rustup && [ "$CHECK_ONLY" = 0 ]; then
  rustup component add rustfmt clippy >/dev/null 2>&1 && ok "rustfmt + clippy" \
    || warn "could not add rustfmt/clippy (may already be present)"
fi
have rustc && ok "$(rustc --version)" || bad "rustc not on PATH (open a new shell and rerun)"

# razer-control-secureblue is edition 2024, which needs Rust 1.85 or newer.
if have rustc; then
  RV=$(rustc --version | awk '{print $2}' | cut -d- -f1)
  RMAJ=$(echo "$RV" | cut -d. -f1); RMIN=$(echo "$RV" | cut -d. -f2)
  if [ "$RMAJ" -gt 1 ] || { [ "$RMAJ" -eq 1 ] && [ "$RMIN" -ge 85 ]; }; then
    ok "rust $RV supports edition 2024"
  else
    bad "rust $RV is too old for edition 2024 (need 1.85+). Run: rustup update stable"
  fi
fi

# ---------------------------------------------------------------------------
say "3. Cargo tools"
# cargo-binstall downloads prebuilt binaries instead of compiling each tool
# from source, which turns ~20 minutes into ~1.
install_tool() {
  bin="$1"; crate="$2"; why="$3"
  if have "$bin"; then ok "$bin already installed ($why)"; return; fi
  if [ "$CHECK_ONLY" = 1 ]; then warn "$bin is missing ($why)"; return; fi
  if have cargo-binstall; then
    cargo binstall -y --no-confirm "$crate" >/dev/null 2>&1 && { ok "$bin installed ($why)"; return; }
    warn "binstall failed for $crate, falling back to source build"
  fi
  echo "  building $crate from source, this can take a few minutes ..."
  cargo install --locked "$crate" >/dev/null 2>&1 && ok "$bin installed ($why)" \
    || bad "could not install $crate"
}

if have cargo; then
  if ! have cargo-binstall && [ "$CHECK_ONLY" = 0 ]; then
    echo "  installing cargo-binstall (makes everything below much faster) ..."
    cargo install cargo-binstall --locked >/dev/null 2>&1 && ok "cargo-binstall" \
      || warn "cargo-binstall unavailable; tools will build from source"
  fi
  install_tool cargo-nextest cargo-nextest "better test runner"
  install_tool cargo-audit   cargo-audit   "RUSTSEC advisories, used by check.sh"
  install_tool cargo-machete cargo-machete "unused deps, used by check.sh"
  install_tool cargo-deny    cargo-deny    "licence policy (GPL-2.0-only)"
  install_tool bacon         bacon         "background clippy while an agent edits"
  install_tool typos         typos-cli     "typo check for the docs"
else
  bad "cargo not available; skipping cargo tools"
fi

# ---------------------------------------------------------------------------
say "4. VS Code extensions (WSL side)"
EXTS="rust-lang.rust-analyzer vadimcn.vscode-lldb tamasfe.even-better-toml \
fill-labs.dependi usernamehw.errorlens timonwong.shellcheck ms-vscode.hexeditor \
github.vscode-github-actions github.vscode-pull-request-github redhat.vscode-yaml \
eamodio.gitlens gruntfuggly.todo-tree streetsidesoftware.code-spell-checker \
bierner.markdown-mermaid"

if ! have code; then
  warn "'code' is not on PATH."
  warn "Open this folder in VS Code with the WSL extension, then run this script"
  warn "again from that window's integrated terminal so extensions land in WSL."
else
  for e in $EXTS; do
    if code --list-extensions 2>/dev/null | grep -qix "$e"; then
      ok "$e"
    elif [ "$CHECK_ONLY" = 1 ]; then
      warn "$e is missing"
    else
      code --install-extension "$e" --force >/dev/null 2>&1 && ok "$e installed" \
        || warn "could not install $e (check the name in the Extensions view)"
    fi
  done
fi

# ---------------------------------------------------------------------------
say "5. Agent CLIs"
have claude && ok "claude $(claude --version 2>/dev/null | head -1)" \
  || warn "claude CLI not found. Install it, then run 'claude' once to sign in."
have codex  && ok "codex $(codex --version 2>/dev/null | head -1)" \
  || warn "codex CLI not found. Install it, then run 'codex' once to sign in."

# Codex defaults. Written only if the file is absent.
if [ "$CHECK_ONLY" = 0 ] && [ ! -f "$HOME/.codex/config.toml" ]; then
  mkdir -p "$HOME/.codex"
  cat > "$HOME/.codex/config.toml" <<'TOML'
# Codex owns whole tasks here, same as Claude Code, so it can write.
# approval_policy = "on-request" keeps commands asking before they run;
# that is the brake, not a read-only sandbox.
model_reasoning_effort = "high"
approval_policy = "on-request"
sandbox_mode = "workspace-write"

# For a deliberate second-opinion pass, put read-only settings in
# ~/.codex/review.config.toml and run Codex with that profile instead.

[mcp_servers.context7]
url = "https://mcp.context7.com/mcp"
TOML
  ok "wrote ~/.codex/config.toml"
elif [ -f "$HOME/.codex/config.toml" ]; then
  skip "~/.codex/config.toml already exists, left alone"
fi

# ---------------------------------------------------------------------------
say "6. GitHub credentials and browser sign-in"
# WSL ships no browser. Without one, "gh auth login --web" and every other
# browser-based flow exits with little or no explanation, which reads as a hang.
# Fedora has no wslu package, so install a minimal shim that hands URLs to the
# Windows default browser.
PS_EXE="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
if [ -x /usr/local/bin/wslview ]; then
  ok "browser bridge present (/usr/local/bin/wslview)"
elif [ "$CHECK_ONLY" = 1 ]; then
  warn "no browser bridge; browser sign-in flows will fail with no useful error"
elif [ ! -x "$PS_EXE" ]; then
  warn "powershell.exe not reachable from WSL; cannot install the browser bridge"
else
  sudo tee /usr/local/bin/wslview >/dev/null <<'SHIM'
#!/usr/bin/env bash
# Hand a URL to the Windows default browser. WSL has no browser of its own.
set -euo pipefail
if [ $# -lt 1 ]; then
  echo "usage: wslview <url>" >&2
  exit 2
fi
exec /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe \
     -NoProfile -NonInteractive -Command "Start-Process '$1'" >/dev/null 2>&1
SHIM
  sudo chmod 0755 /usr/local/bin/wslview
  sudo ln -sf /usr/local/bin/wslview /usr/local/bin/xdg-open
  printf 'export BROWSER=/usr/local/bin/wslview\n' | sudo tee /etc/profile.d/wsl-browser.sh >/dev/null
  sudo chmod 0644 /etc/profile.d/wsl-browser.sh
  ok "browser bridge installed (open a new shell so BROWSER is exported)"
fi

# A PAT must never be written to ~/.bashrc. This script checks GitHub CLI
# authentication but never reads the token. Codex receives it only from the
# companion launcher. Claude's PAT-backed GitHub MCP is an explicit manual choice
# because it stores an authorization header in Claude's user-scoped MCP config.
GITHUB_AUTHENTICATED=0
if have gh && gh auth status --hostname github.com --active >/dev/null 2>&1; then
  GITHUB_AUTHENTICATED=1
  ok "GitHub CLI is authenticated"
elif have gh; then
  if [ "$CHECK_ONLY" = 1 ]; then
    warn "GitHub CLI is not authenticated"
  else
    warn "Run: gh auth login --hostname github.com --git-protocol https --web, then rerun this script"
  fi
else
  warn "GitHub CLI is missing; GitHub access and the optional MCP helper are unavailable"
fi

if [ "$GITHUB_AUTHENTICATED" = 1 ]; then
  # Without a credential helper, "git push" over HTTPS blocks on a username prompt
  # that never renders. It looks like a network hang and is not one.
  if git config --get-regexp 'credential\.https://github\.com\.helper' >/dev/null 2>&1; then
    ok "git credential helper configured for github.com"
  elif [ "$CHECK_ONLY" = 1 ]; then
    warn "no git credential helper; git push will stall on a hidden prompt"
  elif gh auth setup-git --hostname github.com >/dev/null 2>&1; then
    ok "git credential helper configured via gh"
  else
    warn "gh auth setup-git failed; git push over HTTPS will stall"
  fi

  # Pushing a repository containing .github/workflows requires the "workflow" scope,
  # which a default login does not request. The remote rejects the push with a
  # message naming the scope rather than the fix.
  if gh auth status --hostname github.com 2>&1 | grep -q "workflow"; then
    ok "token has the workflow scope"
  else
    warn "token lacks the 'workflow' scope; pushing .github/workflows will be rejected"
    warn "  fix: gh auth refresh --hostname github.com --scopes workflow"
  fi
fi

if grep -q 'GITHUB_MCP_PAT' "$HOME/.bashrc" 2>/dev/null; then
  warn "Legacy GITHUB_MCP_PAT entry detected in ~/.bashrc. Remove it after GitHub CLI authentication is working."
fi

# ---------------------------------------------------------------------------
say "7. MCP servers"

# --- Claude Code -----------------------------------------------------------
if ! have claude; then
  skip "claude CLI not installed"
elif [ "$CHECK_ONLY" = 1 ]; then
  skip "not adding MCP servers"
else
  if claude mcp list 2>/dev/null | grep -q context7; then
    ok "claude: context7 already configured"
  else
    claude mcp add --transport http --scope user context7 https://mcp.context7.com/mcp \
      >/dev/null 2>&1 && ok "claude: context7 added" || warn "claude: could not add context7"
  fi

  if claude mcp list 2>/dev/null | grep -q github; then
    ok "claude: github already configured"
  else
    skip "claude: github is optional and is not configured automatically; see START-HERE.md"
  fi
fi

# --- Codex -----------------------------------------------------------------
# context7 is written with the initial config above. The GitHub table contains no
# credential, so it is appended after GitHub CLI authentication proves the helper
# can obtain one when Codex starts.
CODEX_CFG="$HOME/.codex/config.toml"
if [ "$CHECK_ONLY" = 1 ]; then
  skip "not editing $CODEX_CFG"
elif [ ! -f "$CODEX_CFG" ]; then
  skip "no ~/.codex/config.toml yet"
elif grep -q '\[mcp_servers.github\]' "$CODEX_CFG"; then
  ok "codex: github already in config.toml"
elif [ "$GITHUB_AUTHENTICATED" = 1 ]; then
  cat >> "$CODEX_CFG" <<'TOML'

[mcp_servers.github]
url = "https://api.githubcopilot.com/mcp/"
# Read from the process environment. Launch with helpers/codex-with-github-mcp.sh.
bearer_token_env_var = "GITHUB_MCP_PAT"
TOML
  ok "codex: github added to config.toml"
else
  skip "codex: github needs an authenticated GitHub CLI session"
fi

# ---------------------------------------------------------------------------
say "8. Claude Code user settings"
# Global permissions must be project-agnostic. Repository settings, not this
# file, decide whether builds, tests, or project scripts can run unattended.
CC_SETTINGS="$HOME/.claude/settings.json"
if [ "$CHECK_ONLY" = 1 ]; then
  skip "not writing $CC_SETTINGS"
elif [ -f "$CC_SETTINGS" ]; then
  skip "$CC_SETTINGS already exists, left alone (see guide 5.3 for the block to merge)"
else
  mkdir -p "$HOME/.claude"
  cat > "$CC_SETTINGS" <<'JSON'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": [
      "Bash(cargo fmt *)",
      "Bash(cargo tree *)",
      "Bash(cargo metadata *)",
      "Bash(rustup show *)"
    ],
    "deny": [
      "Read(**/.env)",
      "Read(**/*.pfx)",
      "Read(**/*.p12)",
      "Read(~/.gnupg/**)",
      "Read(~/.ssh/**)"
    ]
  },
  "autoMemoryEnabled": true
}
JSON
  ok "wrote $CC_SETTINGS"
fi

# ---------------------------------------------------------------------------
if [ "$DOCTOR" = 1 ]; then
  say "9. Doctor: environment boundaries and usable configuration"
  if grep -qi microsoft /proc/version 2>/dev/null; then ok "WSL kernel detected"; else warn "WSL kernel not detected"; fi
  case "$PWD" in /mnt/*) warn "Current directory is on a mounted Windows filesystem; keep Linux builds under ~/src";; *) ok "Current directory is on the Linux filesystem";; esac
  if have rustup; then
    COMPONENTS=$(rustup component list --installed 2>/dev/null || true)
    case "$COMPONENTS" in *rustfmt*clippy*|*clippy*rustfmt*) ok "rustfmt and clippy installed";; *) warn "rustfmt or clippy missing";; esac
  fi
  if have code && code --list-extensions 2>/dev/null | grep -qix 'rust-lang.rust-analyzer'; then ok "WSL VS Code rust-analyzer installed"; else warn "WSL VS Code rust-analyzer not detected"; fi
  [ -f "$HOME/.codex/config.toml" ] && ok "Codex user configuration exists" || warn "Codex user configuration missing"
  [ -f "$HOME/.claude/settings.json" ] && ok "Claude user settings exist" || warn "Claude user settings missing"
  if have gh && gh auth status --hostname github.com --active >/dev/null 2>&1; then ok "GitHub CLI authentication works"; else warn "GitHub CLI authentication is unavailable"; fi
  echo "  Doctor does not verify VS Code profile names or agent sign-in state; see doctor/README.md."
fi

# ---------------------------------------------------------------------------
say "Summary"
if [ "$FAIL" -eq 0 ]; then
  echo "  No failures."
else
  echo "  $FAIL problem(s) above need attention."
fi
cat <<'NEXT'

  Still to do by hand (these cannot be scripted):
    1. Run 'claude' and 'codex' once each and sign in.
    2. Add plugins or skills only when a real project workflow requires them.
       They are optional and expand the tools an agent can use.
    3. In VS Code settings (user scope, not workspace):
         Claude Code > Initial Permission Mode  ->  plan
         Claude Code > Preferred Location       ->  sidebar
    4. Create the four Rust and General profiles from profiles/, then adjust only
       personal preferences. Keep exported profiles in a private backup.
    5. Clone razer-control-secureblue into ~/src (NOT under /mnt/c).
    6. Authenticate GitHub CLI when you need GitHub access:
         gh auth login --hostname github.com --git-protocol https --web
       Then launch Codex with helpers/codex-with-github-mcp.sh. The helper
       exposes the token only to that Codex process.
       Claude's PAT-backed GitHub MCP is not configured automatically.
    7. Follow START-HERE.md for the two existing repositories or NEW-PROJECT.md
       for a new project.

NEXT
exit "$FAIL"
