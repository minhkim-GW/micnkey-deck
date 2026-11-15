@echo off
rem Runs MicnKey Deck from this folder without installing.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0MicnKey.ps1"
