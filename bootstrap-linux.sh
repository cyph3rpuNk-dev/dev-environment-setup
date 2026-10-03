#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# bootstrap-linux.sh : project-neutral Linux and macOS development tools
# Runs on native Linux, inside WSL and on macOS. Supports Fedora/RHEL (dnf),
# Debian/Ubuntu (apt) and macOS (Homebrew). Safe to run more than once.
#
#   bash bootstrap-linux.sh                    # base tools and general extensions
#   bash bootstrap-linux.sh --check            # report only, change nothing
#   bash bootstrap-linux.sh --doctor           # check plus environment diagnostics
#   bash bootstrap-linux.sh --stack=rust,python  # add optional stacks
#   bash bootstrap-linux.sh --configure-agents # create missing agent defaults and MCP config
#   bash bootstrap-linux.sh --no-sudo          # install no packages; report missing ones
#   bash bootstrap-linux.sh --install-browser-bridge
#                                              # WSL only: open sign-in URLs in Windows
#
# It removes only its staged installer downloads; project repositories are untouched.
# ---------------------------------------------------------------------------
set -uo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd) || exit 1

usage() { sed -n '3,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

CHECK_ONLY=0
NO_SUDO=0
DOCTOR=0
INSTALL_BROWSER_BRIDGE=0
CONFIGURE_AGENTS=0
WANT_RUST=0
WANT_PYTHON=0
add_stacks() {
  local list="$1" s
  # An empty list would be an empty array, which Bash 3.2 (macOS) rejects under set -u.
  [ -n "$list" ] || { echo "empty --stack= (choose base, rust, python)" >&2; exit 1; }
  IFS=',' read -r -a _stacks <<< "$list"
  for s in "${_stacks[@]}"; do
    case "$s" in
      base) ;;
      rust) WANT_RUST=1 ;;
      python) WANT_PYTHON=1 ;;
      *) echo "unknown stack: $s (choose base, rust, python)" >&2; exit 1 ;;
    esac
  done
}
for arg in "$@"; do
  case "$arg" in
    --stack=*) add_stacks "${arg#--stack=}" ;;
    --configure-agents) CONFIGURE_AGENTS=1 ;;
    --check)   CHECK_ONLY=1 ;;
    --doctor)  CHECK_ONLY=1; DOCTOR=1 ;;
    --no-sudo|--no-dnf) NO_SUDO=1 ;;   # --no-dnf is the pre-Linux-support name
    --install-browser-bridge) INSTALL_BROWSER_BRIDGE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $arg" >&2; usage >&2; exit 1 ;;
  esac
done

# Platform detection reads files only. The overrides exist for the offline tests.
KERNEL=${DEVSETUP_KERNEL:-$(uname -s 2>/dev/null)}
PROC_VERSION=${DEVSETUP_PROC_VERSION:-/proc/version}
OS_RELEASE=${DEVSETUP_OS_RELEASE:-/etc/os-release}
IS_WSL=0
IS_MACOS=0
os_field() { sed -n "s/^$1=//p" "$OS_RELEASE" 2>/dev/null | head -n 1 | tr -d "\"'"; }
DISTRO_ID=""
if [ "$KERNEL" = Darwin ]; then
  IS_MACOS=1
  PKG_MGR=brew
  DISTRO_NAME="macOS $(sw_vers -productVersion 2>/dev/null)"
else
  if grep -qi microsoft "$PROC_VERSION" 2>/dev/null; then IS_WSL=1; fi
  DISTRO_ID=$(os_field ID)
  DISTRO_LIKE=$(os_field ID_LIKE)
  DISTRO_NAME=$(os_field PRETTY_NAME)
  case " $DISTRO_ID $DISTRO_LIKE " in
    *" fedora "*|*" rhel "*|*" centos "*) PKG_MGR=dnf ;;
    *" debian "*|*" ubuntu "*) PKG_MGR=apt ;;
    *) PKG_MGR=none ;;
  esac
fi

if [ "$INSTALL_BROWSER_BRIDGE" = 1 ] && [ "$IS_WSL" = 0 ]; then
  echo '--install-browser-bridge is only for WSL; native Linux and macOS already have a browser.' >&2
  exit 2
