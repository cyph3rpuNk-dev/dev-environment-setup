<#
    bootstrap-windows.ps1 : project-neutral Windows development tools

    Safe to run more than once. Only its own temporary linker probe is removed;
    project repositories are never modified.

        pwsh -File .\bootstrap-windows.ps1              # base tools and general extensions
        pwsh -File .\bootstrap-windows.ps1 -Check       # report only, change nothing
        pwsh -File .\bootstrap-windows.ps1 -Doctor      # check machine, agents, and GitHub auth
        pwsh -File .\bootstrap-windows.ps1 -InstallMissing
                                                        # also winget-install VS Code,
                                                        # Git, GitHub CLI, and pwsh; -Stack Rust adds rustup

    The Visual Studio C++ workload remains a manual installation if the linker
    probe fails, because selecting that large workload requires review.
#>

[CmdletBinding()]
# Optional selections apply to this invocation only, including Check and Doctor.
# -Stack Rust adds Rust; -ConfigureAgents adds agent defaults and MCP.
param(
    [switch]$Check,
    [switch]$InstallMissing,
    [switch]$Doctor,
    [ValidateSet('Base', 'Rust')][string]$Stack = 'Base',
    [switch]$ConfigureAgents
)

$ErrorActionPreference = 'Continue'
$script:Failures = 0
if ($Doctor) { $Check = $true }

function Say  ($m) { Write-Host ""; Write-Host "== $m ==" -ForegroundColor White }
function Ok   ($m) { Write-Host "  ok    $m" -ForegroundColor Green }
function Skip ($m) { Write-Host "  skip  $m" -ForegroundColor DarkGray }
function Warn ($m) { Write-Host "  warn  $m" -ForegroundColor Yellow }
function Bad  ($m) { Write-Host "  FAIL  $m" -ForegroundColor Red; $script:Failures++ }
function Have ($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
# ---------------------------------------------------------------------------
Say "1. Base tools"

$base = @(
    @{ Cmd = 'code';   Winget = 'Microsoft.VisualStudioCode'; What = 'VS Code' },
    @{ Cmd = 'git';    Winget = 'Git.Git';                    What = 'Git' },
    @{ Cmd = 'gh';     Winget = 'GitHub.cli';                 What = 'GitHub CLI (credential store)' },
    @{ Cmd = 'pwsh';   Winget = 'Microsoft.PowerShell';       What = 'PowerShell 7' }
)

if ($Stack -eq 'Rust') {
    $base += @{ Cmd = 'rustup'; Winget = 'Rustlang.Rustup'; What = 'Rust toolchain installer' }
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
if ($Stack -eq 'Rust') {
Say "2. Rust toolchain and the MSVC linker"

if (Have 'rustup') {
    if (-not $Check) {
        rustup component add rustfmt clippy | Out-Host
        if ($LASTEXITCODE -eq 0) { Ok "rustfmt + clippy installed" }
        else { Bad "could not install rustfmt + clippy" }
    }
    $hostLine = (rustup show 2>$null | Out-String)
    if ($hostLine -match 'msvc') { Ok "MSVC host toolchain in use" }
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
        Ok "MSVC linker works"
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

# ---------------------------------------------------------------------------
} # Optional Rust stack

Say "4. VS Code extensions (Windows side)"

$exts = @(
    'ms-vscode.powershell',
    'ms-vscode.hexeditor',
    'ms-vscode-remote.remote-wsl',
    'usernamehw.errorlens',
    'github.vscode-github-actions',
    'github.vscode-pull-request-github',
    'redhat.vscode-yaml',
    'eamodio.gitlens',
    'gruntfuggly.todo-tree',
    'streetsidesoftware.code-spell-checker',
    'bierner.markdown-mermaid'
)

if ($Stack -eq 'Rust') { $exts += @('rust-lang.rust-analyzer', 'ms-vscode.cpptools', 'tamasfe.even-better-toml', 'fill-labs.dependi') }

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
if ($ConfigureAgents) {
Say "5. Agent CLIs"

if (Have 'claude') { Ok "claude found" } else { Warn "claude CLI not found. Install it, then run 'claude' once to sign in." }
if (Have 'codex')  { Ok "codex found" }  else { Warn "codex CLI not found. Install it, then run 'codex' once to sign in." }

$codexDir = Join-Path $env:USERPROFILE '.codex'
$codexCfg = Join-Path $codexDir 'config.toml'
if (-not $Check -and -not (Test-Path $codexCfg)) {
    New-Item -ItemType Directory -Force -Path $codexDir -ErrorAction Stop | Out-Null
    @'
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
'@ | Set-Content -Path $codexCfg -Encoding UTF8 -ErrorAction Stop
    Ok "wrote $codexCfg"
}
elseif (Test-Path $codexCfg) {
    Skip "$codexCfg already exists, left alone"
}

# ---------------------------------------------------------------------------
Say "6. GitHub credentials"
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
Say "7. MCP servers"

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
    else { Skip "claude: github is optional and is not configured automatically; see START-HERE.md" }
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
    @'

[mcp_servers.github]
url = "https://api.githubcopilot.com/mcp/"
# Read from the process environment. Launch Codex through helpers/codex-with-github-mcp.ps1.
bearer_token_env_var = "GITHUB_MCP_PAT"
'@ | Add-Content -Path $codexCfg -Encoding UTF8 -ErrorAction Stop
    Ok "codex: github added to config.toml"
}
else {
    Skip "codex: github needs an authenticated GitHub CLI session"
}

# ---------------------------------------------------------------------------
Say "8. Claude Code user settings"
# Global permissions must be project-agnostic. Repository settings, not this
# file, decide whether builds, tests, or project scripts can run unattended.

$ccDir = Join-Path $env:USERPROFILE '.claude'
$ccSettings = Join-Path $ccDir 'settings.json'
if ($Check) {
    Skip "not writing $ccSettings"
}
elseif (Test-Path $ccSettings) {
    Skip "$ccSettings already exists, left alone (see guide 5.3 for the block to merge)"
}
else {
    New-Item -ItemType Directory -Force -Path $ccDir -ErrorAction Stop | Out-Null
    @'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": [],
    "deny": [
      "Read(**/.env)",
      "Read(**/*.pfx)",
      "Read(**/*.p12)",
      "Read(~/.gnupg/**)",
      "Read(~/.ssh/**)"
    ]
  },
  "autoMemoryEnabled": true
}
'@ | Set-Content -Path $ccSettings -Encoding UTF8 -ErrorAction Stop
    Ok "wrote $ccSettings"
}

# ---------------------------------------------------------------------------
} # Optional agent configuration

