<#
    bootstrap-windows.ps1 : project-neutral Windows development tools

    Safe to run more than once. Only its own temporary linker probe is removed;
    project repositories are never modified.

        powershell -NoProfile -File .\bootstrap-windows.ps1 -Check           # report only, change nothing
        powershell -NoProfile -File .\bootstrap-windows.ps1 -InstallMissing  # winget-install missing tools
        powershell -NoProfile -File .\bootstrap-windows.ps1 -Doctor          # check plus environment probes

    Optional selections, supplied on every run including -Check and -Doctor:

        -Stack Rust,Python   add language stacks (Base is always included)
        -Wsl                 add a Linux environment through WSL; with -InstallMissing in an
                             Administrator PowerShell it enables the WSL platform
        -ConfigureAgents     create missing Claude Code and Codex defaults and MCP config

    The Visual Studio C++ workload remains a manual installation if the Rust linker
    probe fails, because selecting that large workload requires review. Choosing and
    installing a WSL distribution also stays with you.
#>

[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$InstallMissing,
    [switch]$Doctor,
    [string[]]$Stack = @('Base'),
    [switch]$Wsl,
    [switch]$ConfigureAgents
)

$ErrorActionPreference = 'Continue'
$script:Failures = 0
if ($Doctor) { $Check = $true }
# 'powershell -File' passes "-Stack Rust,Python" as one string, so split commas here
# rather than relying on array binding. Validate before doing any work.
$Stack = @($Stack | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($selected in $Stack) {
    if (@('Base', 'Rust', 'Python') -notcontains $selected) {
        Write-Host "unknown stack: $selected (choose Base, Rust, Python)" -ForegroundColor Red
        exit 1
    }
}
$wantRust = $Stack -contains 'Rust'
$wantPython = $Stack -contains 'Python'

function Say  ($m) { Write-Host ""; Write-Host "== $m ==" -ForegroundColor White }
function Ok   ($m) { Write-Host "  ok    $m" -ForegroundColor Green }
function Skip ($m) { Write-Host "  skip  $m" -ForegroundColor DarkGray }
function Warn ($m) { Write-Host "  warn  $m" -ForegroundColor Yellow }
function Bad  ($m) { Write-Host "  FAIL  $m" -ForegroundColor Red; $script:Failures++ }
function Have ($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }

# Agents and Node-based tools reject a UTF-8 byte-order mark in JSON, and Windows
# PowerShell 5.1 writes one for -Encoding UTF8. Write configuration without it.
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-ConfigFile ([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, $script:Utf8NoBom) }
function Add-ConfigText ([string]$Path, [string]$Text) { [IO.File]::AppendAllText($Path, $Text, $script:Utf8NoBom) }

function Test-Administrator {
    if ($env:OS -ne 'Windows_NT') { return $false }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Registered WSL distribution names, default first. wsl.exe emits UTF-16, so strip
# NULs. Only name-shaped lines count, so an informational message is never a name.
function Get-WslDistribution {
    if (-not (Have 'wsl')) { return @() }
    $listing = ((wsl --list --quiet 2>$null | Out-String) -replace "`0", '')
    if ($LASTEXITCODE -ne 0) { return @() }
    return @($listing -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[A-Za-z0-9._-]+$' })
}

# 'Hypervisor' (already running), 'Enabled', 'Disabled' or 'Unknown'. Read-only.
function Get-VirtualizationState {
    if ($env:OS -ne 'Windows_NT') { return 'Unknown' }
    try {
        if ((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).HypervisorPresent) { return 'Hypervisor' }
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
        if ($cpu.VirtualizationFirmwareEnabled) { return 'Enabled' } else { return 'Disabled' }
    }
    catch { return 'Unknown' }
}

function ConvertTo-WslPath ([string]$WindowsPath) {
    if ($WindowsPath -match '^([A-Za-z]):\\(.*)$') {
        return '/mnt/' + $Matches[1].ToLowerInvariant() + '/' + ($Matches[2] -replace '\\', '/')
    }
    return $WindowsPath
}

# ---------------------------------------------------------------------------
Say "0. Machine"
if ($env:OS -eq 'Windows_NT') {
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        Ok ("Windows build " + $os.BuildNumber)
        Ok ("RAM " + [math]::Round($cs.TotalPhysicalMemory / 1GB, 1) + " GB")
        $systemDrive = $env:SystemDrive.TrimEnd(':')
        $free = [math]::Round((Get-PSDrive $systemDrive -ErrorAction Stop).Free / 1GB, 1)
        if ($free -lt 20) { Warn "only $free GB free on ${systemDrive}:; toolchains and WSL need more" }
        else { Ok "$free GB free on ${systemDrive}:" }
    }
    catch { Warn "could not read machine details: $_" }
}
else { Warn "not running on Windows; machine details skipped. On Linux, use bootstrap-linux.sh." }

# ---------------------------------------------------------------------------
Say "1. Base tools"

$base = @(
    @{ Cmd = 'code';   Winget = 'Microsoft.VisualStudioCode'; What = 'VS Code' },
    @{ Cmd = 'git';    Winget = 'Git.Git';                    What = 'Git' },
    @{ Cmd = 'gh';     Winget = 'GitHub.cli';                 What = 'GitHub CLI (credential store)' },
    @{ Cmd = 'pwsh';   Winget = 'Microsoft.PowerShell';       What = 'PowerShell 7' }
)

if ($wantRust) {
    $base += @{ Cmd = 'rustup'; Winget = 'Rustlang.Rustup'; What = 'Rust toolchain installer' }
}
if ($wantPython) {
    # uv manages Python versions, environments, dependencies and uv.lock per project.
    $base += @{ Cmd = 'uv'; Winget = 'astral-sh.uv'; What = 'uv (Python projects)' }
}

foreach ($t in $base) {
    if (Have $t.Cmd) {
        Ok "$($t.What) found"
    }
    elseif ($Check) {
        if ($t.Cmd -eq 'gh') { Warn "$($t.What) is missing (optional GitHub access)" }
        else { Bad "$($t.What) is missing" }
    }
    elseif ($InstallMissing -and (Have 'winget')) {
        Write-Host "  installing $($t.What) ..."
        winget install --id $($t.Winget) -e --accept-package-agreements --accept-source-agreements | Out-Null
        if ($LASTEXITCODE -ne 0) { Bad "winget failed for $($t.What) (exit $LASTEXITCODE)" }
        elseif (Have $t.Cmd) { Ok "$($t.What) installed" }
        else { Warn "$($t.What) installed but not yet on PATH; open a new terminal" }
    }
    else {
        Warn "$($t.What) is missing.  Install with:  winget install --id $($t.Winget) -e"
    }
}

# ---------------------------------------------------------------------------
if ($wantRust) {
Say "2. Rust toolchain and the MSVC linker"

$msvcHost = $false
if (Have 'rustup') {
    if (-not $Check) {
        rustup component add rustfmt clippy | Out-Host
        if ($LASTEXITCODE -eq 0) { Ok "rustfmt + clippy installed" }
        else { Bad "could not install rustfmt + clippy" }
    }
    $hostLine = (rustup show 2>$null | Out-String)
    $msvcHost = $hostLine -match 'msvc'
    if ($msvcHost) { Ok "MSVC host toolchain in use" }
    else { Warn "MSVC host toolchain not detected. For Windows-native Rust use: rustup default stable-x86_64-pc-windows-msvc" }
}
else { Bad "rustup not available; the rest of this section is skipped" }

if (Have 'rustc') { Ok (rustc --version) }

# The single most common Windows Rust failure is a missing MSVC linker, and it
# only shows up at link time. So actually link something.
if ((Have 'cargo') -and -not $Check) {
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $probe = Join-Path $tempRoot ("rustprobe-" + [guid]::NewGuid().ToString('N'))
    $probeCreated = $false
    $locationPushed = $false
    Write-Host "  test-compiling a tiny crate to prove the linker works ..."
    try {
        # Own the temporary directory before invoking cargo; never reuse a path.
        if (Test-Path -LiteralPath $probe) { throw "Probe path already exists: $probe" }
        New-Item -ItemType Directory -Path $probe -ErrorAction Stop | Out-Null
        $probeCreated = $true
        cargo init --quiet --vcs none --bin $probe
        if ($LASTEXITCODE -ne 0) { throw "Could not create the linker probe" }
        Push-Location -LiteralPath $probe -ErrorAction Stop
        $locationPushed = $true
        cargo build --quiet
        if ($LASTEXITCODE -ne 0) { throw "Could not link the probe; install Visual Studio Build Tools with Desktop development with C++" }
        # Only an MSVC toolchain proves the MSVC linker; otherwise report what was shown.
        if ($msvcHost) { Ok "MSVC linker works" }
        else { Ok "the active Rust toolchain links a test program (it is not the MSVC toolchain)" }
    }
    catch { Bad "Linker probe failed: $_" }
    finally {
        if ($locationPushed) { Pop-Location }
        # Verify the absolute cleanup boundary and reject reparse points.
        if ($probeCreated -and (Test-Path -LiteralPath $probe)) {
            $resolvedProbe = (Resolve-Path -LiteralPath $probe).ProviderPath
            $probeItem = Get-Item -LiteralPath $probe -Force
            if ((Split-Path -Parent $resolvedProbe) -eq $tempRoot -and
                -not ($probeItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                Remove-Item -LiteralPath $resolvedProbe -Recurse -Force -ErrorAction Stop
            }
            else { Bad "Refusing cleanup outside the owned temporary directory: $probe" }
        }
    }
}

# ---------------------------------------------------------------------------
Say "3. Cargo tools"

function Install-Tool ($bin, $crate, $why) {
    if (Have $bin) { Ok "$bin already installed ($why)"; return }
    if ($Check) { Warn "$bin is missing ($why)"; return }
    if (Have 'cargo-binstall') {
        cargo binstall -y --no-confirm $crate | Out-Host
        if ($LASTEXITCODE -eq 0 -and (Have $bin)) { Ok "$bin installed ($why)"; return }
        Warn "binstall failed for $crate, falling back to a source build"
    }
    Write-Host "  building $crate from source, this can take a few minutes ..."
    cargo install --locked $crate | Out-Host
    if ($LASTEXITCODE -eq 0 -and (Have $bin)) { Ok "$bin installed ($why)" } else { Bad "could not install $crate" }
}

if (Have 'cargo') {
    if (-not (Have 'cargo-binstall') -and -not $Check) {
        Write-Host "  installing cargo-binstall (makes everything below much faster) ..."
        cargo install cargo-binstall --locked | Out-Host
        if ($LASTEXITCODE -eq 0 -and (Have 'cargo-binstall')) { Ok "cargo-binstall" } else { Warn "cargo-binstall unavailable; tools will build from source" }
    }
    Install-Tool 'cargo-nextest' 'cargo-nextest' 'test runner'
    Install-Tool 'cargo-audit'   'cargo-audit'   'dependency advisories'
    Install-Tool 'cargo-deny'    'cargo-deny'    'licence and advisory policy'
    Install-Tool 'bacon'         'bacon'         'background clippy while an agent edits'
    Install-Tool 'typos'         'typos-cli'     'documentation spell checking'
}
else { Bad "cargo not available; skipping cargo tools" }

} # Optional Rust stack

# ---------------------------------------------------------------------------
Say "4. VS Code extensions (Windows side)"

$exts = @(
    'ms-vscode.powershell',
    'ms-vscode.hexeditor',
    'usernamehw.errorlens',
    'github.vscode-github-actions',
    'github.vscode-pull-request-github',
    'redhat.vscode-yaml',
    'eamodio.gitlens',
    'gruntfuggly.todo-tree',
    'streetsidesoftware.code-spell-checker',
    'bierner.markdown-mermaid'
)

if ($Wsl) { $exts += 'ms-vscode-remote.remote-wsl' }
if ($wantRust) { $exts += @('rust-lang.rust-analyzer', 'ms-vscode.cpptools', 'tamasfe.even-better-toml', 'fill-labs.dependi') }
if ($wantPython) { $exts += @('ms-python.python', 'charliermarsh.ruff') }

if (-not (Have 'code')) {
    Warn "'code' is not on PATH. Open VS Code, then run this script from its integrated terminal."
}
else {
    $installed = @(code --list-extensions 2>$null); if (-not $installed) { $installed = @() }
    foreach ($e in $exts) {
        if ($installed -contains $e) {
            Ok $e
        }
        elseif ($Check) {
            Warn "$e is missing"
        }
        else {
            code --install-extension $e --force | Out-Host
            if ($LASTEXITCODE -eq 0) { Ok "$e installed" }
            else { Bad "could not install $e (check the name in the Extensions view)" }
        }
    }
}

# ---------------------------------------------------------------------------
if ($Wsl) {
Say "5. WSL (optional Linux environment)"
# Use WSL when a project targets Linux: web servers, PHP/WordPress, containers,
# Linux services or Linux-only tools. Windows-native projects do not need it.

$virtualization = Get-VirtualizationState
if ($virtualization -eq 'Disabled') {
    Bad "CPU virtualisation is disabled in firmware. Enable Intel VT-x or AMD-V in the BIOS/UEFI setup; WSL 2 cannot start without it."
}
elseif ($virtualization -eq 'Unknown') { Warn "could not read the virtualisation state" }
else { Ok "virtualisation available" }

$wslDistros = @(Get-WslDistribution)
$toolkitInWsl = ConvertTo-WslPath $PSScriptRoot
if (-not (Have 'wsl')) {
    Bad "wsl.exe not found. WSL needs Windows 10 version 2004 or later, or Windows 11."
}
elseif ($wslDistros.Count -gt 0) {
    Ok ("registered distributions: " + ($wslDistros -join ', '))
    Write-Host "  Inside the distribution:  cd '$toolkitInWsl' && bash bootstrap-linux.sh --check"
}
elseif ($Check -or -not $InstallMissing) {
    Warn "no WSL distribution is registered. Enable WSL with: -Wsl -InstallMissing from an Administrator PowerShell"
}
elseif (-not (Test-Administrator)) {
    Bad "enabling WSL needs an Administrator PowerShell. Open one and run:  wsl --install --no-distribution"
}
else {
    # --no-distribution enables the platform without silently choosing Ubuntu.
    wsl --install --no-distribution | Out-Host
    if ($LASTEXITCODE -ne 0) { Bad "wsl --install --no-distribution failed (exit $LASTEXITCODE)" }
    else {
        Ok "WSL platform enabled"
        Warn "restart Windows if asked, then choose a distribution:"
        Warn "  wsl --list --online      then    wsl --install <Name>   (for example Ubuntu-24.04 or a FedoraLinux entry)"
        Warn "  create the Linux user, then rerun this script with -Wsl -Doctor"
    }
}
} # Optional WSL

# ---------------------------------------------------------------------------
if ($ConfigureAgents) {
Say "6. Agent CLIs"

if (Have 'claude') { Ok "claude found" } else { Warn "claude CLI not found. Install it (see START-HERE.md), then run 'claude' once to sign in." }
if (Have 'codex')  { Ok "codex found" }  else { Warn "codex CLI not found. Install it (see START-HERE.md), then run 'codex' once to sign in." }

$codexDir = Join-Path $env:USERPROFILE '.codex'
$codexCfg = Join-Path $codexDir 'config.toml'
if (-not $Check -and -not (Test-Path $codexCfg)) {
    try {
        New-Item -ItemType Directory -Force -Path $codexDir -ErrorAction Stop | Out-Null
        Write-ConfigFile $codexCfg @'
# Codex owns whole tasks here, same as Claude Code, so it can write.
# approval_policy = "on-request" keeps commands asking before they run;
# that is the brake, not a read-only sandbox.
model_reasoning_effort = "high"
approval_policy = "on-request"
sandbox_mode = "workspace-write"

# For a deliberate second-opinion pass, put read-only settings in
# ~/.codex/review.config.toml and run Codex with that profile instead.

[mcp_servers.context7]
url = "https://mcp.context7.com/mcp"

[windows]
sandbox = "elevated"
'@
        Ok "wrote $codexCfg"
    }
    catch { Bad "could not write ${codexCfg}: $_" }
}
elseif (Test-Path $codexCfg) {
    Skip "$codexCfg already exists, left alone"
}

# ---------------------------------------------------------------------------
Say "7. GitHub credentials"
# Do not persist a PAT in the Windows environment or a shell profile. The script
# checks GitHub CLI authentication but never reads the token. The optional Codex
# helper obtains it only for the Codex child process. Claude's PAT-backed GitHub MCP
# configuration is an explicit manual choice because it stores an authorization
# header in Claude's user-scoped MCP configuration.
$githubAuthenticated = $false
if (Have 'gh') {
    gh auth status --hostname github.com --active 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Ok "GitHub CLI is authenticated"
        $githubAuthenticated = $true
    }
    else {
        Warn "GitHub CLI is not authenticated"
        if (-not $Check) {
            Warn "Run: gh auth login --hostname github.com --git-protocol https --web, then rerun this script"
        }
    }
}
else { Warn "GitHub CLI is missing; GitHub access and the optional MCP helper are unavailable" }

if ([Environment]::GetEnvironmentVariable('GITHUB_MCP_PAT', 'User')) {
    Warn "Legacy user variable GITHUB_MCP_PAT detected. Remove it after GitHub CLI authentication is working."
}

# ---------------------------------------------------------------------------
Say "8. MCP servers"

# --- Claude Code -----------------------------------------------------------
if (-not (Have 'claude')) {
    Skip "claude CLI not installed"
}
elseif ($Check) {
    Skip "not adding MCP servers"
}
else {
    $mcp = (claude mcp list 2>$null | Out-String)

    if ($mcp -match 'context7') {
        Ok "claude: context7 already configured"
    }
    else {
        claude mcp add --transport http --scope user context7 https://mcp.context7.com/mcp | Out-Host
        if ($LASTEXITCODE -eq 0) { Ok "claude: context7 added" }
        else { Bad "claude: could not add context7" }
    }

    if ($mcp -match 'github') { Ok "claude: github already configured" }
    else { Skip "claude: github is optional and is not configured automatically; see docs/agents.md" }
}

# --- Codex -----------------------------------------------------------------
if ($Check) {
    Skip "not editing $codexCfg"
}
elseif (-not (Test-Path $codexCfg)) {
    Skip "no config.toml yet"
}
elseif ((Get-Content $codexCfg -Raw) -match '\[mcp_servers\.github\]') {
    Ok "codex: github already in config.toml"
}
elseif ($githubAuthenticated) {
    try {
        Add-ConfigText $codexCfg @'

[mcp_servers.github]
url = "https://api.githubcopilot.com/mcp/"
# Read from the process environment. Launch Codex through helpers/codex-with-github-mcp.ps1.
bearer_token_env_var = "GITHUB_MCP_PAT"
'@
        Ok "codex: github added to config.toml"
    }
    catch { Bad "could not append GitHub configuration: $_" }
}
else {
    Skip "codex: github needs an authenticated GitHub CLI session"
}

# ---------------------------------------------------------------------------
Say "9. Claude Code user settings"
# Global permissions must be project-agnostic. Repository settings, not this
# file, decide whether builds, tests, or project scripts can run unattended.

$ccDir = Join-Path $env:USERPROFILE '.claude'
$ccSettings = Join-Path $ccDir 'settings.json'
if ($Check) {
    Skip "not writing $ccSettings"
}
elseif (Test-Path $ccSettings) {
    Skip "$ccSettings already exists, left alone (see docs/agents.md for the block to merge)"
}
else {
    try {
        New-Item -ItemType Directory -Force -Path $ccDir -ErrorAction Stop | Out-Null
        Write-ConfigFile $ccSettings @'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": [],
    "deny": [
      "Read(**/.env)",
      "Read(**/.env.*)",
      "Read(**/*.pem)",
      "Read(**/*.key)",
      "Read(**/*.pfx)",
      "Read(**/*.p12)",
      "Read(~/.gnupg/**)",
      "Read(~/.ssh/**)"
    ]
  },
  "autoMemoryEnabled": true
}
'@
        Ok "wrote $ccSettings"
    }
    catch { Bad "could not write ${ccSettings}: $_" }
}

# ---------------------------------------------------------------------------
} # Optional agent configuration

