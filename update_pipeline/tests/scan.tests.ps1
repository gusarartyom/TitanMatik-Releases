# Harmless fixtures and mocked Defender cmdlets; never creates malware or changes AV settings.
$ErrorActionPreference = 'Stop'
$scanScript = Join-Path $PSScriptRoot '../scan.ps1'
$scratch = Join-Path $PSScriptRoot '../../.test-temp'
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$global:TitanMatikScanTestState = @{}

function Get-MpComputerStatus {
    param($ErrorAction)
    if ($global:TitanMatikScanTestState.Case -eq 'health_error') { throw 'unavailable' }
    [pscustomobject]@{
        AntivirusEnabled = ($global:TitanMatikScanTestState.Case -ne 'disabled')
        RealTimeProtectionEnabled = $true
        AntivirusSignatureLastUpdated = if ($global:TitanMatikScanTestState.Case -eq 'stale') { (Get-Date).AddDays(-4) } else { Get-Date }
    }
}
function Get-MpThreat {
    param($ErrorAction)
    if ($global:TitanMatikScanTestState.Case -eq 'active') { [pscustomobject]@{IsActive=$true} }
}
function Get-MpThreatDetection {
    param($ErrorAction)
    $case = $global:TitanMatikScanTestState.Case
    if ($case -eq 'detection_error') { throw 'unavailable' }
    if ($case -in @('clean','disabled','stale','active','health_error','scan_error','tampered','removed')) { return }
    if ($case -in @('new_remediated','changed_old') -and -not $global:TitanMatikScanTestState.Scanned) { return }
    $hit = [ordered]@{
        InitialDetectionTime = (Get-Date).AddDays(-1)
        LastThreatStatusChangeTime = (Get-Date).AddDays(-1)
        RemediationTime = (Get-Date).AddDays(-1)
        Resources = @('file:C:\unrelated-history\old.dll')
        ActionSuccess = $true
        ThreatStatusID = 3
        AdditionalActionsBitMask = 0
    }
    switch ($case) {
        'old_unresolved' { $hit.ActionSuccess=$false; $hit.ThreatStatusID=102 }
        'old_target' { $hit.Resources=@('containerfile:' + $global:TitanMatikScanTestState.Root + '\safe.txt') }
        'new_remediated' { $hit.InitialDetectionTime=Get-Date }
        'changed_old' { $hit.LastThreatStatusChangeTime=Get-Date }
        'unknown_status' { $hit.ThreatStatusID=99 }
        'additional_actions' { $hit.AdditionalActionsBitMask=8 }
    }
    [pscustomobject]$hit
}
function Start-MpScan {
    param($ScanType,$ScanPath,$ErrorAction)
    $global:TitanMatikScanTestState.Scanned=$true
    switch ($global:TitanMatikScanTestState.Case) {
        'scan_error' { throw 'scan failed' }
        'tampered' { [IO.File]::WriteAllText((Join-Path $ScanPath 'safe.txt'),'changed') }
        'removed' { Remove-Item -LiteralPath (Join-Path $ScanPath 'safe.txt') }
    }
}

$passed = 0
try {
    foreach ($case in @('clean','old_unresolved','old_target','old_resolved_unrelated','new_remediated','changed_old','unknown_status','additional_actions','active','health_error','scan_error','detection_error','tampered','removed','stale','disabled')) {
        $root = Join-Path $scratch ('scan-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $root | Out-Null
        [IO.File]::WriteAllText((Join-Path $root 'safe.txt'),'harmless-test-data')
        $global:TitanMatikScanTestState = @{Case=$case; Root=[IO.Path]::GetFullPath($root); Scanned=$false}
        $allowed = $true
        try { & $scanScript -Target $root } catch { $allowed = $false }
        $expected = $case -in @('clean','old_resolved_unrelated')
        if ($allowed -ne $expected) { throw "Unexpected Defender gate decision for $case (allowed=$allowed)" }
        Write-Output "PASS Defender gate: $case"
        $passed++
    }
    Write-Output "Defender gate tests passed: $passed"
} finally {
    Remove-Variable -Name TitanMatikScanTestState -Scope Global
}
