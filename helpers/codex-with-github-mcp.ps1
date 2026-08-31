# Start Codex with a GitHub MCP token taken from GitHub CLI's credential store.
# The token is scoped to this process and its child process, not the user environment.
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CodexArgs)

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI is required. Install it, authenticate with gh auth login, then retry."
}
& gh auth status --hostname github.com --active 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI is not authenticated. Run: gh auth login --hostname github.com --git-protocol https --web"
}
$env:GITHUB_MCP_PAT = (& gh auth token --hostname github.com 2>$null | Select-Object -First 1).Trim()
if (-not $env:GITHUB_MCP_PAT) { throw "GitHub CLI did not provide a token." }
& codex @CodexArgs
exit $LASTEXITCODE