fi
if [ "$NO_SUDO" = 1 ] && [ "$INSTALL_BROWSER_BRIDGE" = 1 ]; then
  echo '--no-sudo cannot be combined with --install-browser-bridge (requires sudo).' >&2
  exit 2
fi

FAIL=0
say()  { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
ok()   { printf '  \033[32mok\033[0m    %s\n' "$1"; }
skip() { printf '  \033[90mskip\033[0m  %s\n' "$1"; }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$1"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL + 1)); }
have() { command -v "$1" >/dev/null 2>&1; }
# Put an installer's bin directory on PATH for this run. The installers' own env
# scripts are not sourced: that would run shell code, even in check mode.
add_path_dir() {
  case ":$PATH:" in *":$1:"*) ;; *) if [ -d "$1" ]; then PATH="$1:$PATH"; fi ;; esac
}

# Download an installer to a private temporary file and run it only if the
# download completed. A partial script is never executed.
run_downloaded_installer() {
  local url="$1" installer; shift
  installer=$(mktemp) || return 1
  if curl --proto '=https' --tlsv1.2 -LsSf "$url" -o "$installer" && sh "$installer" "$@"; then
    rm -f -- "$installer"; return 0
  fi
  rm -f -- "$installer"; return 1
}

# On Apple silicon Homebrew lives in /opt/homebrew, which a new shell only finds
# after its profile is set up. Use it for this run and say how to make it permanent.
if [ "$IS_MACOS" = 1 ] && ! have brew; then
  for candidate in ${DEVSETUP_BREW_CANDIDATES:-/opt/homebrew/bin/brew /usr/local/bin/brew}; do
    if [ -x "$candidate" ]; then
      add_path_dir "${candidate%/*}"
      BREW_NOT_ON_PATH="$candidate"
      break
    fi
  done
fi
BREW_INSTALL='/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'

# ---------------------------------------------------------------------------
say "0. Environment"
if [ "$IS_MACOS" = 1 ]; then ok "$DISTRO_NAME"
elif [ "$IS_WSL" = 1 ]; then ok "WSL detected${DISTRO_NAME:+ ($DISTRO_NAME)}"
else ok "native Linux${DISTRO_NAME:+ ($DISTRO_NAME)}"; fi
if [ "$IS_MACOS" = 1 ]; then
  if ! have brew; then
    bad "Homebrew is required on macOS. Install it with the official command, then rerun:"
    echo "        $BREW_INSTALL"
    PKG_MGR=none
  else
    ok "package manager: brew"
    if [ -n "${BREW_NOT_ON_PATH:-}" ]; then
      warn "Homebrew is installed but not on PATH in new terminals. Add it with:"
      warn "  echo 'eval \"\$($BREW_NOT_ON_PATH shellenv)\"' >> ~/.zprofile"
    fi
  fi
else
  PKG_COMMAND=$PKG_MGR
  [ "$PKG_MGR" != apt ] || PKG_COMMAND=apt-get
  if [ "$PKG_MGR" != none ] && ! have "$PKG_COMMAND"; then
    warn "$PKG_MGR is unavailable; install packages manually on this distribution"
    PKG_MGR=none
  fi
  case "$PKG_MGR" in
    none) warn "unsupported distribution '${DISTRO_ID:-unknown}': packages are checked by command name only; install them yourself" ;;
    *) ok "package manager: $PKG_MGR" ;;
  esac
fi

# ---------------------------------------------------------------------------
say "1. System packages"
if [ "$IS_MACOS" = 1 ]; then
  # macOS ships curl. The C compiler comes from Apple's Command Line Tools.
  PKGS="git gh"
  if [ "$WANT_RUST" = 1 ]; then PKGS="$PKGS pkgconf"; fi
else
  PKGS="curl git gh"
  if [ "$WANT_RUST" = 1 ]; then
    if [ "$PKG_MGR" = apt ]; then PKGS="$PKGS build-essential pkg-config"; else PKGS="$PKGS gcc pkg-config"; fi
  fi
fi

