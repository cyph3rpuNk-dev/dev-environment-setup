# No installers, credentials, browser launches, or real user configuration.
# The mocks below reproduce the real commands' signatures, share state with helper
# scripts through globals, and seed variables that extracted bootstrap blocks read.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Mocks share state with helper scripts run in this session.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Mocks keep the signatures of the commands they replace.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables are read by bootstrap blocks extracted from the AST.')]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$shellExe = (Get-Process -Id $PID).Path
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('dev-setup-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $testRoot
$utf8 = New-Object Text.UTF8Encoding($false)
function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    Write-Host "PASS: $Message"
}
function Parse([string]$Path) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors) { throw ($errors.Message -join '; ') }
    return $ast
}
try {
    & $shellExe -NoProfile -File "$root/tests/test-native-github.ps1"
    Assert ($LASTEXITCODE -eq 0) 'Native GitHub CLI regression suite'
    $template = Get-Content -Raw -Encoding UTF8 "$root/templates/foundation/check.ps1.template"
    $null = New-Item -ItemType Directory -Path "$testRoot/scripts"
    $gate = $template.Replace('{{FORMAT_COMMAND}}', "Write-Error 'simulated failure'").Replace('{{LINT_COMMAND}}', '& missing-audit-command-747').Replace('{{TEST_COMMAND}}', "'continued' | Set-Content continued.txt")
    [IO.File]::WriteAllText("$testRoot/scripts/check.ps1", $gate, $utf8)
    Push-Location -LiteralPath $testRoot
    try {
        & $shellExe -NoProfile -File "$testRoot/scripts/check.ps1"
        Assert ($LASTEXITCODE -eq 2) 'Gate counts PowerShell errors and missing commands'
        Assert (Test-Path "$testRoot/continued.txt") 'Gate continues after failures and runs from repository root'
    } finally { Pop-Location }
    $gate = $template.Replace('{{FORMAT_COMMAND}}', '& $env:TEST_POWERSHELL -NoProfile -Command "exit 9"').Replace('{{LINT_COMMAND}}', "Write-Output 'successful cmdlet'").Replace('{{TEST_COMMAND}}', "Write-Output 'successful test'")
    [IO.File]::WriteAllText("$testRoot/scripts/check.ps1", $gate, $utf8)
    $env:TEST_POWERSHELL = $shellExe
    & $shellExe -NoProfile -File "$testRoot/scripts/check.ps1"
    Assert ($LASTEXITCODE -eq 1) 'Gate counts native failure without contaminating later cmdlets'
    [IO.File]::WriteAllText("$testRoot/scripts/check.ps1", $template, $utf8)
    $output = & $shellExe -NoProfile -File "$testRoot/scripts/check.ps1" | Out-String
    Assert ($LASTEXITCODE -eq 1 -and $output -match 'placeholders') 'Unfilled PowerShell gate refuses to report success'
    $gate = $template.Replace('{{FORMAT_COMMAND}}', "Write-Output 'formatted'").Replace('{{LINT_COMMAND}}', "Write-Output 'linted'")
    [IO.File]::WriteAllText("$testRoot/scripts/check.ps1", $gate, $utf8)
    $output = & $shellExe -NoProfile -File "$testRoot/scripts/check.ps1" | Out-String
    Assert ($LASTEXITCODE -eq 1 -and $output -match 'placeholders') 'PowerShell gate with one placeholder left refuses to run'
    $gate = $template.Replace('{{FORMAT_COMMAND}}', "Write-Output 'formatted'").Replace('{{LINT_COMMAND}}', "Write-Output 'linted'").Replace('{{TEST_COMMAND}}', "Write-Output '{{TEMPLATE_NAME}}'")
    [IO.File]::WriteAllText("$testRoot/scripts/check.ps1", $gate, $utf8)
    $output = & $shellExe -NoProfile -File "$testRoot/scripts/check.ps1" | Out-String
    Assert ($LASTEXITCODE -eq 0 -and $output -match '\{\{TEMPLATE_NAME\}\}') 'PowerShell gate allows other {{...}} text in a filled command'
    $gate = $template.Replace('{{FORMAT_COMMAND}}', "Write-Output 'formatted'").Replace('{{LINT_COMMAND}}', "Write-Output 'linted'") -replace "(?m)^Step 'test'.*\r?\n", ''
    [IO.File]::WriteAllText("$testRoot/scripts/check.ps1", $gate, $utf8)
    & $shellExe -NoProfile -File "$testRoot/scripts/check.ps1" | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'PowerShell gate runs with a deleted step'
    $gate = $template -replace "(?m)^Step .*\r?\n", ''
    [IO.File]::WriteAllText("$testRoot/scripts/check.ps1", $gate, $utf8)
    $output = & $shellExe -NoProfile -File "$testRoot/scripts/check.ps1" | Out-String
    Assert ($LASTEXITCODE -eq 1 -and $output -match 'no steps') 'PowerShell gate with every step deleted refuses to report success'

    # A clean checkout has no ordinary `git diff`, so exercise the real toolkit
    # gate in a committed fixture containing trailing whitespace.
    $whitespaceRoot = Join-Path $testRoot 'committed-whitespace'
    foreach ($directory in @('scripts', 'helpers', 'tests', 'profiles', 'templates/foundation')) {
        $null = New-Item -ItemType Directory -Path (Join-Path $whitespaceRoot $directory) -Force
    }
    Copy-Item -LiteralPath "$root/scripts/check.ps1" -Destination "$whitespaceRoot/scripts/check.ps1"
    Copy-Item -LiteralPath "$root/PSScriptAnalyzerSettings.psd1" -Destination $whitespaceRoot
    foreach ($file in @('bootstrap.ps1', 'helpers/helper.ps1')) {
        [IO.File]::WriteAllText((Join-Path $whitespaceRoot $file), "# syntax fixture`n", $utf8)
    }
    [IO.File]::WriteAllText("$whitespaceRoot/tests/test-powershell.ps1", "exit 0`n", $utf8)
    foreach ($file in @('bootstrap.sh', 'helpers/helper.sh', 'tests/test-bash.sh', 'templates/foundation/check.sh.template')) {
        [IO.File]::WriteAllText((Join-Path $whitespaceRoot $file), "#!/usr/bin/env bash`nexit 0`n", $utf8)
    }
    [IO.File]::WriteAllText("$whitespaceRoot/profiles/fixture.jsonc", "{}`n", $utf8)
    [IO.File]::WriteAllText("$whitespaceRoot/trailing.txt", "committed whitespace  `n", $utf8)
    Push-Location -LiteralPath $whitespaceRoot
    try {
        git init --quiet
        $null = New-Item -ItemType Directory -Path "$whitespaceRoot/no-hooks"
        git config core.autocrlf false
        git config core.hooksPath "$whitespaceRoot/no-hooks"
        git config commit.gpgsign false
        git config user.name fixture
        git config user.email fixture@example.invalid
        git add --all
        git commit --quiet -m fixture
        & $shellExe -NoProfile -File "$whitespaceRoot/scripts/check.ps1"
        Assert ($LASTEXITCODE -eq 1) 'Toolkit gate rejects committed whitespace in a clean checkout'
        Assert ([string]::IsNullOrWhiteSpace((git status --porcelain))) 'Whitespace fixture remains clean after validation'
    }
    finally { Pop-Location }

    # Run the full Windows bootstrap in a child shell with every external tool
    # mocked and a disposable user profile. No real installation or auth occurs.
    $profileHarness = @'
param([string]$Source, [string]$Fixture, [string]$SelectedStack, [switch]$Agents, [switch]$Inspect, [switch]$UseWsl, [switch]$Diagnose)
$env:USERPROFILE = $Fixture
$global:Events = New-Object 'System.Collections.Generic.List[string]'
function Record([string]$Name, $Arguments) {
    $global:Events.Add($Name + ' ' + ($Arguments -join ' '))
    $global:LASTEXITCODE = 0
}
function Get-Command {
    param($Name, $ErrorAction)
    if ($Name -eq 'rustup' -and $env:TEST_NO_RUSTUP -eq '1') { return }
    if ($Name -in @('rustc', 'cargo') -and $env:TEST_NO_RUST -eq '1') { return }
    if ($Name -eq 'gh' -and $env:TEST_NO_GH -eq '1') { return }
    Microsoft.PowerShell.Core\Get-Command $Name -ErrorAction SilentlyContinue
}
function code { Record 'code' $args }
function Get-CimInstance {
    # Machine diagnostics are mocked too: tests must never inspect real hardware.
    [pscustomobject]@{ BuildNumber = 'fixture'; TotalPhysicalMemory = 32GB; HypervisorPresent = $true; VirtualizationFirmwareEnabled = $true }
}
function Get-PSDrive { [pscustomobject]@{ Free = 100GB } }
function git {
    Record 'git' $args
    # Only identity lookups answer, from the test's environment.
    if ($args.Count -ge 4 -and $args[0] -eq 'config' -and $args[2] -eq '--get') {
        if ($args[3] -eq 'user.name') { $env:TEST_GIT_NAME } elseif ($args[3] -eq 'user.email') { $env:TEST_GIT_EMAIL }
    }
}
function gh { Record 'gh' $args }
function pwsh { Record 'pwsh' $args }
function rustup { Record 'rustup' $args; 'stable-x86_64-pc-windows-msvc rustfmt clippy' }
function rustc { Record 'rustc' $args; "rustc fixture`nhost: x86_64-pc-windows-msvc" }
function cargo { Record 'cargo' $args }
function cargo-binstall { Record 'cargo-binstall' $args }
function cargo-nextest {}
function cargo-audit {}
function cargo-deny {}
function bacon {}
function typos {}
function uv { Record 'uv' $args }
function claude { Record 'claude' $args; 'context7 github' }
function codex { Record 'codex' $args }
function wsl { Record 'wsl' $args }
function winget { throw 'Unexpected installer' }
& $Source -Stack $SelectedStack -ConfigureAgents:$Agents -Check:$Inspect -Wsl:$UseWsl -Doctor:$Diagnose
$result = $LASTEXITCODE
[IO.File]::WriteAllLines((Join-Path $Fixture 'events.txt'), $global:Events)
exit $result
'@
    [IO.File]::WriteAllText("$testRoot/profiles.ps1", $profileHarness, $utf8)
    # 'Rust,Python' is one string, exactly as 'powershell -File' passes it.
    foreach ($selection in @('Base', 'Rust', 'Python', 'Rust,Python')) {
        $fixture = Join-Path $testRoot ("profile-" + ($selection -replace ',', '-'))
        $null = New-Item -ItemType Directory -Path $fixture
        & $shellExe -NoProfile -File "$testRoot/profiles.ps1" "$root/bootstrap-windows.ps1" $fixture $selection
        Assert ($LASTEXITCODE -eq 0) "Windows $selection profile provisions with mocks"
        $events = Get-Content -Raw "$fixture/events.txt"
        Assert (-not (Test-Path "$fixture/.codex") -and -not (Test-Path "$fixture/.claude")) 'Agent settings require explicit selection'
        Assert ($events -match 'gh auth status') 'GitHub authentication is checked without agent configuration'
        if ($selection -match 'Rust') {
            Assert ($events -match 'cargo build' -and $events -match 'rust-analyzer') "Windows $selection selection exercises linker and extensions"
        } else {
            Assert ($events -notmatch 'rustup|rustc|cargo|rust-analyzer') "Windows $selection excludes Rust"
        }
        if ($selection -match 'Python') {
            Assert ($events -match 'ms-python.python' -and $events -match 'charliermarsh.ruff') "Windows $selection adds Python extensions"
        } else {
            Assert ($events -notmatch 'ms-python|ruff') "Windows $selection excludes Python"
        }
        Assert ($events -notmatch 'claude|codex|remote-wsl|wsl ') "Windows $selection excludes agents and WSL unless selected"
        & $shellExe -NoProfile -File "$testRoot/profiles.ps1" "$root/bootstrap-windows.ps1" $fixture $selection -Agents -Inspect
        Assert ($LASTEXITCODE -eq 0) "Windows $selection check completes"
        $events = Get-Content -Raw "$fixture/events.txt"
        Assert ($events -notmatch 'cargo (init|build|install)|rustup component add|code --install|claude mcp add') 'Windows checks never provision selected features'
        Assert (-not (Test-Path "$fixture/.codex") -and -not (Test-Path "$fixture/.claude")) 'Windows checks do not create selected agent settings'
    }

    $fixture = Join-Path $testRoot 'profile-no-rustup'
    $null = New-Item -ItemType Directory -Path $fixture
    $savedNoRustup = $env:TEST_NO_RUSTUP
    try {
        $env:TEST_NO_RUSTUP = '1'
        $output = & $shellExe -NoProfile -File "$testRoot/profiles.ps1" "$root/bootstrap-windows.ps1" $fixture 'Rust' -Inspect | Out-String
        Assert ($LASTEXITCODE -eq 1 -and ([regex]::Matches($output, 'FAIL.*Rust toolchain installer')).Count -eq 1) 'Missing rustup counts as one required failure'
        # With no Rust at all (no rustc or cargo either), the cause is still counted once.
        $env:TEST_NO_RUST = '1'
        $output = & $shellExe -NoProfile -File "$testRoot/profiles.ps1" "$root/bootstrap-windows.ps1" $fixture 'Rust' -Inspect | Out-String
        Assert ($LASTEXITCODE -eq 1 -and ([regex]::Matches($output, 'FAIL')).Count -eq 1 -and $output -match 'cargo tools skipped until rustup is installed') 'Missing Rust toolchain counts as one required failure'
    } finally { $env:TEST_NO_RUSTUP = $savedNoRustup; $env:TEST_NO_RUST = $null }

    # GitHub CLI is required on Windows too, as on Linux and macOS: one failure, not a warning.
    $fixture = Join-Path $testRoot 'profile-no-gh'
    $null = New-Item -ItemType Directory -Path $fixture
    try {
        $env:TEST_NO_GH = '1'
        $output = & $shellExe -NoProfile -File "$testRoot/profiles.ps1" "$root/bootstrap-windows.ps1" $fixture 'Base' -Inspect | Out-String
        Assert ($LASTEXITCODE -eq 1 -and ([regex]::Matches($output, 'FAIL')).Count -eq 1 -and $output -match 'FAIL.*GitHub CLI.*is missing') 'Missing GitHub CLI is one required failure'
    } finally { $env:TEST_NO_GH = $null }

    # A helper that refuses to load (as a file blocked after a ZIP download does) is
    # named as the problem, never misreported as a GitHub sign-in failure.
    $blockedRoot = Join-Path $testRoot 'blocked-toolkit'
    $null = New-Item -ItemType Directory -Path (Join-Path $blockedRoot 'helpers')
    Copy-Item -LiteralPath "$root/bootstrap-windows.ps1" -Destination $blockedRoot
    Copy-Item -LiteralPath "$root/helpers/codex-with-github-mcp.ps1" -Destination (Join-Path $blockedRoot 'helpers')
    [IO.File]::WriteAllText((Join-Path $blockedRoot 'helpers/github-auth.ps1'), "throw 'simulated blocked file'`n", $utf8)
    $fixture = Join-Path $testRoot 'profile-blocked-helper'
    $null = New-Item -ItemType Directory -Path $fixture
    $output = & $shellExe -NoProfile -File "$testRoot/profiles.ps1" (Join-Path $blockedRoot 'bootstrap-windows.ps1') $fixture 'Base' -Inspect | Out-String
    Assert ($LASTEXITCODE -eq 1 -and $output -match 'GitHub sign-in was not checked' -and $output -match 'simulated blocked file' -and $output -match 'Unblock-File -LiteralPath' -and $output -notmatch 'GitHub CLI is not authenticated') 'Unloadable GitHub helper is reported by name'
    try { & (Join-Path $blockedRoot 'helpers/codex-with-github-mcp.ps1'); throw 'Expected helper load failure' }
    catch { Assert ($_.ToString() -match 'Could not load .*github-auth\.ps1' -and $_.ToString() -match 'Unblock-File') 'Codex launcher names an unloadable GitHub helper' }

    $fixture = Join-Path $testRoot 'profile-invalid'
    $null = New-Item -ItemType Directory -Path $fixture
    & $shellExe -NoProfile -File "$testRoot/profiles.ps1" "$root/bootstrap-windows.ps1" $fixture 'Rust,Go'
    Assert ($LASTEXITCODE -eq 1 -and -not (Get-Content -Raw "$fixture/events.txt")) 'Unknown stack fails before any work'

    # Agent defaults: written once, without a byte-order mark, and never rewritten.
    $fixture = Join-Path $testRoot 'profile-agents'
    $null = New-Item -ItemType Directory -Path $fixture
    & $shellExe -NoProfile -File "$testRoot/profiles.ps1" "$root/bootstrap-windows.ps1" $fixture 'Base' -Agents
    Assert ($LASTEXITCODE -eq 0) 'Windows agent configuration provisions with mocks'
    $written = @("$fixture/.codex/config.toml", "$fixture/.claude/settings.json")
    foreach ($file in $written) {
        $bytes = [IO.File]::ReadAllBytes($file)
        Assert (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) "$(Split-Path -Leaf $file) has no byte-order mark"
    }
    $null = Get-Content -Raw "$fixture/.claude/settings.json" | ConvertFrom-Json
    $before = @($written | ForEach-Object { [IO.File]::ReadAllText($_) })
    & $shellExe -NoProfile -File "$testRoot/profiles.ps1" "$root/bootstrap-windows.ps1" $fixture 'Base' -Agents
    $after = @($written | ForEach-Object { [IO.File]::ReadAllText($_) })
    Assert ($before[0] -eq $after[0] -and $before[1] -eq $after[1]) 'Agent configuration is unchanged on rerun'
    Assert (([regex]::Matches($after[0], '(?m)^\[mcp_servers\.github\]')).Count -eq 1) 'GitHub MCP table is not duplicated'
    foreach ($existing in @('# [mcp_servers.github] is only a comment', '[mcp_servers."github"]')) {
        [IO.File]::WriteAllText($written[0], $existing, $utf8)
        & $shellExe -NoProfile -File "$testRoot/profiles.ps1" "$root/bootstrap-windows.ps1" $fixture 'Base' -Agents | Out-Null
        Assert ([IO.File]::ReadAllText($written[0]) -ceq $existing) 'Existing TOML remains byte-for-byte unchanged regardless of table spelling'
    }

    # -Wsl adds the Remote-WSL extension; check mode never enables WSL.
    $fixture = Join-Path $testRoot 'profile-wsl'
    $null = New-Item -ItemType Directory -Path $fixture
    & $shellExe -NoProfile -File "$testRoot/profiles.ps1" "$root/bootstrap-windows.ps1" $fixture 'Base' -UseWsl
    $events = Get-Content -Raw "$fixture/events.txt"
    Assert ($events -match 'remote-wsl' -and $events -notmatch 'wsl --install') 'WSL selection adds its extension and never enables WSL without -InstallMissing'

    # Doctor reports whether the Git identity is set, never the values, and writes nothing.
    $fixture = Join-Path $testRoot 'profile-doctor'
    $null = New-Item -ItemType Directory -Path $fixture
    $identityCases = @(
        @{ Name = ''; Email = ''; Expect = 'name or email is not set' },
        @{ Name = 'fixture'; Email = '1+Fixture@Users.Noreply.GitHub.com'; Expect = 'set \(GitHub private address\)' },
        @{ Name = 'fixture'; Email = 'someone@example.invalid'; Expect = 'not a GitHub private \(noreply\) address' }
    )
    try {
        foreach ($case in $identityCases) {
            $env:TEST_GIT_NAME = $case.Name; $env:TEST_GIT_EMAIL = $case.Email
            $output = & $shellExe -NoProfile -File "$testRoot/profiles.ps1" "$root/bootstrap-windows.ps1" $fixture 'Base' -Diagnose | Out-String
            $events = Get-Content -Raw "$fixture/events.txt"
            Assert ($output -match $case.Expect -and $output -cnotmatch 'Noreply|example\.invalid') "Windows doctor reports Git identity: $($case.Expect)"
            Assert ($events -notmatch 'git config --global user\.') 'Windows doctor never writes Git identity'
        }
    }
    finally { Remove-Item Env:\TEST_GIT_NAME, Env:\TEST_GIT_EMAIL -ErrorAction SilentlyContinue }

    # Helpers invoke these functions, so no real auth lookup or agent can run.
    function gh {
        $global:LASTEXITCODE = 0
        if ($global:TestOldGh -and $args -contains '--active') { $global:LASTEXITCODE = 1; 'unknown flag: --active'; return }
        if ($args[1] -eq 'token') {
            if ($global:TestTokenFailure) { $global:LASTEXITCODE = 1; return }
            if (-not $global:TestEmptyToken) { 'fake-test-token' }
        }
    }
    function codex {
        Assert ($env:GITHUB_MCP_PAT -eq 'fake-test-token') 'Codex child sees fake token'
        if ($global:TestLaunchFailure) { throw 'simulated launch failure' }
        $global:LASTEXITCODE = 7
    }
    $previousToken = $env:GITHUB_MCP_PAT
    try {
        foreach ($initial in @($null, 'fake-existing-token')) {
            $env:GITHUB_MCP_PAT = $initial
            & "$root/helpers/codex-with-github-mcp.ps1"
            Assert ($LASTEXITCODE -eq 7) 'Credential helper propagates Codex exit code'
            Assert ($env:GITHUB_MCP_PAT -eq $initial) 'Credential helper restores caller environment'
        }
        $global:TestOldGh = $true
        & "$root/helpers/codex-with-github-mcp.ps1"
        Assert ($LASTEXITCODE -eq 7 -and $env:GITHUB_MCP_PAT -eq 'fake-existing-token') 'Older GitHub CLI fallback launches and restores the environment'
        $global:TestOldGh = $false
        $global:TestLaunchFailure = $true
        try { & "$root/helpers/codex-with-github-mcp.ps1"; throw 'Expected launch failure' }
        catch { Assert ($_.ToString() -match 'simulated launch failure') 'Launch error propagates' }
        Assert ($env:GITHUB_MCP_PAT -eq 'fake-existing-token') 'Token restored after launch exception'
        $global:TestLaunchFailure = $false
        foreach ($scenario in 'TestEmptyToken', 'TestTokenFailure') {
            Set-Variable -Scope Global -Name $scenario -Value $true
            try { & "$root/helpers/codex-with-github-mcp.ps1"; throw 'Expected token rejection' }
            catch { Assert ($_.ToString() -match 'did not provide a token') "Helper rejects $scenario" }
            Set-Variable -Scope Global -Name $scenario -Value $false
        }
    } finally { $env:GITHUB_MCP_PAT = $previousToken }

    # Execute the real fixed bridge command with redirected stdin and a stubbed
    # Start-Process. Even a malicious URL must remain data.
    $bridge = Get-Content -Raw -Encoding UTF8 "$root/helpers/wslview.sh"
    $fixedCommand = [regex]::Match($bridge, "(?s)-Command '\r?\n(.*)\r?\n'\s*$").Groups[1].Value
    Assert (-not [string]::IsNullOrWhiteSpace($fixedCommand)) 'Bridge contains a fixed PowerShell command'
    $wrapper = 'function Start-Process { param($FilePath) [Console]::WriteLine("OPEN:" + $FilePath) }' + "`n" + $fixedCommand
    [IO.File]::WriteAllText("$testRoot/browser.ps1", $wrapper, $utf8)
    foreach ($url in @('https://example.invalid/a?x=1&y=2', "https://example.invalid/'; Write-Output 'INJECTED'; #")) {
        $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($url))
        $result = $encoded | & $shellExe -NoProfile -File "$testRoot/browser.ps1"
        Assert ($LASTEXITCODE -eq 0 -and @($result).Count -eq 1 -and $result -like 'OPEN:https://*') 'Bridge opens URL as data without executing injected commands'
    }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('file:///sensitive'))
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $encoded | & $shellExe -NoProfile -File "$testRoot/browser.ps1" 2>$null
    $ErrorActionPreference = $oldPreference
    Assert ($LASTEXITCODE -ne 0) 'Bridge rejects non-web URI schemes'

    # Run the actual linker-probe block with cargo mocked, never a real build.
    $ast = Parse "$root/bootstrap-windows.ps1"
    $probeAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.IfStatementAst] -and $node.Extent.Text.StartsWith("if ((Have 'cargo')") }, $true)
    function Have { return $true }
    function Ok { param($Message) }
    function Bad { param($Message) $script:probeErrors++ }
    function cargo {
        if ($args[0] -eq 'init') { $global:LASTEXITCODE = $script:initExit }
        elseif ($args[0] -eq 'build') { $script:buildCalls++; $script:buildArguments = @($args); $global:LASTEXITCODE = $script:buildExit }
        else { throw 'Unexpected cargo command' }
    }
    $Check = $false
    function rustc { $global:LASTEXITCODE = 0; 'host: x86_64-pc-windows-msvc' }
    foreach ($scenario in @(@(1, 0, 0, 1), @(0, 1, 1, 1), @(0, 0, 1, 0))) {
        $script:initExit = $scenario[0]; $script:buildExit = $scenario[1]
        $script:buildCalls = 0; $script:probeErrors = 0
        $before = (Get-Location).Path
        & ([scriptblock]::Create($probeAst.Extent.Text))
        Assert ($script:buildCalls -eq $scenario[2] -and $script:probeErrors -eq $scenario[3]) 'Linker probe checks initialization and build results'
        Assert ((Get-Location).Path -eq $before) 'Linker probe restores working directory'
    }
    # Only an MSVC toolchain may be reported as proving the MSVC linker.
    function Ok { param($Message) $script:okMessages += @($Message) }
    $script:initExit = 0; $script:buildExit = 0
    foreach ($msvc in @($true, $false)) {
        $script:fixtureHost = if ($msvc) { 'x86_64-pc-windows-msvc' } else { 'x86_64-pc-windows-gnu' }
        function rustc { $global:LASTEXITCODE = 0; "host: $script:fixtureHost" }
        # Deliberately seed the wrong value: the probe must derive it from rustc.
        $msvcHost = -not $msvc; $script:okMessages = @()
        & ([scriptblock]::Create($probeAst.Extent.Text))
        Assert (($script:okMessages -contains 'MSVC linker works') -eq $msvc) "Linker probe claims MSVC only for an MSVC toolchain (msvc=$msvc)"
        Assert (($script:buildArguments -join ' ') -eq "build --quiet --target $script:fixtureHost") 'Probe explicitly builds for the observed compiler host'
    }
    function rustc { $global:LASTEXITCODE = 1; 'host: x86_64-pc-windows-msvc' }
    $script:buildCalls = 0; $script:probeErrors = 0
    & ([scriptblock]::Create($probeAst.Extent.Text))
    Assert ($script:buildCalls -eq 0 -and $script:probeErrors -eq 1) 'Failed compiler inspection never runs a build or claims linker success'

    # Check the real winget and MCP branches, with commands replaced by stubs.
    $baseLoop = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.ForEachStatementAst] -and $node.Extent.Text.StartsWith('foreach ($t in $base)') }, $true)
    function Have { param($Name) return $Name -eq 'winget' }
    function Warn { param($Message) }
    function winget { $global:LASTEXITCODE = 23 }
    $base = @(@{ Cmd = 'missing-test-tool'; Winget = 'Fake.Package'; What = 'fixture' })
    $InstallMissing = $true; $Check = $false; $script:probeErrors = 0
    & ([scriptblock]::Create($baseLoop.Extent.Text))
    Assert ($script:probeErrors -eq 1) 'Failed winget install is recorded as failure'
    $mcpBlock = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.IfStatementAst] -and $node.Extent.Text.StartsWith("if (-not (Have 'claude'))") }, $true)
    function Have { return $true }
    function claude { $global:LASTEXITCODE = 23 }
    function Skip { param($Message) }
    $script:probeErrors = 0
    & ([scriptblock]::Create($mcpBlock.Extent.Text))
    Assert ($script:probeErrors -eq 1) 'Failed MCP install is recorded as failure'

    # WSL enablement decisions, run from the real block with every command stubbed.
    $wslBlock = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.IfStatementAst] -and $node.Extent.Text.StartsWith('if ($Wsl) {') -and $node.Extent.Text -match 'Get-WslDistribution' }, $true)
    Assert ($null -ne $wslBlock) 'WSL block located'
    function Say { param($Message) }
    function Ok { param($Message) }
    function Warn { param($Message) }
    function Bad { param($Message) $script:probeErrors++ }
    function ConvertTo-WslPath { param($Path) '/mnt/c/toolkit' }
    function wsl { $script:wslCalls += ($args -join ' '); $global:LASTEXITCODE = $script:wslExit }
    # Distros present | Check | InstallMissing | Admin | wsl exit | virtualisation | have wsl | failures | install call
    $cases = @(
        @(@('Ubuntu-24.04'), $false, $true, $false, 0, 'Hypervisor', $true, 0, $false),
        @(@(), $true, $false, $true, 0, 'Enabled', $true, 0, $false),
        @(@(), $false, $false, $true, 0, 'Enabled', $true, 0, $false),
        @(@(), $false, $true, $false, 0, 'Enabled', $true, 1, $false),
        @(@(), $false, $true, $true, 0, 'Enabled', $true, 0, $true),
        @(@(), $false, $true, $true, 5, 'Enabled', $true, 1, $true),
        @(@('FedoraLinux-44'), $true, $false, $false, 0, 'Disabled', $true, 1, $false),
        @(@(), $false, $true, $true, 0, 'Enabled', $false, 1, $false)
    )
    foreach ($case in $cases) {
        $script:caseDistros = $case[0]; $Check = $case[1]; $InstallMissing = $case[2]
        $script:caseAdmin = $case[3]; $script:wslExit = $case[4]; $script:caseVirt = $case[5]; $script:caseHaveWsl = $case[6]
        function Get-WslDistribution { return $script:caseDistros }
        function Test-Administrator { return $script:caseAdmin }
        function Get-VirtualizationState { return $script:caseVirt }
        function Have { param($Name) if ($Name -eq 'wsl') { return $script:caseHaveWsl } return $true }
        $Wsl = $true; $script:probeErrors = 0; $script:wslCalls = @()
        & ([scriptblock]::Create($wslBlock.Extent.Text))
        $installed = @($script:wslCalls | Where-Object { $_ -eq '--install --no-distribution' }).Count -eq 1
        Assert ($script:probeErrors -eq $case[7] -and $installed -eq $case[8]) ("WSL decision: distros=" + $case[0].Count + " check=" + $case[1] + " install=" + $case[2] + " admin=" + $case[3] + " exit=" + $case[4] + " virt=" + $case[5] + " wsl=" + $case[6])
    }

    # Distribution names are read from UTF-16 output; informational text is never a name.
    $listAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-WslDistribution' }, $true)
    . ([scriptblock]::Create($listAst.Extent.Text))
    function Have { return $true }
    function wsl { $global:LASTEXITCODE = $script:wslExit; $script:wslOutput }
    $script:wslExit = 0
    $script:wslOutput = @(("Ubuntu-24.04".ToCharArray() -join "`0"), 'FedoraLinux-44', 'Windows Subsystem for Linux has no installed distributions.')
    $names = @(Get-WslDistribution)
    Assert ($names.Count -eq 2 -and $names[0] -eq 'Ubuntu-24.04' -and $names[1] -eq 'FedoraLinux-44') 'WSL listing strips NULs and ignores messages'
    $script:wslExit = 1
    Assert (@(Get-WslDistribution).Count -eq 0) 'Failed WSL listing yields no distributions'
    Remove-Item Function:\wsl, Function:\Have

    # Scaffolder. Piped input keeps it non-interactive, so it can never wait for input.
    $np = Join-Path $testRoot 'np'
    '' | & $shellExe -NoProfile -File "$root/new-project.ps1" -Name WinTool -Parent $np -Environment Windows -Stack Rust | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'Scaffolder creates a Windows project'
    foreach ($file in @('README.md', 'PROJECT-CHARTER.md', 'AGENTS.md', 'CLAUDE.md', 'scripts/check.ps1', '.gitattributes', '.gitignore', '.editorconfig')) {
        $path = Join-Path (Join-Path $np 'WinTool') $file
        Assert (Test-Path -LiteralPath $path) "Scaffolder created $file"
        $bytes = [IO.File]::ReadAllBytes($path)
        Assert (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF) -and ($bytes -notcontains 13)) "$file is LF without a byte-order mark"
    }
    $project = Join-Path $np 'WinTool'
    Assert ((git -C $project symbolic-ref HEAD) -eq 'refs/heads/main') 'Scaffolded repository starts on main'
    git -C $project rev-parse --verify -q HEAD 2>$null | Out-Null
    Assert ($LASTEXITCODE -ne 0) 'Scaffolder does not commit'
    $charter = Get-Content -Raw (Join-Path $project 'PROJECT-CHARTER.md')
    Assert ($charter -match 'Canonical development environment: WINDOWS' -and $charter -match 'rationale: chosen explicitly' -and $charter -match '\{\{LICENCE_OR_UNDECIDED\}\}') 'Charter records environment and keeps undecided fields'
    Assert ((Get-Content -Raw (Join-Path $project 'scripts/check.ps1')) -match 'cargo clippy' -and (Get-Content -Raw (Join-Path $project '.gitignore')) -match '/target/') 'Rust stack fills the gate and ignore file'
    Assert ((Get-Content -Raw (Join-Path $project 'scripts/check.ps1')) -notmatch 'Copy this gate') 'Scaffolded gate does not tell the reader to copy itself'

    '' | & $shellExe -NoProfile -File "$root/new-project.ps1" -Name Plain -Parent $np -WindowsNative no -LinuxTarget no -NoClaude | Out-Null
    Assert ($LASTEXITCODE -eq 0 -and -not (Test-Path (Join-Path $np 'Plain/CLAUDE.md'))) 'No platform tie stays on Windows and -NoClaude is honoured'
    $output = & $shellExe -NoProfile -File (Join-Path $np 'Plain/scripts/check.ps1') | Out-String
    Assert ($LASTEXITCODE -eq 1 -and $output -match 'placeholders') 'Scaffolded gate without a stack refuses to run'

    $output = '' | & $shellExe -NoProfile -File "$root/new-project.ps1" -Name LinuxTool -Parent $np -WindowsNative no -LinuxTarget yes -Stack Python | Out-String
    Assert ($LASTEXITCODE -eq 3 -and -not (Test-Path (Join-Path $np 'LinuxTool')) -and $output -match 'new-project.sh.*--stack python') 'Linux project is redirected to WSL without creating anything'
    [IO.File]::WriteAllText((Join-Path $project 'sentinel'), 'keep', $utf8)
    '' | & $shellExe -NoProfile -File "$root/new-project.ps1" -Name WinTool -Parent $np -Environment Windows | Out-Null
    Assert ($LASTEXITCODE -eq 1 -and [IO.File]::ReadAllText((Join-Path $project 'sentinel')) -eq 'keep') 'Scaffolder never touches an existing project'
    '' | & $shellExe -NoProfile -File "$root/new-project.ps1" -Name '..\escape' -Parent $np -Environment Windows | Out-Null
    Assert ($LASTEXITCODE -eq 1 -and -not (Test-Path (Join-Path $testRoot 'escape'))) 'Scaffolder rejects unsafe names'
    '' | & $shellExe -NoProfile -File "$root/new-project.ps1" -Name '-dash' -Parent $np -Environment Windows | Out-Null
    Assert ($LASTEXITCODE -eq 1 -and -not (Test-Path (Join-Path $np '-dash'))) 'Scaffolder rejects option-shaped names'
    # Test-Path is not used on reserved names: on Windows it can report the device itself.
    foreach ($reserved in @('con', 'NUL', 'Com1', 'lpt9.txt', 'aux.tar.gz', 'name.')) {
        $output = '' | & $shellExe -NoProfile -File "$root/new-project.ps1" -Name $reserved -Parent $np -Environment Windows | Out-String
        Assert ($LASTEXITCODE -eq 1 -and $output -match 'reserved device name|must not end') "Scaffolder rejects Windows-reserved name $reserved"
    }
    foreach ($ordinary in @('console', 'com10', 'nul-tools', 'v1.0')) {
        '' | & $shellExe -NoProfile -File "$root/new-project.ps1" -Name $ordinary -Parent $np -Environment Linux | Out-Null
        Assert ($LASTEXITCODE -eq 3) "Scaffolder accepts ordinary name $ordinary"
    }
    '' | & $shellExe -NoProfile -File "$root/new-project.ps1" -Name Asks -Parent $np | Out-Null
    Assert ($LASTEXITCODE -eq 1 -and -not (Test-Path (Join-Path $np 'Asks'))) 'Scaffolder never guesses missing answers'

    # A failure part-way through removes what the run created. A stand-in git fails on init.
    $failGit = Join-Path $testRoot 'failgit'
    $null = New-Item -ItemType Directory -Path $failGit
    if ($env:OS -eq 'Windows_NT') {
        [IO.File]::WriteAllText((Join-Path $failGit 'git.cmd'), "@echo fatal: simulated failure 1>&2`r`n@exit /b 1`r`n", $utf8)
    }
    else {
        [IO.File]::WriteAllText((Join-Path $failGit 'git'), "#!/bin/sh`necho 'fatal: simulated failure' >&2`nexit 1`n", $utf8)
        chmod +x (Join-Path $failGit 'git')
    }
    $savedPath = $env:PATH
    try {
        $env:PATH = $failGit + [IO.Path]::PathSeparator + $savedPath
        $output = '' | & $shellExe -NoProfile -File "$root/new-project.ps1" -Name Broken -Parent $np -Environment Windows | Out-String
        Assert ($LASTEXITCODE -eq 1 -and -not (Test-Path (Join-Path $np 'Broken')) -and $output -match 'destination files were preserved') 'A failed preparation never creates the destination'
        $null = New-Item -ItemType Directory -Path (Join-Path $np 'WasEmpty')
        '' | & $shellExe -NoProfile -File "$root/new-project.ps1" -Name WasEmpty -Parent $np -Environment Windows | Out-Null
        Assert ($LASTEXITCODE -eq 1 -and @(Get-ChildItem -Force -LiteralPath (Join-Path $np 'WasEmpty')).Count -eq 0) 'A failed scaffold restores an empty target directory'
    }
    finally { $env:PATH = $savedPath }

    # A writer that arrives during Git preparation must survive publication failure.
    $concurrent = Join-Path $np 'Concurrent'
    $null = New-Item -ItemType Directory -Path $concurrent
    $harness = @'