if ($Doctor) {
    Say "9. Doctor: environment boundaries and usable configuration"
    if ($env:OS -eq 'Windows_NT') { Ok "Windows host detected" } else { Bad "This script must run on Windows" }
    if (Have 'wsl') {
        # wsl.exe emits UTF-16, so strip NULs before matching. Matching '2' against the
        # whole listing is not a check: it also matches a name like 'Ubuntu-22.04', and
        # it never proves the distribution can start. Probe the default one instead.
        $wslList = ((wsl --list --quiet 2>$null | Out-String) -replace "`0", '').Trim()
        if ([string]::IsNullOrWhiteSpace($wslList)) {
            Warn "No WSL distribution is registered"
        }
        else {
            $distro = ($wslList -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1).Trim()
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
                Bad "WSL distribution '$distro' is registered but will not start. See 'A registered WSL distribution will not start' in dev-environment-setup.md Appendix B."
            }
        }
    }
    else { Warn "WSL is unavailable" }
    if ($Stack -eq 'Rust' -and (Have 'rustup')) {
        $components = (rustup component list --installed 2>$null | Out-String)
        if ($components -match 'rustfmt' -and $components -match 'clippy') { Ok "rustfmt and clippy installed" }
        else { Warn "rustfmt or clippy missing" }
    }
    if (Have 'code') {
        $installed = @(code --list-extensions 2>$null)
        if ($installed -contains 'ms-vscode-remote.remote-wsl') { Ok "VS Code Remote - WSL extension installed" }
        else { Warn "VS Code Remote - WSL extension missing" }
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

Write-Host 'Next: START-HERE.md for base readiness; docs/stacks/ for optional stacks; docs/projects/ for project guides.'

exit $script:Failures
