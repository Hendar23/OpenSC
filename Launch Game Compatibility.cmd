@echo off
setlocal
if exist "%~dp0OpenSC.exe" (
  start "" "%~dp0OpenSC.exe" --rendering-method gl_compatibility %*
  exit /b
)
call "%~dp0Launch Game.cmd" --rendering-method gl_compatibility %*
