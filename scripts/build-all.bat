@echo off
rem build-all.bat - Double-click entry for build-all.ps1 (one-click build).
rem Optional args are passed through, e.g.:  build-all.bat -Run
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-all.ps1" %*
set EC=%ERRORLEVEL%
echo.
echo build-all finished (exit code %EC%).
pause
exit /b %EC%
