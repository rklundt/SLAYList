@echo off
REM Copyright (c) 2026 Ray Klundt
REM SPDX-License-Identifier: AGPL-3.0-or-later
REM
REM Windows-native parallel to scripts/dev.sh: clears orphaned dev-server ports,
REM checks prerequisites, then runs `pnpm dev`. Run from anywhere (cd's to repo root).
REM For the bash version (Git Bash), use scripts/dev.sh instead - same behavior.
REM
REM GOTCHA: pnpm resolves to pnpm.cmd (a batch file). A batch file calling another
REM batch file WITHOUT `call` does not return - control transfers and this script ends.
REM So every pnpm invocation below uses `call pnpm ...`. node/func are .exe (no call needed).
setlocal enabledelayedexpansion
cd /d "%~dp0.."

echo === Checking for orphaned listeners on dev ports ===
for %%p in (5193 7071 10000 10001 10002) do (
  set "held="
  for /f "tokens=5" %%a in ('netstat -ano ^| findstr "LISTENING" ^| findstr ":%%p"') do (
    if not "%%a"=="0" if not "%%a"=="4" (
      echo   port %%p: held by PID %%a - killing
      taskkill /F /PID %%a >nul 2>&1
      set "held=1"
    )
  )
  if not defined held echo   port %%p: free
)

echo.
echo === Prerequisite versions (D18: Node 22; D34: pnpm 11; func 4) ===
node --version || (echo ERROR: node not found - install Node 22 LTS & exit /b 1)
call pnpm --version || (echo ERROR: pnpm not found - run: corepack enable & exit /b 1)
func --version || (echo ERROR: func not found - install Azure Functions Core Tools 4.x & exit /b 1)

echo.
echo === Starting dev ^(Ctrl-C to stop all^) ===
echo     web ^(Vite^):  http://localhost:5193   ^<-- browse this
echo     api ^(func^):  http://localhost:7071
echo.
call pnpm dev
