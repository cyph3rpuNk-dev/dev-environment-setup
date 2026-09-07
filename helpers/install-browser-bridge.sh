#!/usr/bin/env bash
# Source this file; installation happens only when the function is called.
install_browser_bridge() {
  local source_file="$1" bin_dir="$2" profile_dir="$3"
  local bridge="$bin_dir/wslview" profile="$profile_dir/wsl-browser.sh"
  local profile_line="export BROWSER=$bin_dir/wslview"
  [ -f "$source_file" ] || { echo 'Browser bridge source missing.' >&2; return 1; }
  # Replace only the exact legacy shim shipped by this repository.
  if [ -L "$bridge" ]; then
    echo "Preserving custom browser bridge: $bridge" >&2; return 1
  elif [ -e "$bridge" ] && ! cmp -s "$source_file" "$bridge"; then
    if ! cmp -s "$bridge" <(cat <<'LEGACY'
#!/usr/bin/env bash
# Hand a URL to the Windows default browser. WSL has no browser of its own.
set -euo pipefail
if [ $# -lt 1 ]; then
  echo "usage: wslview <url>" >&2
  exit 2
fi
exec /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe \
     -NoProfile -NonInteractive -Command "Start-Process '$1'" >/dev/null 2>&1
LEGACY
    ); then
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
    sudo chmod 0644 -- "$profile" || return 1
  fi
  # Preserve existing handlers, including dangling symlinks.
  if [ ! -e "$bin_dir/xdg-open" ] && [ ! -L "$bin_dir/xdg-open" ]; then
    sudo ln -s -- "$bridge" "$bin_dir/xdg-open" || return 1
  fi
  cmp -s "$source_file" "$bridge" && [ -x "$bridge" ] &&
    cmp -s "$profile" <(printf '%s\n' "$profile_line")
}
