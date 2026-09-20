@echo off
REM Prebuilt-friendly Windows build. Steam mode loads steam_api64.dll at runtime
REM (no Steamworks SDK / no CGO). Remnant already ships that DLL in Binaries\Win64.
go build -o steam_bridge.exe .
if errorlevel 1 exit /b 1
echo Built steam_bridge.exe (steam/tcp/lan — steam uses runtime steam_api64.dll)
