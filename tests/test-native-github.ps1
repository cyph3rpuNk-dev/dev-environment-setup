# Exercise native stderr, not PowerShell function mocks. Never use real credentials.
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { Write-Host 'SKIP: native Windows stderr fixture'; exit 0 }
$root = Split-Path -Parent $PSScriptRoot
$shellExe = (Get-Process -Id $PID).Path
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('devsetup-native-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixture
$savedPath = $env:PATH
$savedMode = $env:TEST_NATIVE_GH
$utf8 = New-Object Text.UTF8Encoding($false)
try {
    $gh = @'
@echo off
if "%TEST_NATIVE_GH%"=="unauth" (
  echo not logged in 1>&2
  exit /b 1
)
if "%2"=="token" (
  echo UNEXPECTED_TOKEN_LOOKUP
  exit /b 99
)
if "%TEST_NATIVE_GH%"=="old" if "%5"=="--active" (
  echo unknown flag: --active 1>&2
  exit /b 1
)
echo Logged in to github.com account workflow 1>&2
if "%TEST_NATIVE_GH%"=="missing" (
  echo   - Token scopes: 'repo' 1>&2
) else if not "%TEST_NATIVE_GH%"=="unknown" (
  echo   - Token scopes: 'repo', 'workflow' 1>&2
)
exit /b 0
'@
    [IO.File]::WriteAllText("$fixture/gh.cmd", $gh.Replace("`n", "`r`n"), $utf8)
    $codex = @'
@echo off
echo UNEXPECTED_AGENT_LAUNCH
exit /b 7
'@
    [IO.File]::WriteAllText("$fixture/codex.cmd", $codex.Replace("`n", "`r`n"), $utf8)
    $runner = @'
param($Root, $Mode)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
. (Join-Path $Root 'helpers/github-auth.ps1')
$status = Get-GitHubAuthStatus
Write-Output ("AUTH=" + $status.Authenticated + " SCOPE=" + $status.WorkflowScope)
$env:GITHUB_MCP_PAT = 'fake-previous-token'
try {
    & (Join-Path $Root 'helpers/codex-with-github-mcp.ps1') 2>&1 | Out-String | Write-Output
    $result = $LASTEXITCODE
} catch {
    Write-Output $_.Exception.Message
    $result = 1
}
if ($env:GITHUB_MCP_PAT -ne 'fake-previous-token') { throw 'Caller token was not restored' }
Write-Output "RESULT=$result"
exit 0
'@
    [IO.File]::WriteAllText("$fixture/runner.ps1", $runner, $utf8)
    $env:PATH = $fixture + [IO.Path]::PathSeparator + $savedPath
    foreach ($mode in @('present', 'old', 'missing', 'unknown', 'unauth')) {
        $env:TEST_NATIVE_GH = $mode
        $output = & $shellExe -NoProfile -File "$fixture/runner.ps1" $root $mode | Out-String
        $expected = 1
        if ($LASTEXITCODE -ne 0 -or $output -notmatch "RESULT=$expected") { throw "Native gh fixture failed ($mode): $output" }
        if ($mode -in @('old', 'unknown') -and $output -notmatch 'SCOPE=unknown') { throw 'Unknown scopes were asserted' }
        if ($mode -eq 'missing' -and $output -notmatch 'SCOPE=missing') { throw 'Account name mistaken for scope' }
        if ($mode -eq 'present' -and $output -notmatch 'SCOPE=present') { throw 'Native stderr scopes not captured' }
        if ($mode -eq 'unauth' -and $output -notmatch 'AUTH=False') { throw 'Unauthenticated status missing' }
        if ($output -match 'fake-native-token|fake-previous-token|UNEXPECTED_') { throw 'Token leaked to output' }
        if ($output -notmatch 'launcher is retired') { throw 'Migration guidance missing' }
        Write-Host "PASS: Native GitHub CLI stderr and retired launcher ($mode)"
    }
}
finally {
    $env:PATH = $savedPath
    $env:TEST_NATIVE_GH = $savedMode
    $resolved = (Resolve-Path -LiteralPath $fixture).ProviderPath
    if ($resolved -ne [IO.Path]::GetFullPath($fixture) -or (Get-Item -LiteralPath $resolved).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Unsafe native fixture cleanup path' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
