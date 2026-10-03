#!/usr/bin/env bash
# Source this file; installation happens only when the function is called.

# The exact legacy shim this repository once shipped; only it may be replaced.
# Printed with printf rather than a here-document inside a process substitution,
# which Bash 3.2 (macOS) parses differently.
legacy_browser_bridge() {
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    '# Hand a URL to the Windows default browser. WSL has no browser of its own.' \
    'set -euo pipefail' \
    'if [ $# -lt 1 ]; then' \
    '  echo "usage: wslview <url>" >&2' \
    '  exit 2' \
    'fi' \
    'exec /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe \' \
    "     -NoProfile -NonInteractive -Command \"Start-Process '\$1'\" >/dev/null 2>&1"
}

# SHA-256 of the v2 bridge (helpers/wslview.sh before v3); it may be upgraded too.
# tests/fixtures/wslview-v2.sh keeps its exact bytes.
PREVIOUS_BRIDGE_V2_SHA256=4fc721bf180d8e55dfd7389d9f673a20783e9e708ab7d990292810ff6b9faf0b

file_sha256() {
  local sum
  if command -v sha256sum >/dev/null 2>&1; then sum=$(sha256sum < "$1") || return 1
  else sum=$(shasum -a 256 < "$1") || return 1; fi
  printf '%s\n' "${sum%% *}"
}

# Succeed when the installed bridge is an earlier version this repository shipped.
previous_toolkit_bridge() {
  cmp -s "$1" <(legacy_browser_bridge) && return 0
  [ "$(file_sha256 "$1" 2>/dev/null)" = "$PREVIOUS_BRIDGE_V2_SHA256" ]
}

install_browser_bridge() {
  local source_file="$1" bin_dir="$2" profile_dir="$3"
  local bridge="$bin_dir/wslview" profile="$profile_dir/wsl-browser.sh"
  local profile_line="export BROWSER=$bin_dir/wslview"
  [ -f "$source_file" ] || { echo 'Browser bridge source missing.' >&2; return 1; }
  # Do not hide a distro/user handler found elsewhere on PATH.
  local existing_bridge
  existing_bridge=$(command -v wslview 2>/dev/null || true)
  if [ -n "$existing_bridge" ] && [ "$existing_bridge" != "$bridge" ]; then
    echo "Preserving existing browser bridge on PATH: $existing_bridge" >&2; return 1
  fi
  # Replace only exact earlier versions shipped by this repository.
  if [ -L "$bridge" ]; then
    echo "Preserving custom browser bridge: $bridge" >&2; return 1
  elif [ -e "$bridge" ] && ! cmp -s "$source_file" "$bridge"; then
    if ! previous_toolkit_bridge "$bridge"; then
      echo "Preserving custom browser bridge: $bridge" >&2; return 1
    fi
  fi
  if [ -L "$profile" ] || { [ -e "$profile" ] && ! cmp -s "$profile" <(printf '%s\n' "$profile_line"); }; then
    echo "Preserving custom browser profile: $profile" >&2; return 1
  fi
  if ! cmp -s "$source_file" "$bridge" || [ ! -x "$bridge" ]; then
    sudo install -m 0755 -- "$source_file" "$bridge" || return 1
  fi
  if [ ! -e "$profile" ]; then
    printf '%s\n' "$profile_line" | sudo tee "$profile" >/dev/null || return 1
    # No "--" here: BSD chmod reads the mode as its first operand and would treat "--" as a file.
    sudo chmod 0644 "$profile" || return 1
  fi
  # Preserve existing handlers, including dangling symlinks.
  if [ ! -e "$bin_dir/xdg-open" ] && [ ! -L "$bin_dir/xdg-open" ] && ! command -v xdg-open >/dev/null 2>&1; then
    sudo ln -s -- "$bridge" "$bin_dir/xdg-open" || return 1
  fi
  cmp -s "$source_file" "$bridge" && [ -x "$bridge" ] &&
    cmp -s "$profile" <(printf '%s\n' "$profile_line")
}
