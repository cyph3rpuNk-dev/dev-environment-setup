# Start Codex with a GitHub MCP token taken from GitHub CLI's credential store.
# The token is set for this process and the Codex process only, not the user environment.
# Codex and every command it runs inherit it, with the token's full GitHub CLI access.
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CodexArgs)

$ErrorActionPreference = 'Stop'
# Preserve the child's exit status even if the caller enabled PS 7 native errors.
$PSNativeCommandUseErrorActionPreference = $false
. (Join-Path $PSScriptRoot 'github-auth.ps1')
if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
    throw "Codex CLI is required. Install it before using this helper."
}
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI is required. Install it, authenticate with gh auth login, then retry."
}
$auth = Get-GitHubAuthStatus
if (-not $auth.Authenticated) {
    throw "GitHub CLI is not authenticated. Run: gh auth login --hostname github.com --git-protocol https --web"
}
$tokenResult = Invoke-GitHubCli -Arguments @('auth', 'token', '--hostname', 'github.com')
$token = $tokenResult.Output.Trim()
if ($tokenResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
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
    $tokenResult = $null
}
exit $codexExitCode
