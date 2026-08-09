@echo off
setlocal

rem ============================================================
rem Compila setup.iss (nella stessa cartella di questo bat)
rem con output nella sottocartella dist
rem ============================================================

set "ISCC="

if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if not defined ISCC if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"

if not defined ISCC (
    echo.
    echo [ERRORE] ISCC.exe non trovato nei percorsi standard.
    echo Modifica questo file impostando manualmente il percorso di ISCC.exe.
    echo.
    pause
    exit /b 1
)

echo Compilazione in corso con: %ISCC%
echo Output: %~dp0dist
echo.

"%ISCC%" /O"%~dp0dist" "%~dp0setup.iss"

if errorlevel 1 (
    echo.
    echo [ERRORE] Compilazione fallita.
) else (
    echo.
    echo Compilazione completata correttamente.
)

pause
