# Copyright (c) 2026 Ray Klundt
# SPDX-License-Identifier: AGPL-3.0-or-later

<#
.SYNOPSIS
  Bootstraps the GitHub Actions OIDC deploy identity for one environment (D30/D37/D41).

.DESCRIPTION
  Idempotent, parameterized, operator-run "seed" script. It provisions the deploy identity
  that GitHub Actions uses to deploy to Azure -- the one piece of infra deliberately NOT in
  the Bicep (D41: it's a Microsoft Graph object, not ARM, and it's the bootstrap credential the
  Bicep itself runs under). Run once per environment by an operator with their own credentials.

  BIG PICTURE (plain English, if you're new to this):
    - The problem: GitHub Actions needs PERMISSION to deploy our app to Azure. The naive way is to
      store an Azure password in the repo's CI -- on a PUBLIC repo, a leak waiting to happen.
    - The fix (OIDC federation): instead of a stored secret, Actions hands Azure a short-lived signed
      token proving "this is OUR repo on the develop branch"; Azure trusts it (via the rule steps 1-3
      set up) and hands back a short-lived deploy token. Nothing long-lived exists to leak.
    - Jargon decoder: "app registration" = an identity in Azure's directory; "service principal" =
      that identity's account in our tenant; "federated credential" = the trust rule; step 4 gives that
      identity deploy rights to exactly ONE resource group (not the whole subscription).
    - Not deploy-related: the two "connection strings" (step 6) are just runtime settings the app reads
      (storage + telemetry) -- stored as GitHub secrets so CI can put them in the app's config later.

  STEPS (what -> why). Each step is check-then-create, so the whole script is idempotent:
    1. Entra app registration   -> the identity GitHub Actions will act as (D30).
    2. Service principal         -> the app's usable instance in this tenant; RBAC attaches to it.
    3. Federated credential      -> the OIDC trust "Actions on <repo>@<branch> may BE this identity",
                                    with NO client secret to leak (D30). This is why we use OIDC at all.
    4. Contributor on the env RG -> the identity's ONLY permission, scoped to one resource group, never
                                    the subscription (D7). It can deploy to this env and nothing else.
    5. GitHub repo VARIABLES     -> AZURE_CLIENT_ID / TENANT_ID / SUBSCRIPTION_ID. Plain identifiers (not
                                    secrets); azure/login@v2 uses them + the OIDC token to sign in.
    6. GitHub repo SECRETS       -> the storage + App Insights connection strings (fetched live from
                                    Azure, never pasted), which Sprint 2.2 wires into SWA app settings.
                                    The SWA deploy token is deliberately NOT set here (D37).
    7. Verify                    -> print the gh variable/secret lists so you can confirm what landed.

  RE-RUNNING / RECONCILE: safe anytime. Steps 1-4 check-then-create (no duplicates, no errors); steps
  5-6 overwrite the variables/secrets to current Azure values. So a re-run RECONCILES -- e.g. refreshes
  a rotated key, re-asserts the identity, or bootstraps prod (-Env prod) -- rather than breaking. It is
  a reconciler, NOT a drift reporter: it makes state correct but doesn't tell you what was wrong. (A
  read-only -CheckOnly mode could be added later, mirroring infra/bicep/drift-check.ps1, if wanted.)

  D37 is enforced by construction: the SWA deployment token is NEVER set as a GitHub secret here
  (it stays in gitignored notes as a break-glass fallback only). D17: no secrets/GUIDs are
  hardcoded -- identifiers come from `az account show`, connection strings are fetched live.

  Prod (Epic 9) re-runs this with prod parameters (-Env prod -Branch main). Whether prod reuses
  this same app (one identity, both RGs) or a separate prod app is the one-vs-two decision flagged
  for Epic 9 -- pass a distinct -AppDisplayName for the separate-app path.

.PARAMETER DryRun
  Print every create/set command instead of running it. Read-only checks still run. Use this
  first to preview exactly what will be created.

.EXAMPLE
  ./scripts/bootstrap-deploy-identity.ps1 -DryRun
  Preview the dev bootstrap (no changes).

.EXAMPLE
  ./scripts/bootstrap-deploy-identity.ps1
  Run the dev bootstrap for real.

.EXAMPLE
  ./scripts/bootstrap-deploy-identity.ps1 -Env prod -Branch main -ResourceGroup rg-music-slaylist-prod-use2
  Bootstrap prod (Epic 9), reusing the same deploy app.

.NOTES
  Requires `az login` (subscription that owns the env's RG) and `gh auth login` (write access to
  the repo). Cross-platform: runs on Windows PowerShell 5.1 and on pwsh 7 (Linux/macOS/CI).
  Creating an Entra app registration requires permission in your tenant (personal tenants allow it).
