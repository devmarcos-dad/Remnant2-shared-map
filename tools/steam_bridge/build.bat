@echo off
REM Build steam_bridge for Windows (TCP/LAN modes work without Steamworks).
go build -o steam_bridge.exe .
if errorlevel 1 exit /b 1
echo Built steam_bridge.exe
