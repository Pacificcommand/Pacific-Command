@echo off
rem Export the Windows build from the command line (Godot must be on PATH or edit the path below).
rem Same as Project > Export > Windows Desktop > Export Project in the editor.
set GODOT=godot
cd /d "%~dp0.."
%GODOT% --headless --import
%GODOT% --headless --export-release "Windows Desktop" build\windows\PacificCommand.exe
echo Done: build\windows\PacificCommand.exe
pause
