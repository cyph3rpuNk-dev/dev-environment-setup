# Start Codex with a GitHub MCP token taken from GitHub CLI's credential store.
# The token is scoped to this process and its child process, not the user environment.
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CodexArgs)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
    throw "Codex CLI is required. Install it before using this helper."
}
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI is required. Install it, authenticate with gh auth login, then retry."
}
& gh auth status --hostname github.com --active 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI is not authenticated. Run: gh auth login --hostname github.com --git-protocol https --web"
}
$token = ((& gh auth token --hostname github.com 2>$null) | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
    throw "GitHub CLI did not provide a token."
}
$previousToken = $env:GITHUB_MCP_PAT
$codexExitCode = 1
try {
    $env:GITHUB_MCP_PAT = $token
    & codex @CodexArgs
    $codexExitCode = $LASTEXITCODE
}
finally {
    $env:GITHUB_MCP_PAT = $previousToken
    $token = $null
}
exit $codexExitCode
