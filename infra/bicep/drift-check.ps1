# Copyright (c) 2026 Ray Klundt
# SPDX-License-Identifier: AGPL-3.0-or-later

<#
.SYNOPSIS
  Drift check: compares a live Azure resource group against the infra/bicep templates
  and reports CLEAN or the real drift, filtering out the perennial what-if noise.

.DESCRIPTION
  Wraps `az deployment group what-if` (read-only - changes nothing) and classifies every
  delta:
    - DRIFT  a resource the templates would CREATE (missing from live), or a MODIFY on a
             meaningful scalar property (SKU, retention, network access, public access,
             soft-delete, tags you did not intend, etc.). These are what you act on.
    - noise  computed/read-only/platform-default fields that what-if always shows but ARM
             never actually changes (stableInboundIP, runningStatus, encryption-scope
             defaults, etc.), plus budget date-format normalization. Silently ignored.

  Exit code 0 = CLEAN, 1 = DRIFT detected (so this can gate a future CI workflow), 2 = error.

  LIMITATION (read this): what-if reports array- and reference-typed properties opaquely - it
  canNOT diff diagnostic-setting log/metric CATEGORIES, the Container App CONTAINER IMAGE, or
  the CAE Log-Analytics customerId. This script therefore does NOT detect changes to those.
  For those, rely on the "update the Bicep in the same sprint" discipline (CLAUDE.md guardrail)
  and code review. This tool catches the high-blast-radius scalar drift; it is not a complete
  substitute for that discipline.

.EXAMPLE
  ./infra/bicep/drift-check.ps1 -NotificationEmail you@example.com
  (defaults target the dev RG; pass -Env prod -ResourceGroup rg-...-prod-use2 for prod)
#>

param(
  [string]$ResourceGroup = 'rg-music-slaylist-dev-use2',
  [string]$Env = 'dev',
  [string]$Region = 'use2',
  [string]$Workload = 'music',
  [string]$App = 'slaylist',
  # Optional. The Bicep requires a notificationEmail param (the budget uses it), but what-if
  # never sends anything. If omitted, it's auto-detected from the LIVE budget so it always
  # matches (a mismatched email would otherwise show as false "drift" on the budget). Only pass
  # it explicitly for a fresh env whose budget doesn't exist yet.
  [string]$NotificationEmail,
  # The dev budget's immutable start month. Pass the target env's own budget start on redeploy.
  [string]$BudgetStartDate = '2026-05-01',
  [string]$TemplateFile = "$PSScriptRoot/main.bicep",
  # Also print the filtered what-if noise (computed/read-only/unevaluatable deltas the check
  # ignores) under a separate heading, for auditing that the filter isn't hiding real drift.
  [switch]$ShowNoise
)

$ErrorActionPreference = 'Stop'

# Auto-detect the budget notification email from the live budget when not supplied, so it
# always matches and never shows as false drift. Falls back to a clear error for a fresh env.
if (-not $NotificationEmail) {
  $budgetName = "budget-$Workload-$App-$Env"
  $b = az consumption budget list --query "[?name=='$budgetName']" -o json --only-show-errors 2>$null | ConvertFrom-Json
  if ($b) {
    $firstNotif = $b[0].notifications.PSObject.Properties | Select-Object -First 1
    $NotificationEmail = $firstNotif.Value.contactEmails[0]
  }
  if (-not $NotificationEmail) {
    Write-Error "Could not auto-detect the notification email from budget '$budgetName' (does it exist?). Pass -NotificationEmail explicitly for a fresh environment."
    exit 2
  }
  Write-Host "Notification email auto-detected from live budget '$budgetName'." -ForegroundColor DarkGray
}

