#!/bin/sh
# Export the Windows build (needs the 4.7.2 export templates installed; see docs/STEAM.md).
cd "$(dirname "$0")/.."
godot --headless --import
godot --headless --export-release "Windows Desktop" build/windows/PacificCommand.exe
cd build/windows && zip -9 ../PacificCommand_win64.zip PacificCommand.exe && echo "build/PacificCommand_win64.zip"
