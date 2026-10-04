#!/usr/bin/env bash
# Keep old shortcuts actionable without reading credentials or starting Codex.
printf '%s\n' 'This GitHub MCP launcher is retired. Start codex normally and use gh for GitHub work.' \
  'Remove the legacy GitHub MCP entry and GITHUB_MCP_PAT exports; see docs/agents.md.' >&2
exit 1
