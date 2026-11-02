param([string]$FaultSetup = '', [string]$BackupFailureSetup = '', [string]$MissingBackupSetup = '')
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or $env:RUNNER_OS -ne 'Windows') {
    throw 'This smoke suite may run only on a disposable GitHub-hosted Windows runner'
}
$setup = (Resolve-Path 'build/installer/TitanMatik_Setup.exe').Path
$target = Join-Path $env:RUNNER_TEMP ('TitanMatik-test-' + [guid]::NewGuid())
function Install([switch]$AutoDetect) {
    $log = Join-Path $env:RUNNER_TEMP ('TitanMatik-setup-' + [guid]::NewGuid() + '.log')
    $script:LastInstallerLog = $log
    $arguments = @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',('/LOG="' + $log + '"'))
    if (-not $AutoDetect) { $arguments += ('/DIR="' + $target + '"') }
    $p = Start-Process -FilePath $setup -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
    if ($p.ExitCode -ne 0) {
        if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 80 }
        throw "Installer failed: $($p.ExitCode)"
    }
}
# A headless update with no known installation must not silently create a copy.
$unknownLog = Join-Path $env:RUNNER_TEMP ('TitanMatik-unknown-' + [guid]::NewGuid() + '.log')
$unknown = Start-Process -FilePath $setup -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',('/LOG="'+$unknownLog+'"')) -Wait -PassThru -WindowStyle Hidden
if ($unknown.ExitCode -ne 7) { throw 'Unknown installation did not require an explicit install/update choice' }
if (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'TitanMatik/HeroWarsBro.exe')) { throw 'Unknown installation created an unexpected second copy' }
Install
if (-not (Test-Path (Join-Path $target 'HeroWarsBro.exe'))) { throw 'Main executable missing' }
$names = @('settings.json','license.token','license.attempts','crash.log','.hwlclk','.hwlljt','unknown-user-file.txt','Profiles/sentinel','Screenshots/sentinel','Diagnostics/sentinel')
foreach ($name in $names) {
    $path = Join-Path $target $name
    New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
    [IO.File]::WriteAllText($path, 'preserve-' + $name)
}
New-Item -ItemType Directory -Path (Join-Path $target 'empty-user-directory') | Out-Null
Start-Sleep -Seconds 1
Install -AutoDetect
# Disposable hosted runner only: simulate a ZIP install with a shortcut but no
# remembered path. Restore the test path even if discovery fails.
$testSavedPath = Get-ItemPropertyValue -LiteralPath 'HKCU:\Software\TitanMatik' -Name InstallDir
try {
    Remove-ItemProperty -LiteralPath 'HKCU:\Software\TitanMatik' -Name InstallDir
    Start-Sleep -Seconds 1
    Install -AutoDetect
} finally {
    Set-ItemProperty -LiteralPath 'HKCU:\Software\TitanMatik' -Name InstallDir -Value $testSavedPath
}
foreach ($name in $names) {
    if ([IO.File]::ReadAllText((Join-Path $target $name)) -cne ('preserve-' + $name)) { throw 'Automatic discovery changed user data' }
}

function Assert-BackupRefused([string]$ReasonPattern) {
    Start-Sleep -Seconds 1
    $main = Join-Path $target 'HeroWarsBro.exe'
    $before = (Get-FileHash -LiteralPath $main).Hash
    $refused = $false
    try { Install } catch { $refused = $true }
    if (-not $refused) { throw 'Setup accepted an incomplete backup' }
    if (-not (Select-String -LiteralPath $script:LastInstallerLog -Pattern $ReasonPattern -Quiet)) { throw 'Unexpected backup refusal reason' }
    if ((Get-FileHash -LiteralPath $main).Hash -ne $before) { throw 'Backup failure changed the executable' }
    foreach ($name in $names) {
        if ([IO.File]::ReadAllText((Join-Path $target $name)) -cne ('preserve-' + $name)) { throw 'Backup failure changed user data' }
    }
}
$runningRoot = Join-Path $env:RUNNER_TEMP ('TitanMatik-running-' + [guid]::NewGuid())
New-Item -ItemType Directory $runningRoot | Out-Null
$runningExe = Join-Path $runningRoot 'HeroWarsBro.exe'
Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\ping.exe') -Destination $runningExe
$process = Start-Process -FilePath $runningExe -ArgumentList @('-t','127.0.0.1') -PassThru -WindowStyle Hidden
try {
    Start-Sleep -Seconds 1
    if ($process.HasExited) { throw 'Running-process fixture did not start' }
    $blocked = $false
    try { Install } catch { $blocked = $true }
    if (-not $blocked) { throw 'Setup accepted a running HeroWarsBro.exe' }
    if (-not (Select-String -LiteralPath $script:LastInstallerLog -Pattern 'PrepareToInstall failed:.*HeroWarsBro.exe' -Quiet)) { throw 'Unexpected reason for running-process refusal' }
} finally { if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force } }
Install
foreach ($name in $names) {
    if ([IO.File]::ReadAllText((Join-Path $target $name)) -cne ('preserve-' + $name)) { throw "User data changed: $name" }
}
$backupDirs = @(Get-ChildItem -LiteralPath (Split-Path $target) -Directory | Where-Object { $_.Name.StartsWith((Split-Path $target -Leaf) + '.backup-') })
if (-not @($backupDirs | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'empty-user-directory') }).Count) { throw 'Backup omitted an empty user directory' }

