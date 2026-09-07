# Offline repository gate. Requires PowerShell 5.1+ and Bash (Git for Windows works).
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$failures = 0
function Step([string]$Name, [scriptblock]$Action) {
    Write-Host "`n== $Name =="
    $global:LASTEXITCODE = 0
    try {
        & $Action
        if ($LASTEXITCODE -ne 0) { throw "Command exited with $LASTEXITCODE" }
    }
    catch { $script:failures++; Write-Host "FAIL: $_" }
}
Push-Location -LiteralPath $root
try {
    $shellExe = (Get-Process -Id $PID).Path
    $bash = if ($env:OS -eq 'Windows_NT' -and (Test-Path "$env:ProgramFiles/Git/bin/bash.exe")) {
        "$env:ProgramFiles/Git/bin/bash.exe"
    } else { (Get-Command bash -ErrorAction Stop).Source }
    Step 'PowerShell syntax and profile JSON' {
        $files = @(Get-ChildItem -Path *.ps1, helpers/*.ps1, scripts/*.ps1, tests/*.ps1)
        foreach ($file in $files) {
            $tokens = $null; $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
            if ($parseErrors) { throw "$($file.Name): $($parseErrors.Message -join '; ')" }
        }
        foreach ($file in Get-ChildItem profiles/*.jsonc) {
            $json = (Get-Content -Encoding UTF8 $file.FullName | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
            $null = $json | ConvertFrom-Json
        }
    }
    Step 'Bash syntax' {
        foreach ($file in @(Get-ChildItem *.sh, helpers/*.sh, tests/*.sh, templates/foundation/*.sh.template)) {
            & $bash -n $file.FullName.Replace('\', '/')
            if ($LASTEXITCODE -ne 0) { throw "Invalid Bash: $($file.Name)" }
        }
    }
    Step 'PowerShell regression tests' { & $shellExe -NoProfile -File tests/test-powershell.ps1 }
    Step 'Bash regression tests' { & $bash tests/test-bash.sh }
    Step 'Whitespace' {
        # Compare the effective tracked tree with Git's empty tree. A plain
        # `git diff --check` is a no-op on a clean CI checkout.
        $nullDevice = if ($env:OS -eq 'Windows_NT') { 'NUL' } else { '/dev/null' }
        $emptyTree = ((git hash-object -t tree -- $nullDevice) | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($emptyTree)) {
            throw 'Could not determine the empty Git tree'
        }
        git diff --check $emptyTree --
    }
}
finally { Pop-Location }
exit $failures
