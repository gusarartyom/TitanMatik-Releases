$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../../installer/TitanMatik.Update.ps1"
$scratch = Join-Path (Get-Location) ('.test-temp/updater-' + [guid]::NewGuid())
[IO.Directory]::CreateDirectory($scratch) | Out-Null
[IO.File]::WriteAllText((Join-Path $scratch 'HeroWarsBro.exe'),'not-executed')
$bytes = [Text.Encoding]::UTF8.GetBytes('harmless installer fixture; never executed')
$hash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace('-','').ToLowerInvariant()
$tag = 'tm-' + ('a'*64) + '-' + $hash
$base = 'https://github.com/gusarartyom/TitanMatik-Releases/releases/download/' + $tag + '/'
function Show-UpdateMessage($Text, [switch]$Failure) { $script:message = $Text; $script:failed = [bool]$Failure }
function Get-Process { if ($script:running) { return [pscustomobject]@{Id=123} }; return $null }
function Invoke-RestMethod { if ($script:offline) { throw 'network unavailable' }; return $script:release }
function Invoke-WebRequest($Uri,$OutFile,[switch]$UseBasicParsing) {
    $script:downloads++
    if ($Uri.EndsWith('/SHA256SUMS')) { [IO.File]::WriteAllText($OutFile, ($script:hash+'  TitanMatik_Setup.exe')) }
    else { [IO.File]::WriteAllBytes($OutFile, $(if ($script:corrupt) { [byte[]]@(1,2) } else { $script:bytes })) }
}
function Start-Process($FilePath,$ArgumentList,[switch]$Wait,[switch]$PassThru) { $script:launches++; $script:arguments=$ArgumentList; return [pscustomobject]@{ExitCode=0} }
function Reset-Test {
    $script:failed=$false; $script:message=''; $script:downloads=0; $script:launches=0; $script:corrupt=$false; $script:running=$false; $script:offline=$false
    $script:release=[pscustomobject]@{draft=$false;prerelease=$false;tag_name=$tag;assets=@([pscustomobject]@{name='SHA256SUMS';browser_download_url=($base+'SHA256SUMS')},[pscustomobject]@{name='TitanMatik_Setup.exe';browser_download_url=($base+'TitanMatik_Setup.exe')})}
}
Reset-Test
Invoke-TitanMatikUpdate $scratch
if ($failed -or $launches -ne 1 -or $downloads -ne 2 -or $arguments -notcontains ('/DIR="'+$scratch+'"')) { throw 'Verified installer did not launch against the original directory' }
Reset-Test; $corrupt=$true
Invoke-TitanMatikUpdate $scratch
if (-not $failed -or $launches) { throw 'Corrupted installer was accepted' }
Reset-Test; $release.assets[1].browser_download_url='https://unexpected.example/setup.exe'
Invoke-TitanMatikUpdate $scratch
if (-not $failed -or $launches -or $downloads) { throw 'Unexpected download host was accepted' }
Reset-Test; $release.prerelease=$true
Invoke-TitanMatikUpdate $scratch
if (-not $failed -or $launches -or $downloads) { throw 'Prerelease was accepted' }
Reset-Test
[IO.File]::WriteAllText((Join-Path $scratch '.titanmatik-installed.sha256'),$hash)
Invoke-TitanMatikUpdate $scratch
if ($failed -or $launches -or $downloads) { throw 'Current version downloaded or installed again' }
Reset-Test; $offline=$true
Invoke-TitanMatikUpdate $scratch
if (-not $failed -or $launches -or $downloads) { throw 'Network failure launched an installer' }
Reset-Test; $running=$true
Invoke-TitanMatikUpdate $scratch
if ($launches -or $downloads) { throw 'Running application was updated' }
Write-Output '7 updater transport/version/integrity tests passed; no vendor program executed'