pkg_installed() {
  case "$PKG_MGR" in
    dnf) rpm -q "$1" >/dev/null 2>&1 ;;
    apt) dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed' ;;
    brew) brew list --formula "$1" >/dev/null 2>&1 ;;
    *) case "$1" in build-essential) have gcc ;; pkgconf) have pkg-config ;; *) have "$1" ;; esac ;;
  esac
}

MISSING=""
for p in $PKGS; do
  if pkg_installed "$p"; then ok "$p"; else MISSING="$MISSING $p"; fi
done
if [ -z "$MISSING" ]; then
  :
elif [ "$CHECK_ONLY" = 1 ] || [ "$NO_SUDO" = 1 ]; then
  for p in $MISSING; do bad "$p is missing"; done
elif [ "$PKG_MGR" = none ]; then
  bad "missing:$MISSING. Install them with your package manager, then rerun."
else
  echo "  installing:$MISSING"
  [ "$PKG_MGR" = brew ] || echo "  (you will be asked for your sudo password)"
  install_packages() {
    # MISSING is a space-separated list of package names.
    # shellcheck disable=SC2086
    case "$PKG_MGR" in
      dnf)
        # gh may require an extra repository. Do not let it block base tools.
        local base_missing="" need_gh=0 install_failed=0 package
        for package in $MISSING; do
          if [ "$package" = gh ]; then need_gh=1; else base_missing="$base_missing $package"; fi
        done
        if [ -n "$base_missing" ]; then sudo dnf install -y $base_missing || install_failed=1; fi
        if [ "$need_gh" = 1 ] && ! sudo dnf install -y gh; then
          warn "GitHub CLI may need its official RPM repository: https://github.com/cli/cli/blob/trunk/docs/install_linux.md"
          install_failed=1
        fi
        return "$install_failed" ;;
      apt) sudo apt-get update && sudo apt-get install -y $MISSING ;;
      brew) brew install $MISSING ;;   # Homebrew never needs sudo
    esac
  }
  if install_packages; then ok "system packages installed"
  else
    bad "package installation failed; read the package manager's error above"
    warn "  if another update holds a lock (common just after first start), wait for it to"
    warn "  finish, then rerun; never delete lock files. --no-sudo skips these packages."
  fi
fi

# Probe the supported option rather than assuming a particular release boundary.
GH_ACTIVE=1
if have gh && ! gh auth status --help 2>/dev/null | grep -q -- '--active'; then
  GH_ACTIVE=0
  warn "GitHub CLI lacks --active; for a current build see https://github.com/cli/cli/blob/trunk/docs/install_linux.md"
fi
gh_authenticated() {
  if [ "$GH_ACTIVE" = 1 ]; then gh auth status --hostname github.com --active >/dev/null 2>&1
  else gh auth status --hostname github.com >/dev/null 2>&1; fi
}

# ---------------------------------------------------------------------------
if [ "$WANT_RUST" = 1 ]; then
say "2. Rust toolchain"
if [ "$IS_MACOS" = 1 ]; then
  # Rust links with Apple's toolchain. Installing it opens a system dialog, so it
  # stays a manual step, like the Visual Studio workload on Windows.
  if xcode-select -p >/dev/null 2>&1; then ok "Xcode Command Line Tools installed (linker)"
  else bad "Xcode Command Line Tools missing; Rust cannot link. Run: xcode-select --install"; fi
fi
if have rustup; then
  ok "rustup $(rustup --version 2>/dev/null | head -1)"
elif [ "$CHECK_ONLY" = 1 ]; then
  bad "rustup not installed"
else
  echo "  installing rustup from https://rustup.rs ..."
  # rustup adds ~/.cargo/bin to the shell profile so new terminals find cargo.
  if run_downloaded_installer https://sh.rustup.rs -y; then
    add_path_dir "$HOME/.cargo/bin"
    have rustup && ok "rustup installed (open a new terminal to use it)" \
      || bad "rustup installer completed but rustup is unavailable"
  else
    bad "rustup install failed"
  fi
fi

# Make sure this shell can see cargo even on a first run.
add_path_dir "$HOME/.cargo/bin"

