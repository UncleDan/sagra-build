@echo off
setlocal enabledelayedexpansion

rem ============================================================
rem Compila setup.iss (nella stessa cartella di questo bat)
rem con output nella sottocartella dist.
rem Se sys\ e' vuota, la popola dai runtime VB6 di SysWOW64.
rem ============================================================

set "BASE=%~dp0"
set "SYSDIR=%BASE%sys"

rem --- elenco runtime VB6 richiesti ---
set "RUNTIME=msvbvm60.dll oleaut32.dll olepro32.dll asycfilt.dll comcat.dll stdole2.tlb MSSTDFMT.DLL COMDLG32.ocx MsComCtl.ocx MSCOMCT2.ocx MSFLXGRD.ocx MSHFLXGD.ocx COMCTL32.ocx"

rem ------------------------------------------------------------
rem 1. Popolamento automatico di sys\
rem ------------------------------------------------------------
if not exist "%SYSDIR%" mkdir "%SYSDIR%"

set "MANCA="
for %%F in (%RUNTIME%) do (
    if not exist "%SYSDIR%\%%F" set "MANCA=1"
)

if defined MANCA (
    echo.
    echo Runtime VB6 mancanti in sys\: li copio dal sistema.

    rem su Windows 64 bit i componenti a 32 bit stanno in SysWOW64
    set "SRC=%SystemRoot%\SysWOW64"
    if not exist "!SRC!\msvbvm60.dll" set "SRC=%SystemRoot%\System32"

    if not exist "!SRC!\msvbvm60.dll" (
        echo.
        echo [ERRORE] msvbvm60.dll non trovato ne' in SysWOW64 ne' in System32.
        echo Installa i runtime VB6 su questa macchina, oppure copia
        echo manualmente i file in: %SYSDIR%
        echo.
        pause
        exit /b 1
    )

    echo Sorgente: !SRC!
    for %%F in (%RUNTIME%) do (
        if not exist "%SYSDIR%\%%F" (
            if exist "!SRC!\%%F" (
                copy /Y "!SRC!\%%F" "%SYSDIR%\" >nul
                echo   [copiato]  %%F
            ) else (
                echo   [MANCANTE] %%F  ^(non presente in !SRC!^)
            )
        )
    )
    echo.
)

rem ------------------------------------------------------------
rem 2. Individuazione compilatore Inno Setup
rem ------------------------------------------------------------
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

rem ------------------------------------------------------------
rem 3. Compilazione
rem ------------------------------------------------------------
echo Compilazione con: %ISCC%
echo Output: %BASE%dist
echo.

"%ISCC%" /O"%BASE%dist" "%BASE%setup.iss"

if errorlevel 1 (
    echo.
    echo [ERRORE] Compilazione fallita.
) else (
    echo.
    echo Compilazione completata correttamente.
)

pause