if ($Doctor) {
    Say "10. Doctor: environment boundaries and usable configuration"
    if ($env:OS -eq 'Windows_NT') { Ok "Windows host detected" } else { Bad "This script must run on Windows" }
    # Commits need a name and email. Report only whether they are set, never the values.
    if (Have 'git') {
        $gitName = (git config --global --get user.name 2>$null | Out-String).Trim()
        $gitEmail = (git config --global --get user.email 2>$null | Out-String).Trim()
        if (-not $gitName -or -not $gitEmail) {
            Warn "Git commit name or email is not set; set both with git config --global user.name / user.email"
        }
        elseif ($gitEmail -match '@users\.noreply\.github\.com$') { Ok "Git commit name and email are set (GitHub private address)" }
        else { Warn "Git commit email is not a GitHub private (noreply) address, so every pushed commit publishes it" }
    }
    if (-not $Wsl) {
        Skip "WSL not selected; add -Wsl to check the Linux environment"
    }
    elseif (Have 'wsl') {
        $wslList = @(Get-WslDistribution)
        if ($wslList.Count -eq 0) {
            Warn "No WSL distribution is registered"
        }
        else {
            # Matching '2' against the whole listing is not a check: it also matches a
            # name like 'Ubuntu-22.04', and it never proves the distribution can start.
            $distro = $wslList[0]
            $wslVerbose = ((wsl --list --verbose 2>$null | Out-String) -replace "`0", '')
            if ($wslVerbose -match ("(?m)^\s*\*?\s*" + [regex]::Escape($distro) + "\s+\S+\s+2\s*$")) {
                Ok "WSL distribution '$distro' is version 2"
            }
            else {
                Warn "WSL distribution '$distro' is not reported as version 2"
            }
            wsl -d $distro -- true 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Ok "WSL distribution '$distro' starts successfully"
            }
            else {
                Bad "WSL distribution '$distro' is registered but will not start. See 'A registered WSL distribution will not start' in docs/troubleshooting.md."
            }
        }
        if (Have 'code') {
            $installed = @(code --list-extensions 2>$null)
            if ($installed -contains 'ms-vscode-remote.remote-wsl') { Ok "VS Code WSL extension installed" }
            else { Warn "VS Code WSL extension missing" }
        }
    }
    else { Warn "WSL is unavailable" }
    if ($wantRust -and (Have 'rustup')) {
        $components = (rustup component list --installed 2>$null | Out-String)
        if ($components -match 'rustfmt' -and $components -match 'clippy') { Ok "rustfmt and clippy installed" }
        else { Warn "rustfmt or clippy missing" }
    }
    if ($wantPython) {
        if (Have 'uv') { Ok "uv available" } else { Warn "uv not available" }
    }
    if ($ConfigureAgents) {
    if (Test-Path $codexCfg) { Ok "Codex user configuration exists" } else { Warn "Codex user configuration missing" }
    if (Test-Path $ccSettings) { Ok "Claude user settings exist" } else { Warn "Claude user settings missing" }
    }
    Write-Host "  Doctor does not verify VS Code profile names or agent sign-in state; see doctor/README.md." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
Say "Summary"
if ($script:Failures -eq 0) { Write-Host "  No required failures. Review warnings and manual checks below." }
else { Write-Host "  $($script:Failures) problem(s) above need attention." -ForegroundColor Red }

Write-Host 'Next: START-HERE.md for readiness; docs/stacks/ for stacks; new-project.ps1 to start a project.'

exit $script:Failures