if have rustup && [ "$CHECK_ONLY" = 0 ]; then
  rustup component add rustfmt clippy && ok "rustfmt + clippy" \
    || bad "could not add rustfmt/clippy"
fi
have rustc && ok "$(rustc --version)" || bad "rustc not on PATH (open a new terminal and rerun)"

# Toolchain version requirements belong to each project.
say "3. Cargo tools"
# cargo-binstall downloads prebuilt binaries instead of compiling each tool
# from source, which turns ~20 minutes into ~1.
install_tool() {
  bin="$1"; crate="$2"; why="$3"
  if have "$bin"; then ok "$bin already installed ($why)"; return; fi
  if [ "$CHECK_ONLY" = 1 ]; then warn "$bin is missing ($why)"; return; fi
  if have cargo-binstall; then
    cargo binstall -y --no-confirm "$crate" && { ok "$bin installed ($why)"; return; }
    warn "binstall failed for $crate, falling back to source build"
  fi
  echo "  building $crate from source, this can take a few minutes ..."
  cargo install --locked "$crate" && ok "$bin installed ($why)" \
    || bad "could not install $crate"
}

if have cargo; then
  if ! have cargo-binstall && [ "$CHECK_ONLY" = 0 ]; then
    echo "  installing cargo-binstall (makes everything below much faster) ..."
    cargo install cargo-binstall --locked && ok "cargo-binstall" \
      || warn "cargo-binstall unavailable; tools will build from source"
  fi
  install_tool cargo-nextest cargo-nextest "better test runner"
  install_tool cargo-audit   cargo-audit   "RUSTSEC advisories"
  install_tool cargo-machete cargo-machete "unused dependencies"
  install_tool cargo-deny    cargo-deny    "dependency policy"
  install_tool bacon         bacon         "background clippy while an agent edits"
  install_tool typos         typos-cli     "typo check for the docs"
else
  bad "cargo not available; skipping cargo tools"
fi
fi # Optional Rust stack

# ---------------------------------------------------------------------------
if [ "$WANT_PYTHON" = 1 ]; then
say "2p. Python (uv)"
# uv manages Python versions, virtual environments, dependencies and uv.lock per
# project, so no system Python packages are installed here.
if have uv; then
  ok "$(uv --version 2>/dev/null | head -1)"
elif [ "$CHECK_ONLY" = 1 ]; then
  warn "uv not installed"
else
  echo "  installing uv from https://astral.sh/uv ..."
  # The uv installer writes ~/.local/bin and adds it to the shell profile.
  if run_downloaded_installer https://astral.sh/uv/install.sh; then
    add_path_dir "$HOME/.local/bin"
    have uv && ok "uv installed (open a new terminal to use it)" \
      || bad "uv installer completed but uv is unavailable"
  else
    bad "uv install failed"
  fi
fi
fi # Optional Python stack

# ---------------------------------------------------------------------------
say "4. VS Code extensions"
EXTS="timonwong.shellcheck ms-vscode.hexeditor usernamehw.errorlens github.vscode-github-actions github.vscode-pull-request-github redhat.vscode-yaml eamodio.gitlens gruntfuggly.todo-tree streetsidesoftware.code-spell-checker bierner.markdown-mermaid"
if [ "$WANT_RUST" = 1 ]; then
  EXTS="$EXTS rust-lang.rust-analyzer vadimcn.vscode-lldb tamasfe.even-better-toml fill-labs.dependi"
fi
if [ "$WANT_PYTHON" = 1 ]; then
  EXTS="$EXTS ms-python.python charliermarsh.ruff"
fi

if ! have code && [ "$IS_MACOS" = 1 ] && [ "$PKG_MGR" = brew ]; then
  if [ "$CHECK_ONLY" = 1 ] || [ "$NO_SUDO" = 1 ]; then
    warn "VS Code is missing. Install with: brew install --cask visual-studio-code"
  elif brew install --cask visual-studio-code && have code; then
    ok "VS Code installed"
  else
    bad "VS Code installation failed; install it from https://code.visualstudio.com and rerun"
  fi