# Real Windows ACL failure, scoped to this test's generated installation directory.
$deniedDir = Join-Path $target 'unreadable-user-directory'
New-Item -ItemType Directory -Path $deniedDir | Out-Null
[IO.File]::WriteAllText((Join-Path $deniedDir 'private.txt'),'keep-private-data')
$savedAcl = Get-Acl -LiteralPath $deniedDir
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
try {
    & icacls $deniedDir /deny ($identity + ':(RD)') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not set up access-denied fixture' }
    Assert-BackupRefused 'Backup enumeration failed: error=5'
} finally {
    Set-Acl -LiteralPath $deniedDir -AclObject $savedAcl
}
if ([IO.File]::ReadAllText((Join-Path $deniedDir 'private.txt')) -cne 'keep-private-data') { throw 'Unreadable user file was changed' }
if ($BackupFailureSetup) {
    $goodSetup = $setup
    $setup = (Resolve-Path -LiteralPath $BackupFailureSetup).Path
    try { Assert-BackupRefused 'Backup enumeration failed: error=5' } finally { $setup = $goodSetup }
}
$rollbackTest = 'not tested'
$main = Join-Path $target 'HeroWarsBro.exe'
[IO.File]::WriteAllText($main, 'old-version-for-upgrade')
Start-Sleep -Seconds 1
Install
if ((Get-FileHash -LiteralPath $main).Hash -ne (Get-FileHash -LiteralPath 'build/payload/HeroWarsBro.exe').Hash) { throw 'Old-version upgrade did not replace executable' }
if ($FaultSetup) {
    Start-Sleep -Seconds 1
    $main = Join-Path $target 'HeroWarsBro.exe'
    [IO.File]::WriteAllText($main, 'old-version-sentinel')
    $before = (Get-FileHash -LiteralPath $main).Hash
    $goodSetup = $setup
    $setup = (Resolve-Path -LiteralPath $FaultSetup).Path
    $failed = $false
    try { Install } catch { $failed = $true }
    $setup = $goodSetup
    if (-not $failed) { throw 'Fault fixture unexpectedly succeeded' }
    if (-not (Select-String -LiteralPath $script:LastInstallerLog -Pattern 'TITANMATIK_TEST_FAULT' -Quiet)) { throw 'Failure injection was not reached' }
    if ((Get-FileHash -LiteralPath $main).Hash -ne $before) { throw 'Rollback did not restore old binary' }
    foreach ($name in $names) {
        if ([IO.File]::ReadAllText((Join-Path $target $name)) -cne ('preserve-' + $name)) { throw 'Rollback changed user data' }
    }
    $rollbackTest = 'injected ssPostInstall exception'
}
if ($MissingBackupSetup) {
    Start-Sleep -Seconds 1
    [IO.File]::WriteAllText((Join-Path $target 'HeroWarsBro.exe'), 'original-before-missing-backup')
    $goodSetup = $setup
    $setup = (Resolve-Path -LiteralPath $MissingBackupSetup).Path
    $failed = $false
    try { Install } catch { $failed = $true } finally { $setup = $goodSetup }
    if (-not $failed) { throw 'Missing-backup fixture unexpectedly succeeded' }
    if (-not (Select-String -LiteralPath $script:LastInstallerLog -Pattern 'ROLLBACK ORIGINAL NOT DELETED:.*HeroWarsBro.exe' -Quiet)) { throw 'Missing-backup rollback safeguard was not reached' }
    if (-not (Test-Path -LiteralPath (Join-Path $target 'HeroWarsBro.exe'))) { throw 'Rollback deleted an originally existing file with missing backup' }
    foreach ($name in $names) {
        if ([IO.File]::ReadAllText((Join-Path $target $name)) -cne ('preserve-' + $name)) { throw 'Missing-backup rollback changed user data' }
    }
}
$drive = Join-Path $env:RUNNER_TEMP ('TitanMatik-drive-' + [guid]::NewGuid())
New-Item -ItemType Directory $drive | Out-Null
$letter = @('T','U','V') | Where-Object { -not (Test-Path ($_.ToString() + ':\')) } | Select-Object -First 1
if (-not $letter) { throw 'No unused drive letter for test' }
try {
    subst ($letter + ':') $drive
    if ($LASTEXITCODE -ne 0) { throw 'SUBST failed' }
    $target = $letter + ':\TitanMatik'
    Install
    if (-not (Test-Path -LiteralPath (Join-Path $target 'HeroWarsBro.exe'))) { throw 'Alternate-drive installation missing' }
} finally { subst ($letter + ':') /D }
@{clean=$true; reinstall=$true; user_data=$true; alternate_drive='SUBST'; running_process=$true; rollback=$rollbackTest; backup_access_denied=$true; backup_next_error=[bool]$BackupFailureSetup; missing_backup_preserves_original=[bool]$MissingBackupSetup; gui='not tested'} | ConvertTo-Json | Set-Content 'build/test-results.json'
