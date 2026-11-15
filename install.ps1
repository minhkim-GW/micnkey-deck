# MicnKey Deck installer.
# Copies the app into your own user folder (no admin rights), creates shortcuts and starts it.
# Run it by double-clicking Install.cmd.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$src  = Join-Path $root 'app'
$dest = Join-Path $env:LOCALAPPDATA 'MicnKey Deck'

Write-Host ''
Write-Host '  MicnKey Deck - installer' -ForegroundColor Cyan
Write-Host '  ------------------------'

if (-not (Test-Path (Join-Path $src 'MicnKey.ps1'))) {
    Write-Host '  The "app" folder is missing. Extract the whole zip first, then run Install.cmd again.' -ForegroundColor Red
    Read-Host '  Press Enter to close'
    exit 1
}

# 1. stop a copy that is already running (upgrades)
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'MicnKey\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# 2. copy the app (your own config.json is kept when you upgrade)
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Get-ChildItem $src -File | ForEach-Object {
    if ($_.Name -eq 'config.json') { return }
    Copy-Item $_.FullName -Destination $dest -Force
}
# files downloaded from the internet are marked as blocked; unblock our own copies
Get-ChildItem $dest -File | Unblock-File -ErrorAction SilentlyContinue
Write-Host "  Installed to: $dest"

# 3. shortcuts on the Desktop and in the Start menu
$ws  = New-Object -ComObject WScript.Shell
$ps  = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$ico = Join-Path $dest 'MicnKey.ico'
function New-Shortcut([string]$lnk, [string]$script, [string]$desc, [string]$extra) {
    $sc = $ws.CreateShortcut($lnk)
    $sc.TargetPath       = $ps
    $sc.Arguments        = "-NoProfile $extra-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $dest $script)`""
    $sc.WorkingDirectory = $dest
    $sc.WindowStyle      = 7
    $sc.Description      = $desc
    if (Test-Path $ico) { $sc.IconLocation = $ico }
    $sc.Save()
}
$desktop  = [Environment]::GetFolderPath('Desktop')
$programs = [Environment]::GetFolderPath('Programs')
New-Shortcut (Join-Path $desktop  'MicnKey Deck.lnk')          'MicnKey.ps1'  'MicnKey Deck - mic and AI keypad' ''
New-Shortcut (Join-Path $programs 'MicnKey Deck.lnk')          'MicnKey.ps1'  'MicnKey Deck - mic and AI keypad' ''
New-Shortcut (Join-Path $programs 'MicnKey Deck Settings.lnk') 'Settings.ps1' 'MicnKey Deck - settings'          '-STA '
Write-Host '  Shortcuts: Desktop and Start menu ("MicnKey Deck")'

# 4. start it
Start-Process $ps -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $dest 'MicnKey.ps1')`""
Write-Host ''
Write-Host '  Done! The pad appears at the bottom-right of your screen.' -ForegroundColor Green
Write-Host '  Click the gear on the pad to add or change keys.'
Write-Host ''
Start-Sleep -Seconds 6
