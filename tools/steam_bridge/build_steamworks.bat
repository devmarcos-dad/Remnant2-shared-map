@echo off
setlocal EnableExtensions
REM Build steam_bridge with real ISteamNetworkingMessages P2P (-tags steamworks, CGO).
REM
REM Prerequisites:
REM   1. Go 1.22+ and a C compiler (TDM-GCC / MinGW-w64 / LLVM) on PATH for CGO
REM   2. Steamworks SDK extracted somewhere, e.g. C:\steamworks_sdk
REM   3. Steam client installed (runtime test needs Steam running + logged-in user)
REM
REM Usage:
REM   set STEAMWORKS=C:\path\to\sdk
REM   tools\steam_bridge\build_steamworks.bat

if "%STEAMWORKS%"=="" (
  echo ERROR: Set STEAMWORKS to your Steamworks SDK root ^(folder that contains public\ and redistributable_bin\^).
  echo Example: set STEAMWORKS=C:\steamworks_sdk
  echo See docs\STEAM.md
  exit /b 1
)

if not exist "%STEAMWORKS%\redistributable_bin\win64\steam_api64.lib" (
  if not exist "%STEAMWORKS%\redistributable_bin\win64\steam_api64.dll" (
    echo ERROR: steam_api64.lib / steam_api64.dll not found under:
    echo   %STEAMWORKS%\redistributable_bin\win64\
    exit /b 1
  )
)

set CGO_ENABLED=1
set CGO_CFLAGS=-I%CD%
set CGO_LDFLAGS=-L%STEAMWORKS%\redistributable_bin\win64 -lsteam_api64

echo Building with -tags steamworks ...
go build -tags steamworks -o steam_bridge.exe .
if errorlevel 1 (
  echo.
  echo Build failed. Common fixes:
  echo   - Install a C toolchain for CGO ^(gcc^)
  echo   - Confirm STEAMWORKS points at the SDK root
  echo   - If link errors mention SteamAPI_SteamUser_SteamAPI_v0xx, retarget
  echo     accessor names in steam_abi.h to match your SDK steam_api_flat.h
  exit /b 1
)

copy /Y "%STEAMWORKS%\redistributable_bin\win64\steam_api64.dll" ".\steam_api64.dll" >nul
echo 1282100> steam_appid.txt
echo.
echo Built steam_bridge.exe + steam_api64.dll + steam_appid.txt
echo Run with Steam open: steam_bridge.exe -mode steam
echo Peer: -peer STEAMID64  or  %%TEMP%%\MapSyncQueue\steam_peer.txt
endlocal
