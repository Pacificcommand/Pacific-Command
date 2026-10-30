@echo off
rem Upload the Windows build in build\windows to Steam.
rem 1. Install the Steamworks SDK (https://partner.steamgames.com/downloads) and unzip it to C:\steamworks
rem 2. Fill in YOUR_APP_ID / YOUR_DEPOT_ID in app_build.vdf and depot_build.vdf
rem 3. Run this file. Steam Guard will ask for a code the first time.
set SDK=C:\steamworks\sdk\tools\ContentBuilder\builder
"%SDK%\steamcmd.exe" +login YOUR_STEAM_LOGIN +run_app_build "%~dp0app_build.vdf" +quit
pause
