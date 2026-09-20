@echo off
REM Default Windows build — TCP and LAN modes only (no Steamworks SDK / CGO).
REM -mode steam will exit with a clear pointer to docs/STEAM.md.
go build -o steam_bridge.exe .
if errorlevel 1 exit /b 1
echo Built steam_bridge.exe (tcp/lan; steam mode stubbed)
