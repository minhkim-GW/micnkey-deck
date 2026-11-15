@echo off
rem Installs MicnKey Deck for the current user (no admin needed).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
