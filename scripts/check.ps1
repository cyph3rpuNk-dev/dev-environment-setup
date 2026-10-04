# Offline repository gate. Requires PowerShell 5.1+ and Bash (Git for Windows works).
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$failures = 0
# Native programs report failure through their exit code, and many (cargo, uv) write
# normal progress to stderr. Windows PowerShell 5.1 turns redirected stderr into error
# records, which would fail a successful step, so each step collects them: native
# stderr is printed, while any other PowerShell error still fails the step.
function Step([string]$Name, [scriptblock]$Action) {
    Write-Host "`n== $Name =="
    $global:LASTEXITCODE = 0
    $ErrorActionPreference = 'Continue'
    $problems = New-Object System.Collections.Generic.List[string]
    try {
        & $Action 2>&1 | ForEach-Object {
            if ($_ -isnot [Management.Automation.ErrorRecord]) { $_ }
            elseif ($_.FullyQualifiedErrorId -like 'NativeCommandError*') { Write-Host $_.ToString() }
            else { $problems.Add($_.ToString()) }
        }
        if ($LASTEXITCODE -ne 0) { $problems.Add("Native command exited with $LASTEXITCODE") }
    }
    catch { $problems.Add($_.ToString()) }
    if ($problems.Count -gt 0) {
        $script:failures++
        Write-Host "FAIL: $($problems[0])"
    }
}
Push-Location -LiteralPath $root
try {
    $shellExe = (Get-Process -Id $PID).Path
    $bash = if ($env:OS -eq 'Windows_NT' -and (Test-Path "$env:ProgramFiles/Git/bin/bash.exe")) {
        "$env:ProgramFiles/Git/bin/bash.exe"
    } else { (Get-Command bash -ErrorAction Stop).Source }
    Step 'PowerShell syntax and profile JSON' {
        $files = @(Get-ChildItem -Path *.ps1, helpers/*.ps1, scripts/*.ps1, tests/*.ps1, templates/foundation/*.ps1.template)
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
        foreach ($file in @(Get-ChildItem *.sh, helpers/*.sh, scripts/*.sh, tests/*.sh, templates/foundation/*.sh.template)) {
            & $bash -n $file.FullName.Replace('\', '/')
            if ($LASTEXITCODE -ne 0) { throw "Invalid Bash: $($file.Name)" }
        }
    }
    Step 'ShellCheck (when installed)' {
        if (Get-Command shellcheck -ErrorAction SilentlyContinue) {
            $scripts = @(Get-ChildItem *.sh, helpers/*.sh, scripts/*.sh, tests/*.sh, templates/foundation/*.sh.template | ForEach-Object { $_.FullName })
            & shellcheck -S warning -x @scripts
        }
        else { Write-Host 'skipped: shellcheck is not installed (CI runs it on Linux)' }
    }
    Step 'PSScriptAnalyzer (when installed)' {
        # CI pins the analyzer with DEVSETUP_PSSA_VERSION; 'skip' turns the step off.
        $pssaVersion = $env:DEVSETUP_PSSA_VERSION
        if ($pssaVersion -eq 'skip') { Write-Host 'skipped: DEVSETUP_PSSA_VERSION is skip'; return }
        if ($pssaVersion) { Import-Module PSScriptAnalyzer -RequiredVersion $pssaVersion -ErrorAction Stop }
        elseif (Get-Module -ListAvailable -Name PSScriptAnalyzer) { Import-Module PSScriptAnalyzer -ErrorAction Stop }
        else { Write-Host 'skipped: PSScriptAnalyzer is not installed (CI runs it on Linux)'; return }
        $settings = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
        $findings = @()
        foreach ($file in @(Get-ChildItem *.ps1, helpers/*.ps1, scripts/*.ps1, tests/*.ps1)) {
            $findings += @(Invoke-ScriptAnalyzer -Path $file.FullName -Settings $settings |
                ForEach-Object { "$($file.Name):$($_.Line) $($_.RuleName): $($_.Message)" })
        }
        # Templates are not .ps1 files, so analyze their text.
        foreach ($file in @(Get-ChildItem templates/foundation/*.ps1.template)) {
            $text = [IO.File]::ReadAllText($file.FullName)
            $findings += @(Invoke-ScriptAnalyzer -ScriptDefinition $text -Settings $settings |
                ForEach-Object { "$($file.Name):$($_.Line) $($_.RuleName): $($_.Message)" })
        }
        if ($findings.Count -gt 0) {
            $findings | ForEach-Object { Write-Host "  $_" }
            throw "$($findings.Count) PSScriptAnalyzer finding(s)"
        }
        Write-Host "PSScriptAnalyzer $((Get-Module PSScriptAnalyzer).Version): no findings"
    }
    Step 'PowerShell regression tests' { & $shellExe -NoProfile -File tests/test-powershell.ps1 }
    Step 'Bash regression tests' {
        # Git for Windows launched from PowerShell may inherit only Windows PATH.
        # Add Bash's own utilities explicitly without loading user shell profiles.
        & $bash -c 'export PATH="/usr/bin:/bin:$PATH"; exec bash tests/test-bash.sh'
    }
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
