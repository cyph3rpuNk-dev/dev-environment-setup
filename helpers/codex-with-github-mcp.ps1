# Keep old shortcuts actionable without reading credentials or starting Codex.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'CodexArgs', Justification = 'Retired entry point accepts legacy arguments only to report migration guidance.')]
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CodexArgs)

Write-Error 'This GitHub MCP launcher is retired. Start codex normally and use gh for GitHub work. Remove the legacy GitHub MCP entry and GITHUB_MCP_PAT exports; see docs/agents.md.' -ErrorAction Continue
exit 1