param($Source, $Parent)
function git {
    [IO.File]::WriteAllText((Join-Path $Parent 'Concurrent/sentinel'), 'keep')
    $global:LASTEXITCODE = 0
}
& $Source -Name Concurrent -Parent $Parent -Environment Windows
exit $LASTEXITCODE
'@
    [IO.File]::WriteAllText("$testRoot/concurrent.ps1", $harness, $utf8)
    & $shellExe -NoProfile -File "$testRoot/concurrent.ps1" "$root/new-project.ps1" $np | Out-Null
    Assert ($LASTEXITCODE -eq 1 -and [IO.File]::ReadAllText((Join-Path $concurrent 'sentinel')) -eq 'keep') 'Concurrent destination files survive a publication conflict'
    Assert (-not (Test-Path (Join-Path $concurrent 'README.md'))) 'Publication conflict does not copy generated files'

    $linkTarget = Join-Path $np 'LinkTarget'
    $linkPath = Join-Path $np 'Linked'
    $null = New-Item -ItemType Directory -Path $linkTarget
    $linkCreated = $false
    try {
        $linkType = if ($env:OS -eq 'Windows_NT') { 'Junction' } else { 'SymbolicLink' }
        $null = New-Item -ItemType $linkType -Path $linkPath -Target $linkTarget -ErrorAction Stop
        $linkCreated = $true
    }
    catch { Write-Host 'SKIP: host cannot create a junction or symbolic link' }
    if ($linkCreated) {
        try {
            & $shellExe -NoProfile -File "$root/new-project.ps1" -Name Linked -Parent $np -Environment Windows | Out-Null
            Assert ($LASTEXITCODE -eq 1 -and @(Get-ChildItem -Force -LiteralPath $linkTarget).Count -eq 0) 'Scaffolder rejects a junction or symlink destination'
        }
        finally { [IO.Directory]::Delete($linkPath, $false) }
    }

    # Embedded Claude JSON must stay valid on both platforms.
    foreach ($file in @('bootstrap-windows.ps1', 'bootstrap-linux.sh')) {
        $source = Get-Content -Raw -Encoding UTF8 "$root/$file"
        $json = [regex]::Match($source, '(?ms)^\{\r?\n\s*"\$schema".*?^\}').Value
        $null = $json | ConvertFrom-Json
        Assert (-not [string]::IsNullOrWhiteSpace($json)) "$file contains valid Claude JSON"
    }
}
finally {
    # Only this test's newly created directory is eligible for cleanup.
    $resolved = (Resolve-Path -LiteralPath $testRoot).ProviderPath
    if ($resolved -ne [IO.Path]::GetFullPath($testRoot) -or (Get-Item -LiteralPath $resolved).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'Unexpected test cleanup path'
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host 'PowerShell regressions passed.'
exit 0
