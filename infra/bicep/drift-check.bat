@echo off
REM Copyright (c) 2026 Ray Klundt
REM SPDX-License-Identifier: AGPL-3.0-or-later
REM Convenience wrapper for drift-check.ps1. cmd has no PowerShell execution-policy gate,
REM so this runs the script with -ExecutionPolicy Bypass for this single call (no need to
REM change your machine policy via Set-ExecutionPolicy). Arguments pass straight through.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0drift-check.ps1" %*