#>

param(
  [string]$Env = 'dev',
  [string]$Region = 'use2',
  [string]$Workload = 'music',
  [string]$App = 'slaylist',
  [string]$RepoOwner = 'rklundt',
  [string]$RepoName = 'SLAYList',
  # Git branch whose Actions runs may assume this identity. Defaults from env if not passed.
  [string]$Branch = '',
  # Entra app display name. Default is shared across environments (one identity); pass a distinct
  # name for the separate-prod-app path (the Epic 9 one-vs-two decision).
  [string]$AppDisplayName = 'slaylist-github-deploy',
  # Resource group to scope Contributor RBAC to. Defaults to the env's RG from the naming pattern.
  [string]$ResourceGroup = '',
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Info($m)  { Write-Host $m -ForegroundColor Cyan }
function Ok($m)    { Write-Host "  OK: $m" -ForegroundColor Green }
function Note($m)  { Write-Host "  $m" -ForegroundColor DarkGray }
function Do-Or-Show([string]$desc, [scriptblock]$action) {
  if ($DryRun) { Write-Host "  [dry-run] would: $desc" -ForegroundColor Yellow; return $null }
  return & $action
}

# --- Resolve branch + names (same naming pattern as the Bicep) ---
if (-not $Branch) { $Branch = if ($Env -eq 'prod') { 'main' } else { 'develop' } }
if (-not $ResourceGroup) { $ResourceGroup = "rg-$Workload-$App-$Env-$Region" }
$appInsightsName = "appi-$Workload-$App-$Env-$Region"

# storage account name with the same length-aware fallback as naming.bicep (<= 24 chars)
$stFull = ("st$Workload$App$Env$Region").ToLower()
$stNoWorkload = ("st$App$Env$Region").ToLower()
$stMinimal = ("st$App$Env").ToLower()
if ($stFull.Length -le 24) { $storageName = $stFull }
elseif ($stNoWorkload.Length -le 24) { $storageName = $stNoWorkload }
else { $storageName = $stMinimal }

# Note: ${RepoName} is brace-delimited because a bare "$RepoName:ref" makes PowerShell parse
# the ":ref" as a variable scope qualifier and silently drop it (broken OIDC subject).
$fedSubject = "repo:$RepoOwner/${RepoName}:ref:refs/heads/$Branch"
$fedName = "github-$RepoOwner-$RepoName-$Branch"
$ghRepo = "$RepoOwner/$RepoName"

Info "=== Bootstrap deploy identity: env=$Env, branch=$Branch ==="
Note "App: $AppDisplayName | RG (Contributor scope): $ResourceGroup"
Note "Federated subject: $fedSubject"
Note "Storage: $storageName | App Insights: $appInsightsName | Repo: $ghRepo"
if ($DryRun) { Write-Host "(DRY RUN -- no changes will be made)" -ForegroundColor Yellow }
Write-Host ""

# --- Preflight: az + gh authenticated ---
Info "Preflight: checking az + gh sessions"
$acct = az account show --only-show-errors 2>$null | ConvertFrom-Json
if (-not $acct) { Write-Error "Not logged in to az. Run: az login (and az account set --subscription <id>)."; exit 2 }
$subId = $acct.id
$tenantId = $acct.tenantId
Ok "az: $($acct.user.name) / sub $($acct.name)"
gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Error "Not logged in to gh. Run: gh auth login."; exit 2 }
Ok "gh: authenticated"
Write-Host ""

# --- 1. Entra app registration (idempotent) ---
Info "1. Entra app registration '$AppDisplayName'"
$appId = az ad app list --display-name $AppDisplayName --query "[0].appId" -o tsv --only-show-errors 2>$null
if ($appId) {
  Ok "exists (appId $appId)"
} else {
  $appId = Do-Or-Show "az ad app create --display-name $AppDisplayName" {
    az ad app create --display-name $AppDisplayName --query appId -o tsv --only-show-errors
  }
  if (-not $DryRun) { Ok "created (appId $appId)" }
}

# --- 2. Service principal for the app (RBAC assignee) ---
Info "2. Service principal"
if ($appId) {
  $spExists = az ad sp show --id $appId --query id -o tsv --only-show-errors 2>$null
  if ($spExists) { Ok "exists" }
  else { Do-Or-Show "az ad sp create --id $appId" { az ad sp create --id $appId --only-show-errors | Out-Null }; if (-not $DryRun) { Ok "created" } }
}

