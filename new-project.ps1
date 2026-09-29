<#
    new-project.ps1 : start a new repository from the toolkit's foundation templates

        powershell -NoProfile -File .\new-project.ps1                  # asks what it needs
        powershell -NoProfile -File .\new-project.ps1 -Name my-tool -WindowsNative yes -LinuxTarget no
        powershell -NoProfile -File .\new-project.ps1 -Name my-tool -Environment Windows -Stack Rust

    -Name            repository directory name (letters, digits, . _ -)
    -Parent          where to create it (default: %USERPROFILE%\src)
    -Environment     Windows or Linux; skips the questions
    -WindowsNative   yes/no: builds or runs as a native Windows program?
    -LinuxTarget     yes/no: runs on or deploys to Linux?
    -Stack           None, Rust or Python: pre-fill the gate with that stack's usual commands
    -NoClaude        do not create CLAUDE.md

    Linux projects are created inside WSL (or on a Linux machine) with new-project.sh;
    this script prints the exact command. It creates files and runs 'git init' only in a
    new or empty directory and never commits. Undecided charter fields stay as visible
    {{...}} placeholders.
#>
[CmdletBinding()]
param(
    [string]$Name,
    [string]$Parent,
    [ValidateSet('', 'Windows', 'Linux')][string]$Environment = '',
    [ValidateSet('', 'yes', 'no', 'y', 'n')][string]$WindowsNative = '',
    [ValidateSet('', 'yes', 'no', 'y', 'n')][string]$LinuxTarget = '',
    [ValidateSet('None', 'Rust', 'Python')][string]$Stack = 'None',
    [switch]$NoClaude
)

$ErrorActionPreference = 'Stop'
$templates = Join-Path (Join-Path $PSScriptRoot 'templates') 'foundation'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Stop-NewProject ([string]$Message) {
    Write-Host "new-project: $Message" -ForegroundColor Red
    exit 1
}
function Read-Answer ([string]$Label, [string]$Question) {
    if (-not [Environment]::UserInteractive -or [Console]::IsInputRedirected) {
        Stop-NewProject "missing -$Label; pass it as a parameter"
    }
    return (Read-Host $Question).Trim()
}
function ConvertTo-YesNo ([string]$Label, [string]$Answer) {
    switch -Regex ($Answer.ToLowerInvariant()) {
        '^(y|yes)$' { return 'yes' }
        '^(n|no)$' { return 'no' }
        default { Stop-NewProject "answer yes or no for -$Label (got '$Answer')" }
    }
}
function ConvertTo-WslPath ([string]$WindowsPath) {
    if ($WindowsPath -match '^([A-Za-z]):\\(.*)$') {
        return '/mnt/' + $Matches[1].ToLowerInvariant() + '/' + ($Matches[2] -replace '\\', '/')
    }
    return $WindowsPath
}

if (-not $Name) { $Name = Read-Answer 'Name' 'Repository name (for example my-tool)' }
if ($Name -notmatch '^[A-Za-z0-9_-][A-Za-z0-9._-]*$') {
    Stop-NewProject "name must use letters, digits, '.', '_' or '-', and not start with '.'"
}

# --- Choose the environment -------------------------------------------------
$reason = ''
if ($Environment) { $reason = 'chosen explicitly' }
else {
    if (-not $WindowsNative) {
        $WindowsNative = Read-Answer 'WindowsNative' 'Will it build or run as a native Windows program (Windows APIs, .exe, MSVC, Windows-only SDKs or hardware)? [yes/no]'
    }
    $WindowsNative = ConvertTo-YesNo 'WindowsNative' $WindowsNative
    if (-not $LinuxTarget) {
        $LinuxTarget = Read-Answer 'LinuxTarget' 'Will it run on or deploy to Linux (web server, PHP/WordPress, containers, Linux services or tools)? [yes/no]'
    }
    $LinuxTarget = ConvertTo-YesNo 'LinuxTarget' $LinuxTarget
    switch ("$WindowsNative/$LinuxTarget") {
        'yes/no' { $Environment = 'Windows'; $reason = 'it builds or runs as a native Windows program' }
        'no/yes' { $Environment = 'Linux'; $reason = 'it runs on or deploys to Linux' }
        'no/no' {
            $Environment = 'Windows'
            $reason = 'no platform tie was identified, so it starts where it is being created; revisit if a dependency requires Linux'
        }
        'yes/yes' {
            Write-Host 'It targets both Windows and Linux. Pick one canonical development side;'
            Write-Host 'the other becomes a CI or compatibility target.'
            $Environment = Read-Answer 'Environment' 'Canonical side [Windows/Linux]'
            if (@('Windows', 'Linux') -notcontains $Environment) { Stop-NewProject 'environment must be Windows or Linux' }
            $reason = "cross-platform; $Environment is canonical and the other platform must be covered by CI"
        }
    }
}

if ($Environment -eq 'Linux') {
    $stackOption = if ($Stack -ne 'None') { ' --stack ' + $Stack.ToLowerInvariant() } else { '' }
    Write-Host "Recommended environment: Linux, because $reason."
    Write-Host 'On this Windows machine that means WSL (bootstrap-windows.ps1 -Wsl sets it up).'
    Write-Host 'Open your WSL terminal and run:'
    Write-Host ("  bash '" + (ConvertTo-WslPath $PSScriptRoot) + "/new-project.sh' --name $Name --environment linux$stackOption")
    Write-Host 'Nothing was created.'
    exit 3
}

