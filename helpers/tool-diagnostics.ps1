# Read-only command provenance. Never query credentials or private key stores.
function Show-ToolDiagnostic([string]$Name, [string]$ExplicitPath = '') {
    $commands = @(Get-Command $Name -All -ErrorAction SilentlyContinue)
    if ($ExplicitPath) {
        $selected = Get-Command -Name $ExplicitPath -CommandType Application -ErrorAction SilentlyContinue
        if (-not $selected) { Bad "$Name override is not an executable application"; return }
    }
    elseif ($commands.Count) { $selected = $commands[0] }
    else { Warn "$Name unavailable"; return }
    # Functions and aliases may mask an executable. Do not execute their source.
    if ($selected.CommandType -ne 'Application') {
        Warn "$Name resolves to $($selected.CommandType); executable version not probed"; return
    }
    Ok ("${Name}: " + $selected.Path)
    foreach ($alternative in $commands) {
        if ($alternative.CommandType -eq 'Application' -and $alternative.Path -ne $selected.Path) {
            Warn ("${Name} alternative: " + $alternative.Path)
        }
    }
    # gpg --version does not list keys, launch pinentry, or sign anything.
    try {
        if ($Name -in @('rustup', 'rustc', 'cargo')) {
            $probe = Invoke-RustProbe -Command $selected.Path -Arguments @('--version')
            $version = @($probe.Output); $probeExit = $probe.ExitCode
        }
        else { $version = @(& $selected.Path --version 2>$null); $probeExit = $LASTEXITCODE }
    }
    catch { Warn "$Name version probe failed"; return }
    if ($probeExit -ne 0 -or -not $version.Count) { Warn "$Name version probe failed" }
    else { Ok ("${Name} version: " + $version[0]) }
}