# --- 3. Federated credential (NO client secret) ---
Info "3. Federated credential for $fedSubject"
$fedExists = $null
if ($appId) {
  $fedExists = az ad app federated-credential list --id $appId --query "[?subject=='$fedSubject'].name" -o tsv --only-show-errors 2>$null
}
if ($fedExists) {
  Ok "exists ($fedExists)"
} else {
  $fedJson = '{"name":"' + $fedName + '","issuer":"https://token.actions.githubusercontent.com","subject":"' + $fedSubject + '","audiences":["api://AzureADTokenExchange"]}'
  Do-Or-Show "az ad app federated-credential create (subject $fedSubject)" {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "fedcred-$Env.json"
    Set-Content -Path $tmp -Value $fedJson -Encoding ascii
    az ad app federated-credential create --id $appId --parameters "@$tmp" --only-show-errors | Out-Null
    Remove-Item $tmp -Force
  }
  if (-not $DryRun) { Ok "created (no client secret)" }
}

# --- 4. Contributor RBAC on the env RG ONLY (D7) ---
Info "4. Contributor on $ResourceGroup (RG scope only, never subscription)"
$rgScope = "/subscriptions/$subId/resourceGroups/$ResourceGroup"
$haveRole = $null
if ($appId) {
  $haveRole = az role assignment list --assignee $appId --scope $rgScope --role Contributor --query "[0].id" -o tsv --only-show-errors 2>$null
}
if ($haveRole) {
  Ok "already assigned"
} else {
  Do-Or-Show "az role assignment create --role Contributor --scope $rgScope" {
    az role assignment create --assignee $appId --role Contributor --scope $rgScope --only-show-errors | Out-Null
  }
  if (-not $DryRun) { Ok "assigned" }
}

# --- 5. GitHub repo variables (non-secret identifiers) ---
Info "5. GitHub repo variables (client/tenant/subscription IDs)"
$vars = @{ 'AZURE_CLIENT_ID' = $appId; 'AZURE_TENANT_ID' = $tenantId; 'AZURE_SUBSCRIPTION_ID' = $subId }
foreach ($k in $vars.Keys) {
  Do-Or-Show "gh variable set $k" { gh variable set $k --repo $ghRepo --body $vars[$k] 2>$null | Out-Null }
  if (-not $DryRun) { Ok "$k set" }
}

# --- 6. GitHub repo secrets (fetched live from Azure, piped via stdin) ---
Info "6. GitHub repo secrets (storage + App Insights connection strings)"
Note "D37: the SWA deployment token is intentionally NOT set here -- break-glass only, gitignored notes."
# storage connection string (D25 -- SWA managed-functions API uses connection-string auth)
$stConn = az storage account show-connection-string -n $storageName -g $ResourceGroup --query connectionString -o tsv --only-show-errors 2>$null
if ($stConn) {
  Do-Or-Show "gh secret set AZURE_STORAGE_CONNECTION_STRING (value piped, not shown)" {
    $stConn | gh secret set AZURE_STORAGE_CONNECTION_STRING --repo $ghRepo 2>$null
  }
  if (-not $DryRun) { Ok "AZURE_STORAGE_CONNECTION_STRING set" }
} else { Note "WARN: could not fetch storage connection string for $storageName (skipped)" }
# App Insights connection string (D24) -- via generic resource show to avoid the app-insights extension
$aiConn = az resource show -g $ResourceGroup -n $appInsightsName --resource-type "Microsoft.Insights/components" --query "properties.ConnectionString" -o tsv --only-show-errors 2>$null
if ($aiConn) {
  Do-Or-Show "gh secret set APPINSIGHTS_CONNECTION_STRING (value piped, not shown)" {
    $aiConn | gh secret set APPINSIGHTS_CONNECTION_STRING --repo $ghRepo 2>$null
  }
  if (-not $DryRun) { Ok "APPINSIGHTS_CONNECTION_STRING set" }
} else { Note "WARN: could not fetch App Insights connection string for $appInsightsName (skipped)" }

# --- 7. Verify + summary ---
Write-Host ""
Info "=== Verify (D37: secrets must be the 2 connection strings only -- no SWA deploy token) ==="
if ($DryRun) {
  Write-Host "(dry-run: skipping live verification)" -ForegroundColor Yellow
} else {
  Write-Host "-- gh variable list --" -ForegroundColor DarkGray
  gh variable list --repo $ghRepo 2>$null
  Write-Host "-- gh secret list --" -ForegroundColor DarkGray
  gh secret list --repo $ghRepo 2>$null
  Write-Host ""
  Ok "Bootstrap complete for env=$Env. Sprint 2.2's workflow consumes AZURE_CLIENT_ID/TENANT_ID/"
  Note "SUBSCRIPTION_ID via azure/login@v2, and the two connection-string secrets via SWA app settings."
  Note "Record the gh variable/secret list in the gitignored infra/<env>-resources.md attestation."
}