fi
if ! have code; then
  if [ "$IS_MACOS" = 1 ]; then
    warn "'code' is not on PATH. Open VS Code, run 'Shell Command: Install code command in PATH',"
    warn "then rerun to install the editor extensions."
  elif [ "$IS_WSL" = 1 ]; then
    warn "'code' is not on PATH. Open this folder from Windows VS Code with the WSL"
    warn "extension, then rerun from that window's terminal so extensions land in WSL."
  else
    warn "'code' is not on PATH. Install VS Code (https://code.visualstudio.com/docs/setup/linux),"
    warn "then rerun to install the editor extensions."
  fi
else
  if INSTALLED_EXTS=$(code --list-extensions 2>/dev/null); then
  for e in $EXTS; do
    if printf '%s\n' "$INSTALLED_EXTS" | grep -Fqix "$e"; then
      ok "$e"
    elif [ "$CHECK_ONLY" = 1 ]; then
      warn "$e is missing"
    else
      code --install-extension "$e" --force && ok "$e installed" \
        || bad "could not install $e (check the name in the Extensions view)"
    fi
  done
  else
    bad "could not list VS Code extensions; skipping extension installation"
  fi
fi

# ---------------------------------------------------------------------------
if [ "$CONFIGURE_AGENTS" = 1 ]; then
say "5. Agent CLIs"
have claude && ok "claude $(claude --version 2>/dev/null | head -1)" \
  || warn "claude CLI not found. Install it (see START-HERE.md), then run 'claude' once to sign in."
have codex  && ok "codex $(codex --version 2>/dev/null | head -1)" \
  || warn "codex CLI not found. Install it (see START-HERE.md), then run 'codex' once to sign in."

# Codex defaults. Written only if the file is absent.
CODEX_CREATED=0
if [ "$CHECK_ONLY" = 0 ] && [ ! -f "$HOME/.codex/config.toml" ]; then
  if mkdir -p "$HOME/.codex" && cat > "$HOME/.codex/config.toml" <<'TOML'
# Codex owns whole tasks here, same as Claude Code, so it can write.
# Routine workspace commands can run without approval; on-request asks at
# permission boundaries. This is not per-command approval or a read-only sandbox.
model_reasoning_effort = "high"
approval_policy = "on-request"
sandbox_mode = "workspace-write"

# For a deliberate second-opinion pass, put read-only settings in
# ~/.codex/review.config.toml and run Codex with that profile instead.

[mcp_servers.context7]
url = "https://mcp.context7.com/mcp"
TOML
  then CODEX_CREATED=1; ok "wrote ~/.codex/config.toml"
  else bad "could not write ~/.codex/config.toml"; fi
elif [ -f "$HOME/.codex/config.toml" ]; then
  skip "$HOME/.codex/config.toml already exists, left alone"
fi
fi # Optional agent defaults

# ---------------------------------------------------------------------------
say "6. GitHub credentials and browser sign-in"
if [ "$IS_MACOS" = 1 ]; then
  skip "browser bridge is WSL-only; macOS opens sign-in pages in your default browser"
elif [ "$IS_WSL" = 0 ]; then
  skip "browser bridge is WSL-only; native Linux opens sign-in pages with xdg-open"
else
  # WSL has no browser of its own, so 'gh auth login --web' appears to hang
  # without the optional bridge that opens URLs in the Windows default browser.
  PS_EXE="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
  if [ "$CHECK_ONLY" = 1 ] || [ "$INSTALL_BROWSER_BRIDGE" = 0 ]; then
    if cmp -s "$SCRIPT_DIR/helpers/wslview.sh" /usr/local/bin/wslview && [ -x /usr/local/bin/wslview ]; then
      ok "current browser bridge present"
    else
      warn "browser bridge absent, legacy, or custom; use --install-browser-bridge to install/upgrade the toolkit bridge"
    fi
  elif [ ! -x "$PS_EXE" ]; then
    bad "powershell.exe not reachable from WSL; cannot install the browser bridge"
  else
    # shellcheck source=helpers/install-browser-bridge.sh
    . "$SCRIPT_DIR/helpers/install-browser-bridge.sh"
    if install_browser_bridge "$SCRIPT_DIR/helpers/wslview.sh" /usr/local/bin /etc/profile.d; then
      export BROWSER=/usr/local/bin/wslview
      ok "browser bridge installed and verified (new login shells also set BROWSER)"
    else bad "browser bridge installation failed; existing custom handlers are preserved"; fi
  fi
