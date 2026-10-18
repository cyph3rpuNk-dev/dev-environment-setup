# Disposable fixtures only; no real provisioning, compiler, auth or host cleanup.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$shell = (Get-Process -Id $PID).Path
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('devsetup-maintenance-' + [guid]::NewGuid().ToString('N'))
$utf8 = New-Object Text.UTF8Encoding($false)
function Assert($Ready, [string]$Message) { if (-not $Ready) { throw $Message }; Write-Host "PASS: $Message" }
function Write-Text([string]$Path, [string]$Value) { [IO.File]::WriteAllText($Path, $Value, $utf8) }
$null = New-Item -ItemType Directory -Path $fixture
try {
    $project = Join-Path $fixture 'project'
    $null = New-Item -ItemType Directory -Path "$project/scripts"
    $requirements = "$project/dev-requirements.tsv"
    $harness = @'
param($Source, $Project)
$env:ProgramFiles_x86_fixture = "$Project/sdk-fixture"
[Environment]::SetEnvironmentVariable('ProgramFiles(x86)', $env:ProgramFiles_x86_fixture, 'Process')
function fixture-ready {}
function rustup {
    Add-Content "$Project/events.txt" 'rustup'
    if ($env:RUSTUP_AUTO_INSTALL -ne '0' -or (Get-Location).ProviderPath -ne [IO.Path]::GetPathRoot($Project)) { throw 'unsafe project toolchain probe' }
    'fixture-target'; $global:LASTEXITCODE = 0
}
function cargo { Add-Content "$Project/events.txt" ('cargo ' + ($args -join ' ')); $global:LASTEXITCODE = 0 }
& $Source -ProjectDirectory $Project -SmokeBuild -Target fixture-target
exit $LASTEXITCODE
'@
    Write-Text "$fixture/probe.ps1" $harness
    Write-Text "$project/Cargo.toml" '# inert fixture'
    Write-Text "$project/Cargo.lock" '# inert fixture'
    Write-Text "$project/rust-toolchain.toml" "[toolchain]`nchannel = `"fixture-missing`"`n"
    Write-Text $requirements "# devsetup-requirements-v1`ncommand`tfixture-ready`tall`nrust-target`tfixture-target`tall`nfile`tCargo.lock`tall`n"
    & $shell -NoProfile -File "$fixture/probe.ps1" "$root/scripts/check-project.ps1" $project | Out-Null
    Assert ($LASTEXITCODE -eq 0 -and (Get-Content -Raw "$project/events.txt") -match 'cargo build --locked --target fixture-target') 'Project requirements allow an explicit mocked smoke build'
    Write-Text "$project/events.txt" ''
    Write-Text $requirements "# devsetup-requirements-v1`ncommand`tmissing-fixture-command-884`tall`n"
    & $shell -NoProfile -File "$fixture/probe.ps1" "$root/scripts/check-project.ps1" $project | Out-Null
    Assert ($LASTEXITCODE -ne 0 -and -not (Get-Content -Raw "$project/events.txt")) 'Missing prerequisites prevent compilation'
    Write-Text $requirements "# devsetup-requirements-v1`nfile`t../escape`tall`n"
    & $shell -NoProfile -File "$fixture/probe.ps1" "$root/scripts/check-project.ps1" $project | Out-Null
    Assert ($LASTEXITCODE -ne 0 -and -not (Get-Content -Raw "$project/events.txt")) 'Invalid manifests fail before running tools'
    if ($env:OS -eq 'Windows_NT') {
        Write-Text $requirements "# devsetup-requirements-v1`nwindows-sdk`t10.0.99999.0`twindows`n"
        & $shell -NoProfile -File "$fixture/probe.ps1" "$root/scripts/check-project.ps1" $project | Out-Null
        Assert ($LASTEXITCODE -ne 0 -and -not (Get-Content -Raw "$project/events.txt")) 'Missing SDK fixture prevents a build'
        foreach ($relative in @('Include/10.0.99999.0/um/Windows.h','Lib/10.0.99999.0/um/x64/kernel32.lib')) {
            $sdkPath = "$project/sdk-fixture/Windows Kits/10/$relative"
            $null = New-Item -ItemType Directory -Path (Split-Path -Parent $sdkPath) -Force
            Write-Text $sdkPath 'inert fixture'
        }
        & $shell -NoProfile -File "$fixture/probe.ps1" "$root/scripts/check-project.ps1" $project | Out-Null
        Assert ($LASTEXITCODE -eq 0) 'SDK header/import-library checks use only authored fixtures'
    }

    $artifact = "$root/scripts/manage-artifacts.ps1"
    $id = '11111111111111111111111111111111'
    $path = & $shell -NoProfile -File $artifact -ProjectDirectory $project -Action Create -Category cache -Id $id
    Assert ($LASTEXITCODE -eq 0) 'Artifact manager creates a fresh owned entry'
    Write-Text "$path/inert.txt" 'fixture'
    & $shell -NoProfile -File $artifact -ProjectDirectory $project -Action Clean -Category cache -Id $id | Out-Null
    Assert ($LASTEXITCODE -eq 0 -and (Test-Path "$path/inert.txt")) 'Cleanup previews preserve selected files'
    & $shell -NoProfile -File $artifact -ProjectDirectory $project -Action Clean -Category cache -Id $id -Apply | Out-Null
    Assert ($LASTEXITCODE -eq 0 -and -not (Test-Path $path)) 'Explicit cleanup removes only the owned disposable entry'
    foreach ($category in @('evidence','releases')) {
        $retained = & $shell -NoProfile -File $artifact -ProjectDirectory $project -Action Create -Category $category -Id $id
        & $shell -NoProfile -File $artifact -ProjectDirectory $project -Action Clean -Category $category -Id $id -Apply | Out-Null
        Assert ($LASTEXITCODE -ne 0 -and (Test-Path $retained)) "$category cannot be removed by cleanup"
    }
    $path = & $shell -NoProfile -File $artifact -ProjectDirectory $project -Action Create -Category cache -Id $id
    Write-Text "$path/.devsetup-owned" 'wrong owner'
    & $shell -NoProfile -File $artifact -ProjectDirectory $project -Action Clean -Category cache -Id $id -Apply | Out-Null
    Assert ($LASTEXITCODE -ne 0 -and (Test-Path $path)) 'Mismatched ownership prevents deletion'
    & $shell -NoProfile -File $artifact -ProjectDirectory $project -Action Clean -Category cache -Id '../escape' -Apply | Out-Null
    Assert ($LASTEXITCODE -ne 0) 'Cleanup rejects traversal before touching files'
    Write-Text "$path/.devsetup-owned" "devsetup-artifact-v1`ncategory`tcache`nid`t$id`n"
    $outside = Join-Path $fixture 'outside'
    $null = New-Item -ItemType Directory -Path $outside
    $link = Join-Path $path 'linked-directory'
    $createdLink = $false
    try {
        $linkType = if ($env:OS -eq 'Windows_NT') { 'Junction' } else { 'SymbolicLink' }
        try { $null = New-Item -ItemType $linkType -Path $link -Target $outside -ErrorAction Stop; $createdLink = $true }
        catch { Write-Host 'SKIP: linked-directory creation unavailable in this environment' }
        if ($createdLink) {
            & $shell -NoProfile -File $artifact -ProjectDirectory $project -Action Clean -Category cache -Id $id -Apply | Out-Null
            Assert ($LASTEXITCODE -ne 0 -and (Test-Path $outside)) 'Cleanup refuses a linked descendant and preserves its target'
        }
    }
    finally { if ($createdLink) { [IO.Directory]::Delete($link, $false) } }

    Copy-Item -LiteralPath $artifact -Destination "$project/scripts/manage-artifacts.ps1"
    git init --quiet $project
    $workflow = [IO.File]::ReadAllText("$root/templates/foundation/run-workflow.ps1.template")
    Write-Text "$project/scripts/run-workflow.ps1" $workflow
    & $shell -NoProfile -File "$project/scripts/run-workflow.ps1" -Phase Start | Out-Null
    Assert ($LASTEXITCODE -ne 0 -and -not (Test-Path "$project/artifacts/runs")) 'Unconfigured workflows refuse to create a test run'
    $workflow = $workflow.Replace('$WorkflowConfigured = $false', '$WorkflowConfigured = $true')
    $workflow = $workflow.Replace("throw 'Configure the start hook first'", '[IO.File]::WriteAllText((Join-Path $Directory "started.flag"), "fixture")')
    $workflow = $workflow.Replace("throw 'Require the producer closed, then snapshot and hash its logs here'", "throw 'fixture collection failure'")
    $workflow = $workflow.Replace("throw 'Configure idempotent restoration of owned test changes first'", '[IO.File]::WriteAllText((Join-Path $Directory "restored.flag"), "fixture")')
    Write-Text "$project/scripts/run-workflow.ps1" $workflow
    & $shell -NoProfile -File "$project/scripts/run-workflow.ps1" -Phase Start | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'Configured workflow starts an inert run'
    $run = Get-ChildItem -LiteralPath "$project/artifacts/runs" -Directory | Select-Object -First 1
    & $shell -NoProfile -File "$project/scripts/run-workflow.ps1" -Phase Collect -RunId $run.Name | Out-Null
    Assert ($LASTEXITCODE -ne 0 -and (Get-Content "$($run.FullName)/state.txt").Trim() -eq 'collect-failed') 'Failed collection is retained as a failed state'
    $null = New-Item -ItemType Directory -Path "$($run.FullName)/.workflow-lock"
    & $shell -NoProfile -File $artifact -ProjectDirectory $project -Action Clean -Category runs -Id $run.Name -Apply | Out-Null
    Assert ($LASTEXITCODE -ne 0 -and (Test-Path $run.FullName)) 'A workflow lock prevents cleanup'
    [IO.Directory]::Delete("$($run.FullName)/.workflow-lock", $false)
    & $shell -NoProfile -File $artifact -ProjectDirectory $project -Action Clean -Category runs -Id $run.Name -Apply | Out-Null
    Assert ($LASTEXITCODE -ne 0 -and (Test-Path $run.FullName)) 'An unrestored workflow retains its recovery information'
    & $shell -NoProfile -File "$project/scripts/run-workflow.ps1" -Phase Restore -RunId $run.Name | Out-Null
    Assert ($LASTEXITCODE -eq 0 -and (Test-Path "$($run.FullName)/restored.flag")) 'Restoration remains available after failed collection'
    & $shell -NoProfile -File "$project/scripts/run-workflow.ps1" -Phase Collect -RunId $run.Name | Out-Null
    Assert ($LASTEXITCODE -ne 0 -and (Get-Content "$($run.FullName)/state.txt").Trim() -eq 'restored') 'Out-of-order collection preserves the restored state'
    Assert (Test-Path "$($run.FullName)/metadata.tsv") 'Workflow records its revision availability, shell and helper hash'
    Assert ((Get-Content -Raw "$($run.FullName)/metadata.tsv") -match 'unborn-or-unavailable') 'A new repository without commits is labelled explicitly'
    Write-Text "$path/.devsetup-owned" "devsetup-artifact-v1`ncategory`tcache`nid`t$id`n"
    git -C $project -c core.autocrlf=false -c "core.hooksPath=$fixture/no-hooks" add -- "artifacts/cache/$id/.devsetup-owned"
    & $shell -NoProfile -File $artifact -ProjectDirectory $project -Action Clean -Category cache -Id $id -Apply | Out-Null
    Assert ($LASTEXITCODE -ne 0 -and (Test-Path $path)) 'Cleanup preserves tracked files within an owned disposable entry'
    $scaffoldParent = Join-Path $fixture 'scaffold'
    & $shell -NoProfile -File "$root/new-project.ps1" -Name helper-tool -Parent $scaffoldParent -Environment Windows -MaintenanceHelpers | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'Scaffolding can opt in to maintenance helpers'
    foreach ($file in @('dev-requirements.tsv','scripts/check-project.ps1','scripts/manage-artifacts.ps1','scripts/run-workflow.ps1')) {
        Assert (Test-Path "$scaffoldParent/helper-tool/$file") "Maintenance scaffold contains $file"
    }
    & $shell -NoProfile -File "$scaffoldParent/helper-tool/scripts/check-project.ps1" | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'Copied prerequisite checker works without the toolkit path'
}
finally {
    $resolved = (Resolve-Path -LiteralPath $fixture).ProviderPath
    if ($resolved -ne [IO.Path]::GetFullPath($fixture) -or (Get-Item -LiteralPath $resolved).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Unexpected fixture cleanup path' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host 'Maintenance regressions passed.'
