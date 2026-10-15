@echo off
setlocal
set "OSC_GODOT=%GODOT_PATH%"
if not defined OSC_GODOT if exist "%~dp0.local\godot-path.txt" set /p "OSC_GODOT="<"%~dp0.local\godot-path.txt"
if not defined OSC_GODOT for /f "delims=" %%G in ('where godot 2^>nul') do if not defined OSC_GODOT set "OSC_GODOT=%%G"
if not defined OSC_GODOT (
  echo Godot was not found. Set GODOT_PATH or put its executable path in .local\godot-path.txt.
  pause
  exit /b 1
)
echo Preparing game files...
"%OSC_GODOT%" --headless --path "%~dp0godot" --editor --import
if errorlevel 1 (
  echo Godot could not prepare the game files. See the errors above.
  pause
  exit /b 1
)
start "" "%OSC_GODOT%" --path "%~dp0godot" res://game.tscn %*
