<#
    bootstrap-windows.ps1 : dev environment for Nomad Launcher (Windows side)

    Safe to run more than once. It never deletes anything and never touches
    your repositories.

        pwsh -File .\bootstrap-windows.ps1              # do everything
        pwsh -File .\bootstrap-windows.ps1 -Check       # report only, change nothing
        pwsh -File .\bootstrap-windows.ps1 -Doctor      # check machine, agents, and GitHub auth
        pwsh -File .\bootstrap-windows.ps1 -InstallMissing
                                                        # also winget-install VS Code,
                                                        # Git, GitHub CLI, rustup, and pwsh

    The Visual Studio C++ workload remains a manual installation if the linker
    probe fails, because selecting that large workload requires review.
#>

[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$InstallMissing,
    [switch]$Doctor
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
    @{ Cmd = 'rustup'; Winget = 'Rustlang.Rustup';            What = 'Rust toolchain installer' },
    @{ Cmd = 'pwsh';   Winget = 'Microsoft.PowerShell';       What = 'PowerShell 7 (dist.ps1 wants it)' }
)

foreach ($t in $base) {
    if (Have $t.Cmd) {
        Ok "$($t.What) found"
    }
    elseif ($Check) {
        Warn "$($t.What) is missing"
    }
    elseif ($InstallMissing -and (Have 'winget')) {
        Write-Host "  installing $($t.What) ..."
        winget install --id $($t.Winget) -e --accept-package-agreements --accept-source-agreements | Out-Null
        if (Have $t.Cmd) { Ok "$($t.What) installed" }
        else { Warn "$($t.What) installed but not yet on PATH; open a new terminal" }
    }
    else {
        Warn "$($t.What) is missing.  Install with:  winget install --id $($t.Winget) -e"
    }
}

# ---------------------------------------------------------------------------
Say "2. Rust toolchain and the MSVC linker"

if (Have 'rustup') {
    if (-not $Check) {
        rustup component add rustfmt clippy 2>$null | Out-Null
        Ok "rustfmt + clippy requested"
    }
    $hostLine = (rustup show 2>$null | Out-String)
    if ($hostLine -match 'msvc') { Ok "MSVC host toolchain in use" }
    else { Warn "MSVC host toolchain not detected. Nomad needs it: rustup default stable-x86_64-pc-windows-msvc" }
}
else { Bad "rustup not available; the rest of this section is skipped" }

if (Have 'rustc') { Ok (rustc --version) }

# The single most common Windows Rust failure is a missing MSVC linker, and it
# only shows up at link time. So actually link something.
if ((Have 'cargo') -and -not $Check) {
    $probe = Join-Path $env:TEMP ("rustprobe-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    Write-Host "  test-compiling a tiny crate to prove the linker works ..."
    cargo new --quiet --bin $probe 2>$null | Out-Null
    Push-Location $probe
    cargo build --quiet 2>$null | Out-Null
    $linkOk = ($LASTEXITCODE -eq 0)
    Pop-Location
    Remove-Item -Recurse -Force $probe -ErrorAction SilentlyContinue
    if ($linkOk) {
        Ok "MSVC linker works"
    }
    else {
        Bad "could not link a test binary. You need the C++ build tools:"
        Write-Host "        winget install --id Microsoft.VisualStudio.2022.BuildTools -e" -ForegroundColor Yellow
        Write-Host "        then in the installer tick 'Desktop development with C++'" -ForegroundColor Yellow
    }
}

# Optional: signtool, only needed when you actually sign a release.
$sdkBin = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
if ((Have 'signtool') -or (Test-Path $sdkBin)) { Ok "Windows SDK present (signtool for dist.ps1 signing)" }
else { Skip "Windows SDK not found. Only needed to sign releases; dist.ps1 builds unsigned without it." }

# ---------------------------------------------------------------------------
Say "3. Cargo tools"

function Install-Tool ($bin, $crate, $why) {
    if (Have $bin) { Ok "$bin already installed ($why)"; return }
    if ($Check) { Warn "$bin is missing ($why)"; return }
    if (Have 'cargo-binstall') {
        cargo binstall -y --no-confirm $crate 2>$null | Out-Null
        if (Have $bin) { Ok "$bin installed ($why)"; return }
        Warn "binstall failed for $crate, falling back to a source build"
    }
    Write-Host "  building $crate from source, this can take a few minutes ..."
    cargo install --locked $crate 2>$null | Out-Null
    if (Have $bin) { Ok "$bin installed ($why)" } else { Bad "could not install $crate" }
}

if (Have 'cargo') {
    if (-not (Have 'cargo-binstall') -and -not $Check) {
        Write-Host "  installing cargo-binstall (makes everything below much faster) ..."
        cargo install cargo-binstall --locked 2>$null | Out-Null
        if (Have 'cargo-binstall') { Ok "cargo-binstall" } else { Warn "cargo-binstall unavailable; tools will build from source" }
    }
    Install-Tool 'cargo-nextest' 'cargo-nextest' 'better test runner for the httpmock integration tests'
    Install-Tool 'cargo-audit'   'cargo-audit'   'RUSTSEC advisories, matches the CI audit job'
    Install-Tool 'cargo-deny'    'cargo-deny'    'licence and advisory policy'
    Install-Tool 'bacon'         'bacon'         'background clippy while an agent edits'
    Install-Tool 'typos'         'typos-cli'     'typo check for SPEC.md and README.md'
}
else { Bad "cargo not available; skipping cargo tools" }

# ---------------------------------------------------------------------------
Say "4. VS Code extensions (Windows side)"

$exts = @(
    'rust-lang.rust-analyzer',
    'ms-vscode.powershell',
    'ms-vscode.cpptools',
    'ms-vscode.hexeditor',
    'ms-vscode-remote.remote-wsl',
    'tamasfe.even-better-toml',
    'fill-labs.dependi',
    'usernamehw.errorlens',
    'github.vscode-github-actions',
    'github.vscode-pull-request-github',
    'redhat.vscode-yaml',
    'eamodio.gitlens',
    'gruntfuggly.todo-tree',
    'streetsidesoftware.code-spell-checker',
    'bierner.markdown-mermaid'
)

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
            code --install-extension $e --force 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { Ok "$e installed" }
            else { Warn "could not install $e (check the name in the Extensions view)" }
        }
    }
}

