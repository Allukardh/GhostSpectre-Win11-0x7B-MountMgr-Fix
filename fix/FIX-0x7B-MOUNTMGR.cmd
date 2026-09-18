@echo off
setlocal EnableExtensions EnableDelayedExpansion
title FIX 0x7B - mountmgr recovery

echo ============================================================
echo  FIX 0x7B - MOUNTMGR RECOVERY
echo  Use from WinPE / Ghost Boot CMD as Administrator
echo ============================================================
echo.
echo This script ONLY repairs the specific case where:
echo   - Windows has INACCESSIBLE_BOOT_DEVICE 0x7B
echo   - mountmgr.sys exists
echo   - Services\mountmgr is missing in the offline SYSTEM hive
echo.
echo It does NOT touch partitions, GPT, BCD, filesystems, or user data.
echo.

set "WINVOL="

rem Optional argument: FIX-0x7B-MOUNTMGR.cmd C:
if not "%~1"=="" (
    set "WINVOL=%~1"
    if not "!WINVOL:~-1!"==":" set "WINVOL=!WINVOL!:"
    goto :validate
)

rem Auto-detect a unique Windows installation.
set /a COUNT=0
for %%D in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist "%%D:\Windows\System32\Config\SYSTEM" (
        if exist "%%D:\Windows\System32\drivers\mountmgr.sys" (
            set /a COUNT+=1
            set "WINVOL=%%D:"
            set "CAND!COUNT!=%%D:"
        )
    )
)

if !COUNT! EQU 0 (
    echo ERROR: No Windows installation with mountmgr.sys was found.
    echo Run the script with the Windows drive explicitly, for example:
    echo   %~nx0 C:
    exit /b 2
)

if !COUNT! GTR 1 (
    echo ERROR: More than one Windows installation was found:
    for /L %%N in (1,1,!COUNT!) do echo   !CAND%%N!
    echo.
    echo Rerun specifying the correct Windows drive, for example:
    echo   %~nx0 C:
    exit /b 2
)

:validate
if not exist "!WINVOL!\Windows\System32\Config\SYSTEM" (
    echo ERROR: !WINVOL!\Windows\System32\Config\SYSTEM was not found.
    exit /b 2
)

if not exist "!WINVOL!\Windows\System32\drivers\mountmgr.sys" (
    echo ERROR: mountmgr.sys is missing from !WINVOL!\Windows\System32\drivers
    echo This is NOT the registry-only failure repaired by this script.
    exit /b 2
)

echo Windows detected: !WINVOL!
echo.

rem Use a private temporary hive name to avoid conflicts with OFFSYS.
reg load HKLM\FIX7B "!WINVOL!\Windows\System32\Config\SYSTEM" >nul 2>&1
if errorlevel 1 (
    echo ERROR: Could not load the offline SYSTEM hive.
    echo Make sure it is not already mounted by another recovery command.
    exit /b 3
)

rem Read the active ControlSet from HKLM\SYSTEM\Select.
set "CURHEX="
for /f "tokens=3" %%A in ('reg query "HKLM\FIX7B\Select" /v Current 2^>nul') do set "CURHEX=%%A"

if not defined CURHEX (
    echo ERROR: Could not determine Select\Current.
    goto :fail
)

set /a CURDEC=!CURHEX!
set "PAD=00!CURDEC!"
set "CS=ControlSet!PAD:~-3!"

echo Active control set: !CS!
echo.

rem Safety check: do not overwrite a service that already exists.
reg query "HKLM\FIX7B\!CS!\Services\mountmgr" >nul 2>&1
if not errorlevel 1 (
    echo mountmgr already exists in !CS!.
    echo.
    reg query "HKLM\FIX7B\!CS!\Services\mountmgr"
    echo.
    echo No changes were made. This exact repair is not indicated.
    goto :done
)

echo CONFIRMED: Services\mountmgr is MISSING.
echo Creating a full SYSTEM hive backup before repair...
reg save HKLM\FIX7B "!WINVOL!\SYSTEM-before-mountmgr.hiv" /y >nul 2>&1
if errorlevel 1 (
    echo ERROR: Could not save the SYSTEM hive backup.
    goto :fail
)

echo Backup saved as:
echo   !WINVOL!\SYSTEM-before-mountmgr.hiv
echo.

rem Prefer copying the known-good mountmgr service definition from the running WinPE.
reg query "HKLM\SYSTEM\CurrentControlSet\Services\mountmgr" >nul 2>&1
if not errorlevel 1 (
    echo Copying mountmgr service definition from the running WinPE...
    reg copy "HKLM\SYSTEM\CurrentControlSet\Services\mountmgr" "HKLM\FIX7B\!CS!\Services\mountmgr" /s /f >nul
    if errorlevel 1 goto :fail_after_backup
) else (
    echo WinPE mountmgr key not found. Using standard Microsoft service values...
    reg add "HKLM\FIX7B\!CS!\Services\mountmgr" /v Description  /t REG_SZ        /d "@%%SystemRoot%%\system32\drivers\mountmgr.sys,-101" /f >nul
    if errorlevel 1 goto :fail_after_backup
    reg add "HKLM\FIX7B\!CS!\Services\mountmgr" /v DisplayName  /t REG_SZ        /d "@%%SystemRoot%%\system32\drivers\mountmgr.sys,-100" /f >nul
    if errorlevel 1 goto :fail_after_backup
    reg add "HKLM\FIX7B\!CS!\Services\mountmgr" /v ErrorControl /t REG_DWORD     /d 3 /f >nul
    if errorlevel 1 goto :fail_after_backup
    reg add "HKLM\FIX7B\!CS!\Services\mountmgr" /v Group        /t REG_SZ        /d "System Bus Extender" /f >nul
    if errorlevel 1 goto :fail_after_backup
    reg add "HKLM\FIX7B\!CS!\Services\mountmgr" /v ImagePath    /t REG_EXPAND_SZ /d "System32\drivers\mountmgr.sys" /f >nul
    if errorlevel 1 goto :fail_after_backup
    reg add "HKLM\FIX7B\!CS!\Services\mountmgr" /v Start        /t REG_DWORD     /d 0 /f >nul
    if errorlevel 1 goto :fail_after_backup
    reg add "HKLM\FIX7B\!CS!\Services\mountmgr" /v Type         /t REG_DWORD     /d 1 /f >nul
    if errorlevel 1 goto :fail_after_backup
)

echo.
echo Verification:
reg query "HKLM\FIX7B\!CS!\Services\mountmgr"
if errorlevel 1 goto :fail_after_backup

echo.
echo Repair completed successfully.
echo No BCD/GPT/partition changes were made.
echo.

:done
reg unload HKLM\FIX7B >nul 2>&1
if errorlevel 1 (
    echo WARNING: Could not unload HKLM\FIX7B automatically.
    echo Run manually:
    echo   reg unload HKLM\FIX7B
    exit /b 4
)

echo Offline SYSTEM hive unloaded successfully.
echo.
echo Now shut the PC down completely and power it on again.
echo If Windows boots, verify in an elevated CMD:
echo   sc query mountmgr
echo   reg query HKLM\SYSTEM\CurrentControlSet\Services\mountmgr
echo.
exit /b 0

:fail_after_backup
echo.
echo ERROR: Repair failed after the backup was created.
echo Backup is at:
echo   !WINVOL!\SYSTEM-before-mountmgr.hiv
goto :fail

:fail
reg unload HKLM\FIX7B >nul 2>&1
echo No further changes will be attempted.
exit /b 5