if (-not $Parent) {
    $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    $Parent = Join-Path $homeDir 'src'
}
$Parent = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Parent)
$target = Join-Path $Parent $Name
if (Test-Path -LiteralPath $target) {
    $item = Get-Item -LiteralPath $target -Force
    if (-not $item.PSIsContainer -or @(Get-ChildItem -LiteralPath $target -Force).Count -gt 0) {
        Stop-NewProject "$target already exists and is not an empty directory; nothing was changed"
    }
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Stop-NewProject 'git is required; run bootstrap-windows.ps1 -InstallMissing first' }
foreach ($file in @('PROJECT-CHARTER.md.template', 'AGENTS.md.template', 'CLAUDE.md.template', 'check.ps1.template',
                    'README.md.template', 'gitattributes.template', 'gitignore.template', 'editorconfig.template')) {
    if (-not (Test-Path -LiteralPath (Join-Path $templates $file))) { Stop-NewProject "toolkit template missing: $file" }
}

$gate = 'powershell -NoProfile -File scripts/check.ps1'
$commands = @{}
$ignoreExtra = ''
switch ($Stack) {
    'Rust' {
        $commands = @{ FORMAT_COMMAND = 'cargo fmt --all -- --check'
                       LINT_COMMAND = 'cargo clippy --workspace --all-targets -- -D warnings'
                       TEST_COMMAND = 'cargo test --workspace' }
        $ignoreExtra = "`n# Rust build output`n/target/`n"
    }
    'Python' {
        $commands = @{ FORMAT_COMMAND = 'uv run ruff format --check .'
                       LINT_COMMAND = 'uv run ruff check .'
                       TEST_COMMAND = 'uv run pytest -q' }
        $ignoreExtra = "`n# Python environments and caches`n.venv/`n__pycache__/`n.pytest_cache/`n.ruff_cache/`n.mypy_cache/`n"
    }
}

# Replace {{KEY}} literally and write LF text without a byte-order mark.
function Write-FromTemplate ([string]$Template, [string]$Output, [hashtable]$Values) {
    $text = [IO.File]::ReadAllText((Join-Path $templates $Template)) -replace "`r`n", "`n"
    foreach ($key in $Values.Keys) { $text = $text.Replace('{{' + $key + '}}', [string]$Values[$key]) }
    [IO.File]::WriteAllText($Output, $text, $utf8NoBom)
}

$null = New-Item -ItemType Directory -Force -Path (Join-Path $target 'scripts')
Write-FromTemplate 'README.md.template' (Join-Path $target 'README.md') @{ PROJECT_NAME = $Name; ENVIRONMENT = 'Windows'; GATE_COMMAND = $gate }
Write-FromTemplate 'PROJECT-CHARTER.md.template' (Join-Path $target 'PROJECT-CHARTER.md') @{
    PROJECT_NAME = $Name
    'IDEA | PROTOTYPE | ACTIVE | MAINTENANCE' = 'IDEA'
    'WINDOWS | LINUX | MACOS | WSL | UNDECIDED' = 'WINDOWS'
    WHY_THIS_ENVIRONMENT = $reason
    GATE_COMMAND = $gate
}
Write-FromTemplate 'AGENTS.md.template' (Join-Path $target 'AGENTS.md') @{ PROJECT_NAME = $Name; GATE_COMMAND = $gate }
if (-not $NoClaude) { Write-FromTemplate 'CLAUDE.md.template' (Join-Path $target 'CLAUDE.md') @{} }
Write-FromTemplate 'check.ps1.template' (Join-Path (Join-Path $target 'scripts') 'check.ps1') $commands
Write-FromTemplate 'gitattributes.template' (Join-Path $target '.gitattributes') @{}
Write-FromTemplate 'gitignore.template' (Join-Path $target '.gitignore') @{}
if ($ignoreExtra) { [IO.File]::AppendAllText((Join-Path $target '.gitignore'), $ignoreExtra, $utf8NoBom) }
Write-FromTemplate 'editorconfig.template' (Join-Path $target '.editorconfig') @{}

git init --quiet -- $target
if ($LASTEXITCODE -ne 0) { Stop-NewProject "git init failed in $target" }
git -C $target symbolic-ref HEAD refs/heads/main
if ($LASTEXITCODE -ne 0) { Stop-NewProject "could not set the initial branch to main in $target" }

Write-Host ''
Write-Host "Created $target"
Write-Host "Environment: Windows, because $reason."
Write-Host ''
Write-Host 'Next steps:'
Write-Host "  1. cd $target"
Write-Host '  2. Fill in PROJECT-CHARTER.md. Leave unknown answers as visible open decisions.'
switch ($Stack) {
    'Python' { Write-Host '  3. uv init --app .   then   uv add --dev ruff pytest   (review the generated files)' }
    'Rust' { Write-Host '  3. cargo init   (review the generated manifest and add rust-toolchain.toml deliberately)' }
    default { Write-Host '  3. Choose a stack, then replace the placeholders in scripts/check.ps1 with its commands.' }
}
Write-Host '  4. Replace the remaining {{...}} placeholders in AGENTS.md; the gate refuses to run'
Write-Host '     while its own placeholders remain.'
Write-Host "  5. Run $gate, review 'git status --short --untracked-files=all', then make the first commit."
Write-Host '  6. Create a private GitHub repository when ready:'
Write-Host "       gh repo create $Name --private --source . --remote origin --push"
Write-Host 'See NEW-PROJECT.md in the toolkit for the full checklist.'
exit 0
