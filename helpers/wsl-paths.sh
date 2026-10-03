#!/usr/bin/env bash
# Source this file. WSL mounts Windows drives as <root><letter>, where the root is
# /mnt/ unless /etc/wsl.conf sets [automount] root. DEVSETUP_WSL_CONF overrides the
# file for the offline tests.

# Print the drive mount root with a trailing slash, for example /mnt/ or /windows/.
# Tolerates a UTF-8 byte-order mark (Windows editors add one), a comment after the
# section header, and single or double quotes around the value.
wsl_drive_root() {
  local root
  root=$(BOM=$(printf '\357\273\277') QUOTE="'" awk '
    NR == 1 && index($0, ENVIRON["BOM"]) == 1 { $0 = substr($0, length(ENVIRON["BOM"]) + 1) }
    /^[[:space:]]*\[/ {
      section = tolower($0); sub(/\].*$/, "]", section); gsub(/[[:space:]]/, "", section); next
    }
    section == "[automount]" && index($0, "=") > 0 {
      key = tolower(substr($0, 1, index($0, "=") - 1)); gsub(/[[:space:]]/, "", key)
      if (key != "root") next
      value = substr($0, index($0, "=") + 1)
      sub(/[[:space:]]+#.*$/, "", value)
      q = ENVIRON["QUOTE"]
      gsub("^[[:space:]\"" q "]+|[[:space:]\"" q "]+$", "", value)
      print value; exit
    }' "${DEVSETUP_WSL_CONF:-/etc/wsl.conf}" 2>/dev/null)
  # Only an absolute root is meaningful; anything else means the default.
  case "$root" in /*) ;; *) root=/mnt/ ;; esac
  case "$root" in */) ;; *) root="$root/" ;; esac
  printf '%s\n' "$root"
}

# Succeed when an absolute, already-resolved path is on a mounted Windows drive.
# The default /mnt/ is always checked as well as the configured root, so a wsl.conf
# that is read differently from how WSL reads it never removes the default guard.
wsl_is_windows_path() {
  local root real path="${1%/}/"
  for root in "$(wsl_drive_root)" /mnt/; do
    case "$path" in "$root"[A-Za-z]/*) return 0 ;; esac
    # Callers pass a resolved path, so also compare with the root's resolved path in
    # case the root is reached through a symbolic link.
    real=$(cd -P -- "$root" 2>/dev/null && pwd -P) || continue
    case "$path" in "${real%/}/"[A-Za-z]/*) return 0 ;; esac
  done
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
