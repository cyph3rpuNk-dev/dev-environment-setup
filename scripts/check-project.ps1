# Copy to a project's scripts/ directory; reads dev-requirements.tsv at its root.
[CmdletBinding()]
param([string]$ProjectDirectory, [switch]$SmokeBuild, [string]$Target)
$ErrorActionPreference = 'Stop'
if (-not $ProjectDirectory) { $ProjectDirectory = Split-Path -Parent $PSScriptRoot }
$priorAutoInstall = $env:RUSTUP_AUTO_INSTALL
try {
    $env:RUSTUP_AUTO_INSTALL = '0'
    $root = (Resolve-Path -LiteralPath $ProjectDirectory).ProviderPath
    $manifest = Join-Path $root 'dev-requirements.tsv'
    $rows = @(); $failures = 0
    if (Test-Path -LiteralPath $manifest) {
        $lines = [IO.File]::ReadAllLines($manifest)
        if (-not $lines.Count -or $lines[0] -cne '# devsetup-requirements-v1') { throw 'Unknown requirements schema' }
        foreach ($line in $lines | Select-Object -Skip 1) {
            if (-not $line.Trim() -or $line.StartsWith('#')) { continue }
            $fields = @($line.Split([char]9))
            if ($fields.Count -ne 3 -or @('all','windows','unix') -cnotcontains $fields[2]) { throw 'Expected kind, value, scope separated by tabs' }
            $kind, $value, $scope = $fields
            switch -CaseSensitive ($kind) {
                { $_ -cin @('command','rust-target','pkg-config') } {
                    if ($value -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*$') { throw 'Invalid requirement name' }
                }
                'windows-sdk' {
                    if ($scope -cne 'windows' -or $value -notmatch '^10\.0\.[0-9]+\.[0-9]+$') { throw 'Windows SDK needs a 10.0.build.revision version and windows scope' }
                }
                'file' {
                    if ([IO.Path]::IsPathRooted($value) -or $value -match '(^|[\\/])\.\.([\\/]|$)' -or -not $value -or $value -match ':') { throw 'File requirements must stay relative to the project' }
                }
                default { throw "Unknown requirement kind: $kind" }
            }
            $rows += ,$fields
        }
    }
    if (-not $rows.Count) { Write-Host 'warn: no project requirements declared; readiness is not established' }
    foreach ($row in $rows) {
        $kind, $value, $scope = $row
        $windows = $env:OS -eq 'Windows_NT'
        if (($scope -eq 'windows' -and -not $windows) -or ($scope -eq 'unix' -and $windows)) { continue }
        $ready = $false
        switch ($kind) {
            'command' { $ready = [bool](Get-Command -Name $value -ErrorAction SilentlyContinue) }
            'file' { $ready = Test-Path -LiteralPath (Join-Path $root $value) -PathType Leaf }
            'rust-target' {
                if (Get-Command rustup -ErrorAction SilentlyContinue) {
                    # Older rustup ignores AUTO_INSTALL; avoid project pin discovery.
                    Push-Location -LiteralPath ([IO.Path]::GetPathRoot($root))
                    try {
                        $installed = @(rustup target list --installed 2>$null)
                        $ready = $LASTEXITCODE -eq 0 -and $installed -contains $value
                    }
                    finally { Pop-Location }
                }
            }
            'pkg-config' {
                if (Get-Command pkg-config -ErrorAction SilentlyContinue) { & pkg-config --exists $value; $ready = $LASTEXITCODE -eq 0 }
            }
            'windows-sdk' {
                $kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10'
                $ready = (Test-Path -LiteralPath "$kits/Include/$value/um/Windows.h" -PathType Leaf) -and
                         (Test-Path -LiteralPath "$kits/Lib/$value/um/x64/kernel32.lib" -PathType Leaf)
            }
        }
        if ($ready) { Write-Host "ok: $kind $value" }
        else { $failures++; Write-Host "FAIL: $kind $value" }
    }
    if ($SmokeBuild) {
        if ($failures) { throw 'Prerequisites failed; smoke build was not started' }
        if ($Target -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or
            -not (Test-Path -LiteralPath "$root/Cargo.toml") -or -not (Test-Path -LiteralPath "$root/Cargo.lock")) {
            throw 'Rust smoke build requires an explicit target, Cargo.toml and Cargo.lock'
        }
        Push-Location -LiteralPath $root
        try { cargo build --locked --target $Target; if ($LASTEXITCODE -ne 0) { $failures++ } }
        finally { Pop-Location }
    }
    exit $failures
}
catch { Write-Host "FAIL: $_"; exit 1 }
finally { $env:RUSTUP_AUTO_INSTALL = $priorAutoInstall }
