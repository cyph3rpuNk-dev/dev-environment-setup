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

    # Embedded Claude JSON must stay valid on both platforms.
    foreach ($file in @('bootstrap-windows.ps1', 'bootstrap-wsl.sh')) {
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