# Leaf property names that what-if always surfaces but ARM never actually changes (or cannot
# evaluate). Anything NOT in this set is treated as real drift. Keep this list tight - an
# over-broad allowlist hides genuine drift.
$NoiseLeaves = @(
  # tags the templates re-assert (already correct after the Sprint 1.7 reconcile)
  'managed-by', 'region', 'cost-center',
  # SWA computed / read-only
  'stableInboundIP', 'trafficSplitting', 'deploymentAuthPolicy',
  # Container App computed / default-applied
  'runningStatus', 'maxInactiveRevisions',
  # Container Apps Environment default sub-objects + unevaluatable reference()
  'peerAuthentication', 'peerTrafficConfiguration', 'customerId',
  # role-assignment what-if artifacts: principalId is a reference() what-if can't resolve
  # (resolves to the same MI guid at deploy); principalType reads back empty but is set to
  # ServicePrincipal. Neither is real drift for our MI-scoped assignments.
  'principalId', 'principalType',
  # Storage container / blob-service platform defaults
  'defaultEncryptionScope', 'denyEncryptionScopeOverride', 'allowPermanentDelete',
  # LAW features (what-if marks NoEffect)
  'features',
  # budget date fields (immutable / format-normalized) + decoupled action-group ref
  'endDate', 'startDate', 'contactGroups',
  # array-typed props what-if reports opaquely (see LIMITATION above)
  'logs', 'metrics', 'containers'
)

Write-Host "Running what-if against $ResourceGroup (read-only)..." -ForegroundColor Cyan

$raw = az deployment group what-if `
  --resource-group $ResourceGroup `
  --template-file $TemplateFile `
  --parameters env=$Env region=$Region workload=$Workload app=$App `
               notificationEmail=$NotificationEmail budgetStartDate=$BudgetStartDate `
  --no-pretty-print --only-show-errors 2>$null

if (-not $raw) { Write-Error "what-if produced no output. Check az login / subscription / params."; exit 2 }

$changes = ($raw | ConvertFrom-Json).changes
$drift = [System.Collections.Generic.List[string]]::new()
$noise = [System.Collections.Generic.List[string]]::new()

function Format-Delta($rid, $d) {
  $b = "$($d.before)"; if ($b.Length -gt 40) { $b = $b.Substring(0, 40) }
  $a = "$($d.after)"; if ($a.Length -gt 40) { $a = $a.Substring(0, 40) }
  return "$rid  ::  $($d.path)  ($b to $a)"
}

foreach ($c in $changes) {
  $rid = ($c.resourceId -split '/providers/')[-1]
  switch ($c.changeType) {
    'Ignore' { $noise.Add("IGNORE  $rid  (resource not managed by these templates)") }
    'Create' {
      # Role-assignment creates were the only expected Creates, and only BEFORE the reconcile.
      # After Sprint 1.7 they exist with deterministic GUIDs, so any Create now means a managed
      # resource is missing from live = drift.
      $drift.Add("CREATE  $rid  (templates would create this; it is missing from live)")
    }
    'Modify' {
      foreach ($d in $c.delta) {
        $leaf = ($d.path -split '\.')[-1]
        # the whole-object 'properties' delete on queueServices is legacy classic-logging noise
        if ($d.path -eq 'properties' -and $rid -like '*queueServices*') { $noise.Add("MODIFY  $(Format-Delta $rid $d)"); continue }
        if ($NoiseLeaves -notcontains $leaf) {
          $drift.Add("MODIFY  $(Format-Delta $rid $d)")
        }
        else {
          $noise.Add("MODIFY  $(Format-Delta $rid $d)")
        }
      }
    }
  }
}

if ($ShowNoise -and $noise.Count -gt 0) {
  Write-Host ""
  Write-Host "Filtered noise ($($noise.Count) item(s) - computed/read-only/unevaluatable, NOT drift):" -ForegroundColor DarkGray
  $noise | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
}

Write-Host ""
if ($drift.Count -eq 0) {
  Write-Host "CLEAN - live matches the Bicep (only known what-if noise present)." -ForegroundColor Green
  exit 0
}
else {
  Write-Host "DRIFT DETECTED ($($drift.Count) item(s)):" -ForegroundColor Yellow
  $drift | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
  Write-Host ""
  Write-Host "Reconcile by either (a) updating the Bicep to match the intended live state and" -ForegroundColor Yellow
  Write-Host "redeploying, or (b) redeploying the Bicep to revert an unintended portal change." -ForegroundColor Yellow
  exit 1
}
