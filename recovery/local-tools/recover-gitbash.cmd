@echo off
chcp 65001 >nul
setlocal
set "BASH=C:\Program Files\Git\bin\bash.exe"
if not exist "%BASH%" set "BASH=C:\Program Files\Git\usr\bin\bash.exe"
if not exist "%BASH%" (
  echo Git Bash not found. Please run recover-run.cmd instead.
  pause
  exit /b 1
)
if not exist "%TEMP%\owrt\rsh.sh" (
  echo Saved SSH helper not found at %TEMP%\owrt\rsh.sh
  echo Please run recover-run.cmd instead.
  pause
  exit /b 1
)

rem 仓库根 = 本脚本所在目录的上两级（recovery\local-tools\..\..）
set "REPO=%~dp0..\.."
for /f "delims=" %%i in ('"%BASH%" -lc "cygpath -u \"%REPO%\""') do set "REPO_U=%%i"
"%BASH%" -lc "cd \"%REPO_U%\" && cat recovery/recover-now.sh | /tmp/owrt/rsh.sh 'cat > /tmp/recover-now.sh && ash /tmp/recover-now.sh'"
echo.
pause
