# No installers, credentials, browser launches, or real user configuration.
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

    # A clean checkout has no ordinary `git diff`, so exercise the real toolkit
    # gate in a committed fixture containing trailing whitespace.
    $whitespaceRoot = Join-Path $testRoot 'committed-whitespace'
    foreach ($directory in @('scripts', 'helpers', 'tests', 'profiles', 'templates/foundation')) {
        $null = New-Item -ItemType Directory -Path (Join-Path $whitespaceRoot $directory) -Force
    }
    Copy-Item -LiteralPath "$root/scripts/check.ps1" -Destination "$whitespaceRoot/scripts/check.ps1"
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
param([string]$Source, [string]$Fixture, [string]$SelectedStack, [switch]$Agents, [switch]$Inspect, [switch]$UseWsl)
$env:USERPROFILE = $Fixture
$global:Events = New-Object 'System.Collections.Generic.List[string]'
function Record([string]$Name, $Arguments) {
    $global:Events.Add($Name + ' ' + ($Arguments -join ' '))
    $global:LASTEXITCODE = 0
}
function code { Record 'code' $args }
function git { Record 'git' $args }
function gh { Record 'gh' $args }
function pwsh { Record 'pwsh' $args }
function rustup { Record 'rustup' $args; 'stable-x86_64-pc-windows-msvc rustfmt clippy' }
function rustc { Record 'rustc' $args; 'rustc fixture' }
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
& $Source -Stack $SelectedStack -ConfigureAgents:$Agents -Check:$Inspect -Wsl:$UseWsl
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

    # -Wsl adds the Remote-WSL extension; check mode never enables WSL.
    $fixture = Join-Path $testRoot 'profile-wsl'
    $null = New-Item -ItemType Directory -Path $fixture
    & $shellExe -NoProfile -File "$testRoot/profiles.ps1" "$root/bootstrap-windows.ps1" $fixture 'Base' -UseWsl
    $events = Get-Content -Raw "$fixture/events.txt"
    Assert ($events -match 'remote-wsl' -and $events -notmatch 'wsl --install') 'WSL selection adds its extension and never enables WSL without -InstallMissing'

    # Helpers invoke these functions, so no real auth lookup or agent can run.
    function gh {
        $global:LASTEXITCODE = 0
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
        elseif ($args[0] -eq 'build') { $script:buildCalls++; $global:LASTEXITCODE = $script:buildExit }
        else { throw 'Unexpected cargo command' }
    }
    $Check = $false
    foreach ($scenario in @(@(1, 0, 0, 1), @(0, 1, 1, 1), @(0, 0, 1, 0))) {
        $script:initExit = $scenario[0]; $script:buildExit = $scenario[1]
        $script:buildCalls = 0; $script:probeErrors = 0
        $before = (Get-Location).Path
        & ([scriptblock]::Create($probeAst.Extent.Text))
        Assert ($script:buildCalls -eq $scenario[2] -and $script:probeErrors -eq $scenario[3]) 'Linker probe checks initialization and build results'
        Assert ((Get-Location).Path -eq $before) 'Linker probe restores working directory'
    }

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
    '' | & $shellExe -NoProfile -File "$root/new-project.ps1" -Name Asks -Parent $np | Out-Null
    Assert ($LASTEXITCODE -eq 1 -and -not (Test-Path (Join-Path $np 'Asks'))) 'Scaffolder never guesses missing answers'

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
