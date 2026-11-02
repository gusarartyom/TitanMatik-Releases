$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
function Show-UpdateMessage([string]$Text, [switch]$Failure) {
    if ($Failure) { [void][Windows.Forms.MessageBox]::Show($Text, 'Обновление TitanMatik', 'OK', 'Error') }
    else { [void][Windows.Forms.MessageBox]::Show($Text, 'Обновление TitanMatik') }
}
function Invoke-TitanMatikUpdate([string]$installDir = $PSScriptRoot) {
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('TitanMatik-update-' + [guid]::NewGuid())
try {
    if (-not (Test-Path -LiteralPath (Join-Path $installDir 'HeroWarsBro.exe'))) { throw 'Программа не найдена рядом с модулем обновления.' }
    if (Get-Process -Name HeroWarsBro -ErrorAction SilentlyContinue) {
        Show-UpdateMessage 'Сохраните работу и закройте TitanMatik, затем повторите обновление.'
        return
    }
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/gusarartyom/TitanMatik-Releases/releases/latest' -Headers @{'User-Agent'='TitanMatik-Updater'}
    if ($release.draft -or $release.prerelease -or $release.tag_name -notmatch '^tm-[a-f0-9]{64}-[a-f0-9]{64}$') { throw 'Проверенное обновление пока недоступно.' }
    $identity = Join-Path $installDir '.titanmatik-installed.sha256'
    if ((Test-Path -LiteralPath $identity) -and [IO.File]::ReadAllText($identity).Trim().ToLowerInvariant() -ceq $release.tag_name.Substring(68)) {
        Show-UpdateMessage 'У вас уже установлена актуальная версия TitanMatik.'
        return
    }
    $expectedBase = 'https://github.com/gusarartyom/TitanMatik-Releases/releases/download/' + $release.tag_name + '/'
    $assets = @{}
    foreach ($name in @('TitanMatik_Setup.exe','SHA256SUMS')) {
        $matches = @($release.assets | Where-Object name -eq $name)
        if ($matches.Count -ne 1 -or $matches[0].browser_download_url -cne ($expectedBase + $name)) { throw 'Не удалось проверить адрес обновления.' }
        $assets[$name] = $matches[0]
    }
    [IO.Directory]::CreateDirectory($scratch) | Out-Null
    foreach ($name in @('SHA256SUMS','TitanMatik_Setup.exe')) {
        Invoke-WebRequest -UseBasicParsing -Uri $assets[$name].browser_download_url -OutFile (Join-Path $scratch $name)
    }
    $sum = [IO.File]::ReadAllText((Join-Path $scratch 'SHA256SUMS')).Trim()
    if ($sum -notmatch '^([a-f0-9]{64})  TitanMatik_Setup\.exe$') { throw 'Некорректная контрольная сумма обновления.' }
    $expected = $Matches[1]
    $setup = Join-Path $scratch 'TitanMatik_Setup.exe'
    if ((Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected -or -not $release.tag_name.EndsWith($expected)) { throw 'Загруженный установщик повреждён. Обновление отменено.' }
    $process = Start-Process -FilePath $setup -ArgumentList @('/SP-','/SILENT','/SUPPRESSMSGBOXES','/NORESTART',('/DIR="'+$installDir+'"')) -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw 'Не удалось завершить обновление. Текущая версия сохранена; обратитесь в поддержку.' }
    Show-UpdateMessage 'TitanMatik обновлён. Можно запускать приложение обычным ярлыком.'
} catch {
    Show-UpdateMessage ('Обновление не выполнено. ' + $_.Exception.Message) -Failure
}
# Temporary downloads are left for the OS temporary-file cleanup. Never remove
# an updater executable while an installer child may still be using it.
}
if ($MyInvocation.InvocationName -ne '.') { Invoke-TitanMatikUpdate }
