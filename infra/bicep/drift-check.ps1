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
    - REVIEW properties what-if reports OPAQUELY (it can't diff them) where a real change could
             hide: the Container App template (image, cpu/mem, env) and diagnostic-setting
             log/metric categories. NOT counted as drift, but ALWAYS surfaced as a REVIEW note
             so the check never silently misses them - confirm those by eye if you changed them.
    - noise  computed/read-only/platform-default fields that what-if always shows but ARM
             never actually changes (stableInboundIP, runningStatus, encryption-scope
             defaults, reference() expressions that resolve to the same value, etc.), plus
             budget date-format normalization. Silently ignored (shown only with -ShowNoise).

  Exit code 0 = CLEAN (no drift; REVIEW items don't fail it), 1 = DRIFT detected (so this can
  gate a future CI workflow), 2 = error.

  LIMITATION: what-if cannot diff array/reference-typed properties, so this check cannot itself
  verify the Container App image/resources/env or the diagnostic-setting categories - it flags
  them in the REVIEW note rather than vouching for them. The real guard for those is the
  "update the Bicep in the same sprint" discipline (CLAUDE.md guardrail) + code review. This
  tool catches high-blast-radius scalar drift (SKU, retention, network/public access, RBAC
  presence, tags); it is not a complete substitute for that discipline.

.EXAMPLE
  ./infra/bicep/drift-check.ps1
  Zero-arg run against dev. The budget notification email is auto-detected from the live
  budget, so nothing needs to be passed. Prints CLEAN or the DRIFT list.

.EXAMPLE
  ./infra/bicep/drift-check.ps1 -ShowNoise
  Same as above, but also lists the filtered what-if noise (in gray) so you can audit that
  the noise filter isn't masking something real.

.EXAMPLE
  ./infra/bicep/drift-check.ps1 -Env prod -ResourceGroup rg-music-slaylist-prod-use2 -BudgetStartDate 2026-09-01
  Check prod (Sprint 9.1). For a brand-new env whose budget does not exist yet, also pass
  -NotificationEmail (auto-detect needs an existing budget to read from).

.NOTES
  Read-only: runs `az deployment group what-if` only; never deploys or mutates anything.
  Requires `az` logged into the target subscription. On Windows, if PowerShell's execution
  policy blocks the script, run the sibling drift-check.bat wrapper instead.
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
  # SWA computed / read-only. (deploymentAuthPolicy is deliberately NOT here: we pin it in
  # Bicep, so post-reconcile it matches and never appears; if it ever shows up in what-if again
  # that's a real portal change we WANT surfaced as drift.)
  'stableInboundIP', 'trafficSplitting',
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
  'endDate', 'startDate', 'contactGroups'
)

# Leaves that what-if reports OPAQUELY (it can't actually diff them), where a real change COULD
# hide: the Container App template array (image, cpu/mem, env vars) and diagnostic-setting log/
# metric category arrays. These are NOT silently ignored like $NoiseLeaves — they're surfaced
# as an always-shown REVIEW note so the check never silently misses a container-image or
# diag-category change. They do NOT count as drift (they'd appear on every run), but they tell
# you "this tool can't see these; confirm them yourself or via the same-sprint Bicep discipline."
$ReviewLeaves = @('containers', 'logs', 'metrics')

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
$review = [System.Collections.Generic.List[string]]::new()

# Renders one what-if delta as a single line: "<resource>  ::  <property path>  (<before> to <after>)".
# Long before/after values (e.g. a reference() expression or a connection string) are truncated
# to 40 chars so the output stays one line per delta.
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
        if ($ReviewLeaves -contains $leaf) {
          $review.Add("MODIFY  $(Format-Delta $rid $d)")
        }
        elseif ($NoiseLeaves -notcontains $leaf) {
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

# REVIEW is ALWAYS shown (not gated on -ShowNoise): what-if can't diff these, so the check can't
# vouch for them. This is the one thing the tool genuinely can't see, so it must say so every run.
if ($review.Count -gt 0) {
  Write-Host ""
  Write-Host "REVIEW ($($review.Count)): what-if cannot diff these, so this check does NOT cover them -" -ForegroundColor Magenta
  Write-Host "  the Container App image/resources/env and diagnostic-setting categories. Confirm those" -ForegroundColor Magenta
  Write-Host "  manually if you changed them (the same-sprint Bicep discipline is the real guard)." -ForegroundColor Magenta
  if ($ShowNoise) { $review | ForEach-Object { Write-Host "  $_" -ForegroundColor Magenta } }
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
