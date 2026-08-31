#!/usr/bin/env bash
# Start Codex with a GitHub MCP token taken from GitHub CLI's credential store.
# The token is exported only to this child process, never to ~/.bashrc.
set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required. Install it, authenticate with gh auth login, then retry." >&2
  exit 1
fi
if ! gh auth status --hostname github.com --active >/dev/null 2>&1; then
  echo "GitHub CLI is not authenticated. Run: gh auth login --hostname github.com --git-protocol https --web" >&2
  exit 1
fi

GITHUB_MCP_PAT="$(gh auth token --hostname github.com)"
export GITHUB_MCP_PAT
exec codex "$@"