# ---------------------------------------------------------------------------
Say "5. Agent CLIs"

if (Have 'claude') { Ok "claude found" } else { Warn "claude CLI not found. Install it, then run 'claude' once to sign in." }
if (Have 'codex')  { Ok "codex found" }  else { Warn "codex CLI not found. Install it, then run 'codex' once to sign in." }

$codexDir = Join-Path $env:USERPROFILE '.codex'
$codexCfg = Join-Path $codexDir 'config.toml'
if (-not $Check -and -not (Test-Path $codexCfg)) {
    New-Item -ItemType Directory -Force -Path $codexDir | Out-Null
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
'@ | Set-Content -Path $codexCfg -Encoding UTF8
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
        claude mcp add --transport http --scope user context7 https://mcp.context7.com/mcp 2>$null | Out-Null
        Ok "claude: context7 added"
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
'@ | Add-Content -Path $codexCfg -Encoding UTF8
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
    New-Item -ItemType Directory -Force -Path $ccDir | Out-Null
    @'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": [
      "Bash(cargo fmt *)",
      "Bash(cargo tree *)",
      "Bash(cargo metadata *)",
      "Bash(rustup show *)"
    ],
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
'@ | Set-Content -Path $ccSettings -Encoding UTF8
    Ok "wrote $ccSettings"
}

# ---------------------------------------------------------------------------
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
    if (Have 'rustup') {
        $components = (rustup component list --installed 2>$null | Out-String)
        if ($components -match 'rustfmt' -and $components -match 'clippy') { Ok "rustfmt and clippy installed" }
        else { Warn "rustfmt or clippy missing" }
    }
    if (Have 'code') {
        $installed = @(code --list-extensions 2>$null)
        if ($installed -contains 'ms-vscode-remote.remote-wsl') { Ok "VS Code Remote - WSL extension installed" }
        else { Warn "VS Code Remote - WSL extension missing" }
    }
    if (Test-Path $codexCfg) { Ok "Codex user configuration exists" } else { Warn "Codex user configuration missing" }
    if (Test-Path $ccSettings) { Ok "Claude user settings exist" } else { Warn "Claude user settings missing" }
    Write-Host "  Doctor does not verify VS Code profile names or agent sign-in state; see doctor/README.md." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
Say "Summary"
if ($script:Failures -eq 0) { Write-Host "  No failures." }
else { Write-Host "  $($script:Failures) problem(s) above need attention." -ForegroundColor Red }

Write-Host @'

  Still to do by hand (these cannot be scripted):
    1. Run 'claude' and 'codex' once each and sign in.
    2. Add plugins or skills only when a real project workflow requires them.
       They are optional and expand the tools an agent can use.
    3. In VS Code settings (user scope, not workspace):
         Claude Code > Initial Permission Mode  ->  plan
         Claude Code > Preferred Location       ->  sidebar
    4. Create the four Rust and General profiles from profiles/, then adjust only
       personal preferences. Keep exported profiles in a private backup.
    5. Clone Nomad-Launcher to C:\src\Nomad-Launcher.
    6. Install the WSL side: run bootstrap-wsl.sh inside your Fedora shell.
    7. Authenticate GitHub CLI when you need GitHub access:
         gh auth login --hostname github.com --git-protocol https --web
       Then launch Codex with helpers\codex-with-github-mcp.ps1. The helper
       exposes the token only to that Codex process.
       Claude's PAT-backed GitHub MCP is not configured automatically.
    8. Follow START-HERE.md for the two existing repositories or NEW-PROJECT.md
       for a new project.

'@

exit $script:Failures
