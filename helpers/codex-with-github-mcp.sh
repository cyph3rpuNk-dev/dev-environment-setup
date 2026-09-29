#!/usr/bin/env bash
# Start Codex with a GitHub MCP token taken from GitHub CLI's credential store.
# The token is exported to this process only, never to ~/.bashrc. Codex and every
# command it runs inherit it, with the token's full GitHub CLI access.
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
if [ -z "$GITHUB_MCP_PAT" ]; then
  echo "GitHub CLI did not provide a token." >&2
  exit 1
fi
export GITHUB_MCP_PAT
exec codex "$@"
