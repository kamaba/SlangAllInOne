@echo off
rem Build the SLang Unity native plugin (x64, MSVC).
rem ASCII only. Argument 1 = output directory (no spaces).
rem Unity PluginAPI headers are vendored next to this file (see LICENSE.md).
setlocal
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b 1
cl.exe /nologo /W3 /O2 /MD /EHsc /LD /utf-8 /D_CRT_SECURE_NO_WARNINGS /DWIN32 ^
 /I"%~dp0UnityPluginAPI" ^
 /Fo:"%~1\slang_unity_native.obj" ^
 /Fe:"%~1\slang_unity_native.dll" ^
 "%~dp0slang_unity.cpp" ^
 /link /SECTION:.slushare,RWS
exit /b %ERRORLEVEL%
