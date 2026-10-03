# Source only. Keep native stderr from becoming a terminating error on PS 5.1.
# Callers inspect ExitCode; captured output (including tokens) is never logged here.
function Invoke-GitHubCli {
    param([string[]]$Arguments, [switch]$IncludeError)
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    if ($IncludeError) { $output = @(& gh @Arguments 2>&1 | ForEach-Object { "$_" }) }
    else { $output = @(& gh @Arguments 2>$null) }
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
}

function Get-GitHubAuthStatus {
    $result = Invoke-GitHubCli -Arguments @('auth', 'status', '--hostname', 'github.com', '--active') -IncludeError
    $activeOnly = $true
    if ($result.ExitCode -ne 0 -and $result.Output -match 'unknown flag: --active') {
        $activeOnly = $false
        $result = Invoke-GitHubCli -Arguments @('auth', 'status', '--hostname', 'github.com') -IncludeError
    }
    $scopeState = 'unknown'
    if ($result.ExitCode -eq 0 -and $activeOnly -and $result.Output -match '(?m)^\s*- Token scopes:\s*([^\r\n]*)') {
        $scopes = @($Matches[1] -split ',' | ForEach-Object { $_.Trim().Trim("'") })
        $scopeState = if ($scopes -contains 'workflow') { 'present' } else { 'missing' }
    }
    [pscustomobject]@{ Authenticated = ($result.ExitCode -eq 0); WorkflowScope = $scopeState }
}
