# MicnKey Deck uninstaller. Run it by double-clicking Uninstall.cmd.

$dest = Join-Path $env:LOCALAPPDATA 'MicnKey Deck'

Write-Host ''
Write-Host '  MicnKey Deck - uninstall' -ForegroundColor Cyan
Write-Host "  This removes the app, its settings and its shortcuts from: $dest"
$answer = Read-Host '  Type Y and press Enter to continue'
if ($answer -notmatch '^[Yy]') { Write-Host '  Nothing was removed.'; Start-Sleep -Seconds 2; exit }

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match '(MicnKey|Settings)\.ps1' -and $_.CommandLine -match 'MicnKey Deck' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 800

foreach ($folder in @('Desktop', 'Programs', 'Startup')) {
    foreach ($name in @('MicnKey Deck.lnk', 'MicnKey Deck Settings.lnk')) {
        $lnk = Join-Path ([Environment]::GetFolderPath($folder)) $name
        if (Test-Path $lnk) { Remove-Item $lnk -Force }
    }
}
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }

Write-Host '  MicnKey Deck has been removed.' -ForegroundColor Green
Start-Sleep -Seconds 3
