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
    Write-Output ('Testing installation; automatic discovery=' + [bool]$AutoDetect)
    $p = Start-Process -FilePath $setup -ArgumentList $arguments -PassThru -WindowStyle Hidden
    if (-not $p.WaitForExit(120000)) {
        if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 80 }
        throw 'Installer did not exit within two minutes on the disposable test runner'
    }
    if ($p.ExitCode -ne 0) {
        if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 80 }
        throw "Installer failed: $($p.ExitCode)"
    }
}
# A headless update with no known installation must not silently create a copy.
$unknownLog = Join-Path $env:RUNNER_TEMP ('TitanMatik-unknown-' + [guid]::NewGuid() + '.log')
$unknown = Start-Process -FilePath $setup -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',('/LOG="'+$unknownLog+'"')) -PassThru -WindowStyle Hidden
if (-not $unknown.WaitForExit(120000)) {
    if (Test-Path -LiteralPath $unknownLog) { Get-Content -LiteralPath $unknownLog -Tail 80 }
    throw 'Unknown installation hung instead of refusing a silent first installation'
}
if ($unknown.ExitCode -ne 7) { throw 'Unknown installation did not require an explicit install/update choice' }
if (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'TitanMatik/HeroWarsBro.exe')) { throw 'Unknown installation created an unexpected second copy' }
Install
if (-not (Test-Path (Join-Path $target 'HeroWarsBro.exe'))) { throw 'Main executable missing' }
$shell = New-Object -ComObject WScript.Shell
$desktop = [Environment]::GetFolderPath('Desktop')
$mainLink = Join-Path $desktop 'TitanMatik.lnk'
$link = $shell.CreateShortcut($mainLink)
if ($link.TargetPath -ne (Join-Path $target 'HeroWarsBro.exe') -or $link.IconLocation -notlike ((Join-Path $target 'TitanMatik.ico') + '*')) { throw 'Shortcut target or TitanMatik logo missing' }
if ((Get-FileHash -LiteralPath (Join-Path $target 'TitanMatik.ico')).Hash -ne (Get-FileHash -LiteralPath 'installer/TitanMatik.ico').Hash) { throw 'Installed logo differs' }
foreach ($name in @('HeroWarsBro.lnk','Old TitanMatik.lnk')) {
    $old = $shell.CreateShortcut((Join-Path $desktop $name)); $old.TargetPath=Join-Path $target 'HeroWarsBro.exe'; $old.Save()
}
$oldUpdateLink = Join-Path $desktop 'Legacy updater fixture.lnk'
$old = $shell.CreateShortcut($oldUpdateLink)
$old.TargetPath = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
$old.Arguments = '-NoProfile -File "' + (Join-Path $target 'TitanMatik.Update.ps1') + '"'; $old.Save()
Move-Item -LiteralPath $oldUpdateLink -Destination (Join-Path $desktop 'Обновить TitanMatik.lnk')
$unrelated = Join-Path $desktop 'Unrelated application.lnk'
$old = $shell.CreateShortcut($unrelated); $old.TargetPath=Join-Path $env:SystemRoot 'notepad.exe'; $old.Save()
$names = @('settings.json','license.token','license.attempts','crash.log','.hwlclk','.hwlljt','unknown-user-file.txt','Profiles/sentinel','Screenshots/sentinel','Diagnostics/sentinel')
foreach ($name in $names) {
    $path = Join-Path $target $name
    New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
    [IO.File]::WriteAllText($path, 'preserve-' + $name)
}
New-Item -ItemType Directory -Path (Join-Path $target 'empty-user-directory') | Out-Null
Start-Sleep -Seconds 1
Install -AutoDetect
foreach ($name in @('HeroWarsBro.lnk','Old TitanMatik.lnk','Обновить TitanMatik.lnk')) {
    if (Test-Path -LiteralPath (Join-Path $desktop $name)) { throw 'Duplicate desktop shortcut remains' }
}
if (-not (Test-Path -LiteralPath $unrelated)) { throw 'Unrelated desktop shortcut was removed' }
# A saved path must not hide another copy discovered through its shortcut.
$secondTarget = Join-Path $env:RUNNER_TEMP ('TitanMatik-second-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $secondTarget | Out-Null
foreach ($name in @('HeroWarsBro.exe','e_sqlite3.dll','WebView2Loader.dll')) {
    Copy-Item -LiteralPath (Join-Path $target $name) -Destination (Join-Path $secondTarget $name)
}
$secondLink = Join-Path $desktop 'Second TitanMatik test.lnk'
$old = $shell.CreateShortcut($secondLink); $old.TargetPath=Join-Path $secondTarget 'HeroWarsBro.exe'; $old.Save()
$before = (Get-FileHash -LiteralPath (Join-Path $target 'HeroWarsBro.exe')).Hash
$refused = $false
try { Install -AutoDetect } catch { $refused = $true }
if (-not $refused -or -not (Select-String -LiteralPath $script:LastInstallerLog -Pattern 'PrepareToInstall failed:.*несколько копий' -Quiet)) { throw 'Saved installation hid the second installation' }
if ((Get-FileHash -LiteralPath (Join-Path $target 'HeroWarsBro.exe')).Hash -ne $before) { throw 'Ambiguous discovery changed the application' }
Remove-Item -LiteralPath $secondLink
# Update an existing shared shortcut instead of keeping both shared and user links.
$commonLink = Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'TitanMatik.lnk'
if (Test-Path -LiteralPath $commonLink) { throw 'Common desktop fixture is not isolated' }
$old = $shell.CreateShortcut($commonLink); $old.TargetPath=Join-Path $target 'HeroWarsBro.exe'; $old.Save()
try {
    Start-Sleep -Seconds 1
    Install
    if (Test-Path -LiteralPath $mainLink) { throw 'Both common and user shortcuts remain' }
    $shared = $shell.CreateShortcut($commonLink)
    if ($shared.IconLocation -notlike ((Join-Path $target 'TitanMatik.ico') + '*')) { throw 'Common shortcut logo was not updated' }
} finally { Remove-Item -LiteralPath $commonLink -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 1
Install
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
