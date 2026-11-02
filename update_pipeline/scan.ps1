param([Parameter(Mandatory=$true)][string]$Target)
$ErrorActionPreference = 'Stop'

function Assert-DefenderHealth {
    $status = Get-MpComputerStatus -ErrorAction Stop
    if ($status.AntivirusEnabled -ne $true -or $status.RealTimeProtectionEnabled -ne $true) { throw 'Defender is not active' }
    if (-not $status.AntivirusSignatureLastUpdated -or $status.AntivirusSignatureLastUpdated -lt (Get-Date).AddDays(-3)) { throw 'Defender signatures are stale' }
}

function Assert-DefenderThreats([datetime]$Since, [string]$Root) {
    # These APIs include history. Unresolved/unknown states must block even when
    # InitialDetectionTime predates this run. Never treat a successful action alone
    # as proof that no further remediation is required.
    $active = @(Get-MpThreat -ErrorAction Stop | Where-Object { $_.IsActive -ne $false })
    if ($active.Count) { throw 'Defender reports an active or unknown threat state' }
    foreach ($hit in @(Get-MpThreatDetection -ErrorAction Stop)) {
        if ($hit.ActionSuccess -ne $true -or $hit.ThreatStatusID -notin @(2,3,4) -or $hit.AdditionalActionsBitMask -ne 0) {
            throw 'Defender reports an unresolved or unknown detection'
        }
        if ($hit.InitialDetectionTime -ge $Since -or $hit.LastThreatStatusChangeTime -ge $Since -or $hit.RemediationTime -ge $Since) {
            throw 'Defender reported a detection or remediation during this scan'
        }
        foreach ($resource in @($hit.Resources)) {
            if ($resource -and ([string]$resource).IndexOf($Root, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                throw 'Defender detection history references the scanned target'
            }
        }
    }
}

function Get-ScanInventory([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    $entries = @($item)
    if ($item.PSIsContainer) { $entries += @(Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction Stop) }
    $hashes = [ordered]@{}
    foreach ($entry in @($entries | Sort-Object FullName)) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Scan target contains a reparse point' }
        if (-not $entry.PSIsContainer) {
            $hashes[$entry.FullName] = (Get-FileHash -LiteralPath $entry.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
        }
    }
    if (-not $hashes.Count) { throw 'Scan target contains no files' }
    return (ConvertTo-Json -InputObject $hashes -Compress)
}

$root = (Resolve-Path -LiteralPath $Target -ErrorAction Stop).Path
$start = Get-Date
Assert-DefenderHealth
Assert-DefenderThreats -Since $start -Root $root
$before = Get-ScanInventory $root
Start-MpScan -ScanType CustomScan -ScanPath $root -ErrorAction Stop
Assert-DefenderHealth
Assert-DefenderThreats -Since $start -Root $root
if ((Get-ScanInventory $root) -cne $before) { throw 'Scanned files disappeared or changed; publication forbidden' }
