# Stage outcomes only: never persist console output, auth results or credentials.
function Complete-SetupStage {
    if ($script:SetupStage) { $script:SetupRows.Add("$script:SetupStage`t$script:SetupStageStatus") }
}
function Start-SetupStage {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Updates in-memory receipt metadata only; no external state is changed.')]
    param([string]$Name)
    Complete-SetupStage
    $script:SetupStage = ($Name.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    $script:SetupStageStatus = 'completed'
}
function Write-SetupReceipt([string]$Path, [bool]$Completed) {
    if (-not $Completed) { $script:SetupStageStatus = 'interrupted' }
    Complete-SetupStage
    $status = if ($Completed -and $script:Failures -eq 0) { 'completed' } else { 'failed-or-interrupted' }
    $text = "# devsetup-results-v1`nrun`t$([guid]::NewGuid().ToString('N'))`nstatus`t$status`n" + ($script:SetupRows -join "`n") + "`n"
    # CreateNew refuses collisions, including a concurrently created destination.
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
    try { $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($text); $stream.Write($bytes, 0, $bytes.Length) }
    finally { $stream.Dispose() }
}