fi

# A PAT must never be written to ~/.bashrc. This script checks GitHub CLI
# authentication but never reads the token. Codex receives it only from the
# companion launcher. Claude's PAT-backed GitHub MCP is an explicit manual choice
# because it stores an authorization header in Claude's user-scoped MCP config.
GITHUB_AUTHENTICATED=0
if have gh && gh_authenticated; then
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
  GH_SCOPES=""
  if [ "$GH_ACTIVE" = 1 ] && GH_STATUS=$(gh auth status --hostname github.com --active 2>&1); then
    GH_SCOPES=$(printf '%s\n' "$GH_STATUS" | sed -n 's/^[[:space:]]*- Token scopes:[[:space:]]*//p')
  fi
  if [ -z "$GH_SCOPES" ]; then
    warn "workflow permission could not be determined (older CLI or token without classic scopes); check repository permissions before pushing workflows"
  elif printf '%s\n' "$GH_SCOPES" | tr -d "' " | tr ',' '\n' | grep -qx workflow; then
    ok "active token has the workflow scope"
  else
    warn "active classic token lacks the 'workflow' scope"
    warn "  fix: gh auth refresh --hostname github.com --scopes workflow"
  fi
fi

for profile in .bashrc .bash_profile .zshrc .zprofile .profile; do
  if grep -q 'GITHUB_MCP_PAT' "$HOME/$profile" 2>/dev/null; then
    warn "Legacy GITHUB_MCP_PAT entry detected in ~/$profile. Remove it after GitHub CLI authentication is working."
  fi
done

# ---------------------------------------------------------------------------
if [ "$CONFIGURE_AGENTS" = 1 ]; then
say "7. MCP servers"

# --- Claude Code -----------------------------------------------------------
if ! have claude; then
  skip "claude CLI not installed"
elif [ "$CHECK_ONLY" = 1 ]; then
  skip "not adding MCP servers"
else
  if claude mcp get context7 >/dev/null 2>&1; then
    ok "claude: context7 already configured"
  else
    claude mcp add --transport http --scope user context7 https://mcp.context7.com/mcp \
      && ok "claude: context7 added" || bad "claude: could not add context7"
  fi

  if claude mcp get github >/dev/null 2>&1; then
    ok "claude: github already configured"
  else
    skip "claude: github is optional and is not configured automatically; see docs/agents.md"
  fi
fi

# --- Codex -----------------------------------------------------------------
# context7 is written with the initial config above. The GitHub table contains no
# credential. Only append to the configuration created by this invocation;
# arbitrary existing TOML must be merged manually rather than guessed with regex.
CODEX_CFG="$HOME/.codex/config.toml"
if [ "$CHECK_ONLY" = 1 ]; then
  skip "not editing $CODEX_CFG"
elif [ ! -f "$CODEX_CFG" ]; then
  skip "no ~/.codex/config.toml yet"
elif [ "$CODEX_CREATED" = 0 ]; then
  skip "codex: existing config preserved; review GitHub MCP setup in docs/agents.md"
elif [ "$GITHUB_AUTHENTICATED" = 1 ]; then
  if cat >> "$CODEX_CFG" <<'TOML'

[mcp_servers.github]
url = "https://api.githubcopilot.com/mcp/"
# Read from the process environment. Launch with helpers/codex-with-github-mcp.sh.
bearer_token_env_var = "GITHUB_MCP_PAT"
TOML
  then ok "codex: github added to config.toml"
  else bad "could not append GitHub configuration"; fi
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
  skip "$CC_SETTINGS already exists, left alone (see docs/agents.md for the block to merge)"
