#!/usr/bin/env bash
# Source this file. WSL mounts Windows drives as <root><letter>, where the root is
# /mnt/ unless /etc/wsl.conf sets [automount] root. DEVSETUP_WSL_CONF overrides the
# file for the offline tests.

# Print the drive mount root with a trailing slash, for example /mnt/ or /windows/.
wsl_drive_root() {
  local root
  root=$(awk '
    /^[[:space:]]*\[/ { section = tolower($0); gsub(/[[:space:]]/, "", section); next }
    section == "[automount]" && index($0, "=") > 0 {
      key = tolower(substr($0, 1, index($0, "=") - 1)); gsub(/[[:space:]]/, "", key)
      if (key != "root") next
      value = substr($0, index($0, "=") + 1)
      sub(/[[:space:]]+#.*$/, "", value)
      gsub(/^[[:space:]"]+|[[:space:]"]+$/, "", value)
      print value; exit
    }' "${DEVSETUP_WSL_CONF:-/etc/wsl.conf}" 2>/dev/null)
  # Only an absolute root is meaningful; anything else means the default.
  case "$root" in /*) ;; *) root=/mnt/ ;; esac
  case "$root" in */) ;; *) root="$root/" ;; esac
  printf '%s\n' "$root"
}

# Succeed when an absolute, already-resolved path is on a mounted Windows drive.
wsl_is_windows_path() {
  local root
  root=$(wsl_drive_root)
  case "${1%/}/" in "$root"[A-Za-z]/*) return 0 ;; esac
  return 1
}

# Print the Windows PowerShell executable the browser bridge will use, or fail. Keep
# this lookup identical to helpers/wslview.sh: the usual path, then Windows' PATH,
# which WSL interop appends and which follows a custom mount root.
wsl_powershell() {
  local default=${DEVSETUP_WSL_POWERSHELL:-/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe}
  if [ -x "$default" ]; then printf '%s\n' "$default"; return 0; fi
  command -v powershell.exe 2>/dev/null
}
