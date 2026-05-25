#!/usr/bin/env bash
# Copyright (c) 2026 Ray Klundt
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Local dev kickoff for SLAYList (Sprint 0.3+).
#
# Tracked, portable, machine-agnostic version. Resolves the project root from
# the script's own location, so it works regardless of where you cloned the
# repo. If you want a per-machine override (different ports, extra steps, etc.),
# create `dev.sh` at the repo root — that path is gitignored.
#
# What it does:
#   1. Checks ports 5193 (Vite), 7071 (func), 10000/10001/10002 (Azurite) for
#      orphaned listeners from prior crashed/aborted runs.
#   2. Force-kills anything holding them.
#   3. Waits 1000ms for OS-side socket teardown.
#   4. Verifies Node 22 / pnpm 11 / func 4 are on PATH (D18 + D34).
#   5. Runs `pnpm dev` (concurrently runs azurite + tsc-watch + func + vite).
#
# Browse http://localhost:5193 once "VITE ready" appears.
# Ctrl-C stops all four processes.

set -e

# Project root = directory containing this script's parent (since script is in /scripts).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PORTS=(5193 7071 10000 10001 10002)

cd "$PROJECT_ROOT" || { echo "ERROR: cannot cd to $PROJECT_ROOT"; exit 1; }

# --- 1 & 2: detect and kill orphaned port holders ---
echo "=== Checking for orphaned listeners on ports ${PORTS[*]} ==="
killed_any=0
for port in "${PORTS[@]}"; do
  pids=$(netstat -ano 2>/dev/null | grep -E "[ :]${port}[[:space:]].*LISTENING" | awk '{print $NF}' | sort -u)
  if [[ -z "$pids" ]]; then
    echo "  port $port: free"
    continue
  fi
  for pid in $pids; do
    if [[ "$pid" == "0" || "$pid" == "4" ]]; then
      continue
    fi
    echo "  port $port: held by PID $pid — killing"
    taskkill //F //PID "$pid" 2>&1 | head -1 || echo "    (taskkill failed; PID may be gone already)"
    killed_any=1
  done
done

# --- 3: short wait for sockets to drain ---
if [[ $killed_any -eq 1 ]]; then
  echo "=== Waiting 1000ms for sockets to release ==="
  sleep 1
fi

# --- 4: prerequisite versions ---
echo ""
echo "=== Prerequisite versions (D18: Node 22; D34: pnpm 11; func 4) ==="
node --version  || { echo "ERROR: node not found — install Node 22 LTS (use nvm/fnm to switch)"; exit 1; }
pnpm --version  || { echo "ERROR: pnpm not found — 'corepack enable && corepack prepare pnpm@latest --activate'"; exit 1; }
func --version  || { echo "ERROR: func not found — install Azure Functions Core Tools 4.x"; exit 1; }

# --- 5: start dev ---
echo ""
echo "=== cwd: $(pwd) ==="
echo "=== Starting dev (Ctrl-C to stop all) ==="
echo "    storage (Azurite): :10000 / :10001 / :10002 (silent)"
echo "    api (func):        http://localhost:7071"
echo "    web (Vite):        http://localhost:5193   <-- browse this"
echo "    Vite proxies /api/* to localhost:7071"
echo ""

pnpm dev
