@echo off
setlocal
set "OSC_GODOT=%GODOT_PATH%"
if not defined OSC_GODOT for /f "delims=" %%G in ('where godot 2^>nul') do if not defined OSC_GODOT set "OSC_GODOT=%%G"
if not defined OSC_GODOT (
  echo Godot was not found. Set GODOT_PATH to your Godot executable, or launch asset_editor.tscn from Godot.
  pause
  exit /b 1
)
start "" "%OSC_GODOT%" --path "%~dp0godot" res://asset_editor.tscn
