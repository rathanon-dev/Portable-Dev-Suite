@echo off
setlocal enabledelayedexpansion

:: ============================================================================
:: ⚙️ USER CONFIGURATION AREA (แก้ไขเฉพาะส่วนนี้เท่านั้น)
:: ============================================================================

:: 1. Setup Parameters for setup.ps1:
::    [-e]         : Load Environment (PATH + Alias) into active shell
::    [-c]         : Check Hardware & System Diagnostics
::    [-h]         : Show Help Menu
::    [-i all -y]  : Auto-install full stack (Python, Git, CUDA, cuDNN)
set "PARAM=-e"


:: 2. Target Workspace Folder (Relative path inside project root)
::    Leave empty "" to stay at root, or specify subfolder (e.g. workspace)
set "TARGET_WORKSPACE=workspace"


:: 3. Execution Command (Runs automatically ONLY when PARAM includes -e)
::    Leave empty "" if you only want an open Terminal Shell without auto-running app
set "EXEC_COMMAND=python app.py"


:: ============================================================================
:: 🚫 SYSTEM LOGIC ENGINE (ห้ามแก้ไขโค้ดตั้งแต่บรรทัดนี้เป็นต้นไป)
:: ============================================================================

set "PYTHONUTF8=1"
set "SCRIPT_ROOT=%~dp0"
set "SETUP_PS1=%SCRIPT_ROOT%setup.ps1"

:: Override PARAM if user explicitly passes CLI arguments (e.g. start.bat -c)
if not "%~1"=="" set "PARAM=%*"

:: Check if PARAM contains "-e" flag
echo %PARAM% | findstr /i /c:"-e" >nul
if %errorlevel%==0 (
    :: ------------------------------------------------------------------------
    :: MODE 1: Environment Live Shell Mode (-e)
    :: Inject PATH -> Change Directory -> Execute Command
    :: ------------------------------------------------------------------------
    powershell -NoProfile -ExecutionPolicy Bypass -NoExit -Command ^
        "& '%SETUP_PS1%' %PARAM%; " ^
        "if ('%TARGET_WORKSPACE%' -ne '' -and (Test-Path '%SCRIPT_ROOT%%TARGET_WORKSPACE%')) { Set-Location '%SCRIPT_ROOT%%TARGET_WORKSPACE%' }; " ^
        "if ('%EXEC_COMMAND%' -ne '') { Write-Host ' [LAUNCH] Executing: %EXEC_COMMAND%' -ForegroundColor Cyan; %EXEC_COMMAND% }"
) else (
    :: ------------------------------------------------------------------------
    :: MODE 2: System Management Mode (-c, -h, -i, etc.)
    :: Run Setup Task ONLY -> Skip Workspace & Skip Exec Command
    :: ------------------------------------------------------------------------
    powershell -NoProfile -ExecutionPolicy Bypass -NoExit -Command "& '%SETUP_PS1%' %PARAM%"
)