else
  if mkdir -p "$HOME/.claude" && cat > "$CC_SETTINGS" <<'JSON'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": [],
    "deny": [
      "Read(**/.env)",
      "Read(**/.env.*)",
      "Read(**/*.pem)",
      "Read(**/*.key)",
      "Read(**/*.pfx)",
      "Read(**/*.p12)",
      "Read(~/.gnupg/**)",
      "Read(~/.ssh/**)"
    ]
  },
  "autoMemoryEnabled": true
}
JSON
  then ok "wrote $CC_SETTINGS"
  else bad "could not write $CC_SETTINGS"; fi
fi

# ---------------------------------------------------------------------------
fi # Optional agent configuration

if [ "$DOCTOR" = 1 ]; then
  say "9. Doctor: environment boundaries and usable configuration"
  if [ "$IS_WSL" = 1 ]; then
    ok "WSL kernel detected"
    # Linux projects under /mnt/c are slow and lose Linux permissions.
    if [ -d "$HOME/src" ]; then
      SRC_REAL=$(cd -- "$HOME/src" && pwd -P)
      case "$SRC_REAL" in
        /mnt/*) warn "$HOME/src resolves to $SRC_REAL on the Windows filesystem; keep Linux projects on the Linux filesystem" ;;
        *) ok "$HOME/src is on the Linux filesystem" ;;
      esac
    else
      skip "$HOME/src does not exist yet; keep Linux projects there, not under /mnt/c"
    fi
  elif [ "$IS_MACOS" = 1 ]; then
    ok "macOS detected ($(uname -m 2>/dev/null))"
    if xcode-select -p >/dev/null 2>&1; then ok "Xcode Command Line Tools installed"
    else warn "Xcode Command Line Tools missing; run: xcode-select --install"; fi
  else
    ok "native Linux kernel"
  fi
  if [ "$WANT_RUST" = 1 ] && have rustup; then
    COMPONENTS=$(rustup component list --installed 2>/dev/null || true)
    case "$COMPONENTS" in *rustfmt*clippy*|*clippy*rustfmt*) ok "rustfmt and clippy installed";; *) warn "rustfmt or clippy missing";; esac
  fi
  if [ "$WANT_RUST" = 1 ]; then
    if have code && code --list-extensions 2>/dev/null | grep -qix 'rust-lang.rust-analyzer'; then ok "VS Code rust-analyzer installed"; else warn "VS Code rust-analyzer not detected"; fi
  fi
  if [ "$WANT_PYTHON" = 1 ]; then
    if have uv; then ok "uv available"; else warn "uv not available"; fi
  fi
  if [ "$CONFIGURE_AGENTS" = 1 ]; then
    [ -f "$HOME/.codex/config.toml" ] && ok "Codex user configuration exists" || warn "Codex user configuration missing"
    [ -f "$HOME/.claude/settings.json" ] && ok "Claude user settings exist" || warn "Claude user settings missing"
  fi
  if have gh && gh_authenticated; then ok "GitHub CLI authentication works"; else warn "GitHub CLI authentication is unavailable"; fi
  # Commits need a name and email. Report only whether they are set, never the values.
  if have git; then
    GIT_NAME=$(git config --global --get user.name 2>/dev/null || true)
    GIT_EMAIL=$(git config --global --get user.email 2>/dev/null || true)
    if [ -z "$GIT_NAME" ] || [ -z "$GIT_EMAIL" ]; then
      warn "Git commit name or email is not set; set both with git config --global user.name / user.email"
    else
      case "$(printf '%s' "$GIT_EMAIL" | tr '[:upper:]' '[:lower:]')" in
        *@users.noreply.github.com) ok "Git commit name and email are set (GitHub private address)" ;;
        *) warn "Git commit email is not a GitHub private (noreply) address, so every pushed commit publishes it" ;;
      esac
    fi
  fi
  echo "  Doctor does not verify VS Code profile names or agent sign-in state; see doctor/README.md."
fi

# ---------------------------------------------------------------------------
say "Summary"
if [ "$FAIL" -eq 0 ]; then
  echo "  No required failures. Review warnings and manual checks below."
else
  echo "  $FAIL problem(s) above need attention."
fi
echo "Next: START-HERE.md for readiness; docs/stacks/ for stacks; new-project.sh to start a project."
exit "$FAIL"
