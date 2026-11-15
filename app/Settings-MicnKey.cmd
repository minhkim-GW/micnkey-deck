@echo off
rem Opens the MicnKey Deck settings window.
start "" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Settings.ps1"
