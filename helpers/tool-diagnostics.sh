#!/usr/bin/env bash
# Sourced by doctor only. No credential queries or private-key inspection.
show_tool_diagnostic() {
  local name="$1" selected="${2:-}" candidate directory rest version
  if [ -z "$selected" ]; then selected=$(command -v "$name" 2>/dev/null) || { warn "$name unavailable"; return; }; fi
  case "$selected" in
    /*) ;;
    *) warn "$name resolves to a shell command rather than an absolute executable; version not probed"; return ;;
  esac
  ok "$name: $selected"
  # Scan PATH without eval, associative arrays or external language runtimes.
  rest="$PATH:"
  while [ -n "$rest" ]; do
    directory=${rest%%:*}; rest=${rest#*:}; [ -n "$directory" ] || directory=.
    candidate="$directory/$name"
    if [ -f "$candidate" ] && [ -x "$candidate" ] && [ "$candidate" != "$selected" ]; then
      warn "$name alternative: $candidate"
    fi
  done
  if [ "$IS_WSL" = 1 ]; then
    # Even --version on the WSL shim can install the VS Code server.
    if [ "$name" = code ]; then warn 'code version not probed in read-only WSL diagnostics'; return; fi
    if { type wsl_is_windows_path >/dev/null 2>&1 && wsl_is_windows_path "$selected"; } ||
       [[ "$selected" == *.exe ]]; then
      warn "$name uses a Windows-mounted/executable path in WSL; verify a Linux installation"; return
    fi
  fi
  case "$name" in
    rustup|rustc|cargo) version=$(rust_probe "$selected" --version 2>/dev/null);;
    *) version=$("$selected" --version 2>/dev/null);;
  esac
  if [ "$?" = 0 ]; then
    if [ -n "$version" ]; then ok "$name version: ${version%%$'\n'*}"; else warn "$name version probe returned no version"; fi
  else warn "$name version probe failed"; fi
}
