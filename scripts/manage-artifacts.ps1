# Self-contained project helper. Only explicitly owned cache/run entries can be removed.
[CmdletBinding()]
param([ValidateSet('Create','Inspect','Clean')][string]$Action = 'Inspect',
      [ValidateSet('cache','runs','evidence','releases')][string]$Category = 'cache',
      [string]$Id, [switch]$Apply,
      [string]$ProjectDirectory)
$ErrorActionPreference = 'Stop'
if (-not $ProjectDirectory) { $ProjectDirectory = Split-Path -Parent $PSScriptRoot }
try {
    $Category = $Category.ToLowerInvariant()
    if (-not $Id -and $Action -eq 'Create') { $Id = [guid]::NewGuid().ToString('N') }
    if ($Id -cnotmatch '^[a-f0-9]{32}$') { throw 'An exact 32-character lowercase hexadecimal Id is required' }
    if ($Apply -and $Action -ne 'Clean') { throw '-Apply is only valid with Clean' }
    $root = (Resolve-Path -LiteralPath $ProjectDirectory).ProviderPath.TrimEnd([IO.Path]::DirectorySeparatorChar)
    $base = Join-Path $root "artifacts/$Category"
    $path = [IO.Path]::GetFullPath((Join-Path $base $Id))
    if ((Split-Path -Parent $path) -ne [IO.Path]::GetFullPath($base)) { throw 'Artifact path escaped its category' }
    foreach ($component in @($root, (Join-Path $root 'artifacts'), $base, $path)) {
        if (Test-Path -LiteralPath $component) {
            $item = Get-Item -LiteralPath $component -Force
            if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Artifact boundary contains a file or reparse point' }
        }
    }
    $marker = "devsetup-artifact-v1`ncategory`t$Category`nid`t$Id`n"
    if ($Action -eq 'Create') {
        if (Test-Path -LiteralPath $path) { throw 'Artifact already exists; preserve it' }
        $null = New-Item -ItemType Directory -Path $base -Force
        $null = New-Item -ItemType Directory -Path $path
        [IO.File]::WriteAllText((Join-Path $path '.devsetup-owned'), $marker, (New-Object Text.UTF8Encoding($false)))
        Write-Output $path; exit 0
    }
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw 'Artifact does not exist' }
    $pending = New-Object 'System.Collections.Generic.Stack[string]'; $pending.Push($path)
    $bytes = [long]0
    while ($pending.Count) {
        foreach ($entry in Get-ChildItem -LiteralPath $pending.Pop() -Force) {
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Artifact tree contains a reparse point; preserve it' }
            if ($entry.Name -eq '.git') { throw 'Artifact tree contains repository metadata; preserve it' }
            if ($entry.PSIsContainer) { $pending.Push($entry.FullName) } else { $bytes += $entry.Length }
        }
    }
    if ([IO.File]::ReadAllText((Join-Path $path '.devsetup-owned')) -cne $marker) { throw 'Ownership marker is absent or does not match' }
    if ($Action -eq 'Inspect') { Write-Output $path; exit 0 }
    if (@('cache','runs') -notcontains $Category) { throw 'Evidence and releases are retained; Clean does not remove them' }
    if (Test-Path -LiteralPath (Join-Path $root '.git')) {
        $tracked = @(git -C $root ls-files -- "artifacts/$Category/$Id")
        if ($LASTEXITCODE -ne 0 -or $tracked.Count) { throw 'Cannot establish that this artifact contains no tracked files' }
    }
    # A locked workflow is potentially active or interrupted; never clean it automatically.
    if (Test-Path -LiteralPath (Join-Path $path '.workflow-lock')) { throw 'Workflow lock exists; preserve the run' }
    $statePath = Join-Path $path 'state.txt'
    if ($Category -eq 'runs' -and (Test-Path -LiteralPath $statePath) -and
        [IO.File]::ReadAllText($statePath).Trim() -cne 'restored') { throw 'Workflow is not restored; preserve its recovery information' }
    Write-Host "Disposable artifact: $path ($bytes logical bytes)"
    if ($Apply) {
        # All path components and descendants were checked above; never delete the category/root.
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
        if (Test-Path -LiteralPath $path) { throw 'Artifact removal did not complete' }
        Write-Host 'Removed the selected owned artifact.'
    }
    else { Write-Host 'Preview only. Repeat the same selection with -Apply to remove it.' }
    exit 0
}
catch { Write-Host "FAIL: $_"; exit 1 }
