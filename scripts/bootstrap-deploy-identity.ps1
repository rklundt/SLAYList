# Copyright (c) 2026 Ray Klundt
# SPDX-License-Identifier: AGPL-3.0-or-later

<#
.SYNOPSIS
  Bootstraps the GitHub Actions OIDC deploy identity for one environment (D30/D37/D41).

.DESCRIPTION
  Idempotent, parameterized, operator-run "seed" script. It provisions EVERYTHING GitHub Actions
  needs to deploy to one environment -- the deploy identity is the one piece of infra deliberately
  NOT in the Bicep (D41: it's a Microsoft Graph object, not ARM, and it's the bootstrap credential
  the Bicep itself runs under). Run once per environment by an operator with their own credentials.

  BIG PICTURE (plain English, if you're new to this):
    - The problem: GitHub Actions needs PERMISSION to deploy our app to Azure. The naive way is to
      store an Azure password in the repo's CI -- on a PUBLIC repo, a leak waiting to happen.
    - The fix (OIDC federation): instead of a stored secret, Actions hands Azure a short-lived signed
      token; Azure trusts it (via a "federated credential" rule) and hands back a short-lived deploy
      token. Nothing long-lived exists to leak.
    - Trust is keyed to a GitHub ENVIRONMENT, not a branch: the rule says "Actions deploying to the
      <env> environment may BE this identity". GitHub then controls WHICH branches may use that
      environment -- ANY branch for dev (so you can test deploys from a feature branch), only `main`
      for prod. This decouples deploy-trust from a single branch and properly gates prod.
    - Jargon decoder: "app registration" = an identity in Azure's directory; "service principal" =
      that identity's account in our tenant; "federated credential" = the trust rule; step 4 gives
      that identity deploy rights to exactly ONE resource group (not the whole subscription).

  STEPS (what -> why). Each step is check-then-create, so the whole script is idempotent:
    1. Entra app registration        -> the identity GitHub Actions will act as (D30).
    2. Service principal             -> the app's usable instance in this tenant; RBAC attaches to it.
    3. Federated credential (ENV)    -> the OIDC trust "Actions deploying to the <env> environment may
                                        BE this identity", with NO client secret (D30). Also removes any
                                        stale BRANCH-based credential left from the earlier approach.
    4. Contributor on the env RG     -> the identity's ONLY permission, scoped to one resource group,
                                        never the subscription (D7). Deploys to this env and nothing else.
    5. GitHub environment            -> creates the `<env>` environment and its deployment-branch policy:
                                        ANY branch for dev (easy testing), only `main` for prod (gate).
    6. Environment SECRETS (IDs)     -> AZURE_CLIENT_ID / TENANT_ID / SUBSCRIPTION_ID, scoped to the
                                        environment. They're really IDENTIFIERS, not secrets, but we store
                                        them as secrets on a PUBLIC repo so an accidental log echo can't
                                        become a recon breadcrumb (GitHub masks secrets, not variables).
    7. Environment SECRETS (config)  -> storage + App Insights connection strings (genuinely sensitive;
                                        fetched live, never pasted), environment-scoped. SWA deploy token
                                        is deliberately NOT set (D37). Both steps also delete any leftover
                                        REPO-scoped copies of these secrets (superseded by env-scoped).
    8. Verify                        -> print the environment + repo secret lists to confirm.

  RE-RUNNING / RECONCILE: safe anytime (check-then-create; secrets overwrite to current values). A
  re-run reconciles -- refreshes a rotated key, re-asserts the identity, or bootstraps prod
  (-Env prod). It is a reconciler, not a drift reporter.

  D37 enforced by construction: the SWA deploy token is NEVER set as a secret here. D17: no
  secrets/GUIDs hardcoded -- identifiers come from `az account show`, connection strings fetched live.
  SEPARATE app per environment (two-app model, D7): app is `slaylist-github-deploy-<env>`, so the dev
  identity holds dev-RG rights only and can never reach prod.

.PARAMETER DryRun
  Print every create/set command instead of running it. Read-only checks still run. Run this first.

.PARAMETER RunUpToStep
  Run only steps 1..N then stop (cautious, incremental). 0 (default) runs everything. Composes with
  -DryRun. Steps: 1 app, 2 SP, 3 federated cred, 4 RBAC, 5 GitHub env, 6 ID secrets, 7 config secrets,
  8 verify.

.EXAMPLE
  ./scripts/bootstrap-deploy-identity.ps1 -DryRun
  Preview the dev bootstrap (no changes).

.EXAMPLE
  ./scripts/bootstrap-deploy-identity.ps1 -RunUpToStep 5
  Cautiously run steps 1-5 (identity + RBAC + GitHub environment), then stop.

.EXAMPLE
  ./scripts/bootstrap-deploy-identity.ps1 -Env prod -ResourceGroup rg-music-slaylist-prod-use2
  Bootstrap prod (Epic 9) as a SEPARATE app, prod-RG-scoped, with the prod environment gated to `main`.

.NOTES
  Requires `az login` (subscription that owns the env's RG) and `gh auth login` (admin on the repo --
  creating environments needs repo admin). Cross-platform: Windows PowerShell 5.1 and pwsh 7.
  Creating an Entra app registration requires permission in your tenant (personal tenants allow it).
#>

param(
  [string]$Env = 'dev',
  [string]$Region = 'use2',
  [string]$Workload = 'music',
  [string]$App = 'slaylist',
  [string]$RepoOwner = 'rklundt',
  [string]$RepoName = 'SLAYList',
  # Entra app display name. Defaults to slaylist-github-deploy-<env> -- a SEPARATE app per environment
  # (two-app model, D7): the dev identity holds dev-RG rights only and can never reach prod.
  [string]$AppDisplayName = '',
  # Resource group to scope Contributor RBAC to. Defaults to the env's RG from the naming pattern.
  [string]$ResourceGroup = '',
  # Which branch may deploy to this env. Empty = ANY branch (dev). Defaults to 'main' for prod.
  # This is the GitHub environment's deployment-branch policy -- the prod gate.
  [string]$RestrictDeployToBranch = '',
  # Run only steps 1..N and stop. 0 = everything. Steps: 1 app, 2 SP, 3 fed cred, 4 RBAC,
  # 5 GitHub env, 6 ID secrets, 7 config secrets, 8 verify. Composes with -DryRun.
  [ValidateRange(0, 8)][int]$RunUpToStep = 0,
  [switch]$DryRun
)

# Continue, not Stop: az/gh write to stderr for ordinary conditions (e.g. "no SP found yet"); under
# Stop that would halt the script. We check results explicitly (if/$LASTEXITCODE) instead.
$ErrorActionPreference = 'Continue'

function Info($m)  { Write-Host $m -ForegroundColor Cyan }
function Ok($m)    { Write-Host "  OK: $m" -ForegroundColor Green }
function Note($m)  { Write-Host "  $m" -ForegroundColor DarkGray }
function Do-Or-Show([string]$desc, [scriptblock]$action) {
  if ($DryRun) { Write-Host "  [dry-run] would: $desc" -ForegroundColor Yellow; return $null }
  return & $action
}
# A failed CREATE no longer throws (ErrorActionPreference=Continue), so check $LASTEXITCODE after each.
function Assert-LastOk([string]$what) {
  if (-not $DryRun -and $LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: $what failed (exit code $LASTEXITCODE). Fix the cause and re-run (idempotent)." -ForegroundColor Red
    exit 1
  }
}
# -RunUpToStep gate: call before each step; the first step past the limit prints a note and exits 0.
function Stop-If-Past([int]$n) {
  if ($RunUpToStep -gt 0 -and $n -gt $RunUpToStep) {
    Write-Host ""
    Note "Stopped after step $RunUpToStep (-RunUpToStep $RunUpToStep). Re-run without it, or higher, to continue."
    exit 0
  }
}

# --- Resolve names (same naming pattern as the Bicep) ---
if (-not $AppDisplayName) { $AppDisplayName = "slaylist-github-deploy-$Env" }
if (-not $ResourceGroup) { $ResourceGroup = "rg-$Workload-$App-$Env-$Region" }
if (-not $RestrictDeployToBranch -and $Env -eq 'prod') { $RestrictDeployToBranch = 'main' }
$appInsightsName = "appi-$Workload-$App-$Env-$Region"

# storage account name with the same length-aware fallback as naming.bicep (<= 24 chars)
$stFull = ("st$Workload$App$Env$Region").ToLower()
$stNoWorkload = ("st$App$Env$Region").ToLower()
$stMinimal = ("st$App$Env").ToLower()
if ($stFull.Length -le 24) { $storageName = $stFull }
elseif ($stNoWorkload.Length -le 24) { $storageName = $stNoWorkload }
else { $storageName = $stMinimal }

# Environment-based federated subject (NOT branch-based). ${RepoName} is brace-delimited so a bare
# "$RepoName:environment" isn't parsed as a variable scope qualifier.
$fedSubject = "repo:$RepoOwner/${RepoName}:environment:$Env"
$fedName = "github-$RepoOwner-$RepoName-env-$Env"
$ghRepo = "$RepoOwner/$RepoName"
$idSecretNames = @('AZURE_CLIENT_ID', 'AZURE_TENANT_ID', 'AZURE_SUBSCRIPTION_ID')
$connSecretNames = @('AZURE_STORAGE_CONNECTION_STRING', 'APPINSIGHTS_CONNECTION_STRING')

Info "=== Bootstrap deploy identity: env=$Env ==="
Note "App: $AppDisplayName | RG (Contributor scope): $ResourceGroup"
Note "Federated subject (environment-based): $fedSubject"
Note "GitHub env deploy policy: $(if ($RestrictDeployToBranch) { "only branch '$RestrictDeployToBranch'" } else { 'any branch' })"
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

# --- 1. Entra app registration (idempotent; duplicate-name guard) ---
Info "1. Entra app registration '$AppDisplayName'"
$appIds = @(az ad app list --display-name $AppDisplayName --query "[].appId" -o tsv --only-show-errors 2>$null)
if ($appIds.Count -gt 1) {
  Write-Host "  ERROR: $($appIds.Count) app registrations are named '$AppDisplayName' (appIds: $($appIds -join ', ')). Entra allows duplicate names; delete the extra(s) and re-run." -ForegroundColor Red
  exit 1
}
if ($appIds.Count -eq 1) {
  $appId = $appIds[0]
  Ok "exists (appId $appId)"
} else {
  $appId = Do-Or-Show "az ad app create --display-name $AppDisplayName" {
    az ad app create --display-name $AppDisplayName --query appId -o tsv --only-show-errors
  }
  Assert-LastOk "app registration create"
  if (-not $DryRun) { Ok "created (appId $appId)" }
}
if ($DryRun -and -not $appId) { $appId = '<new-app-id>' }

Stop-If-Past 2
# --- 2. Service principal (sp list, not sp show; retry for AAD replication) ---
Info "2. Service principal"
if ($appId) {
  $spExists = az ad sp list --filter "appId eq '$appId'" --query "[0].id" -o tsv --only-show-errors 2>$null
  if ($spExists) {
    Ok "exists"
  } else {
    Do-Or-Show "az ad sp create --id $appId (with retry for AAD replication)" {
      $created = $false
      for ($i = 1; $i -le 6; $i++) {
        az ad sp create --id $appId --only-show-errors 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $created = $true; break }
        Note "app not replicated yet (attempt $i/6); waiting 5s..."
        Start-Sleep -Seconds 5
      }
      if (-not $created) { Write-Host "  ERROR: service principal create failed after retries -- wait a minute and re-run." -ForegroundColor Red; exit 1 }
    }
    if (-not $DryRun) { Ok "created" }
  }
}

# --- 2b. Tag the SP so it shows under the portal's DEFAULT Enterprise Applications filter ---
# The portal adds the WindowsAzureActiveDirectoryIntegratedApp tag to UI-registered apps; the CLI does
# NOT, so a script-created SP is hidden unless you switch the filter to "All applications". Purely
# cosmetic -- the SP authenticates and authorizes identically with or without the tag.
Info "2b. Tag SP for default Enterprise Applications visibility"
$integratedTag = 'WindowsAzureActiveDirectoryIntegratedApp'
if ($appId -and $appId -ne '<new-app-id>') {
  $spObjId = az ad sp show --id $appId --query id -o tsv --only-show-errors 2>$null
  $curTags = az ad sp show --id $appId --query tags -o tsv --only-show-errors 2>$null
  if ($curTags -match $integratedTag) {
    Ok "already tagged"
  } elseif ($spObjId) {
    Do-Or-Show "az rest PATCH servicePrincipal tags += $integratedTag" {
      $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "sptags-$Env.json"
      Set-Content -Path $tmp -Value ('{"tags":["' + $integratedTag + '"]}') -Encoding ascii
      az rest --method PATCH --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$spObjId" --headers "Content-Type=application/json" --body "@$tmp" --only-show-errors | Out-Null
      $script:tagRc = $LASTEXITCODE
      Remove-Item $tmp -Force
    }
    if (-not $DryRun) { $global:LASTEXITCODE = $script:tagRc; Assert-LastOk "tag SP"; Ok "tagged (visible in default Enterprise Applications view)" }
  }
} elseif ($DryRun) { Note "[dry-run] would: tag the SP $integratedTag for default Enterprise Apps visibility" }

Stop-If-Past 3
# --- 3. Federated credential (ENVIRONMENT-based, NO client secret) + remove stale branch credential ---
Info "3. Federated credential for $fedSubject"
$fedExists = $null
if ($appId -and -not $DryRun) {
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
    $script:fedRc = $LASTEXITCODE
    Remove-Item $tmp -Force
  }
  if (-not $DryRun) { $global:LASTEXITCODE = $script:fedRc; Assert-LastOk "federated credential create"; Ok "created (no client secret)" }
}
# Cleanup: remove any superseded BRANCH-based federated credential (from the earlier approach).
if ($appId -and -not $DryRun) {
  $branchCredIds = @(az ad app federated-credential list --id $appId --query "[?contains(subject, ':ref:refs/heads/')].id" -o tsv --only-show-errors 2>$null)
  foreach ($cid in $branchCredIds) {
    az ad app federated-credential delete --id $appId --federated-credential-id $cid --only-show-errors 2>$null | Out-Null
    Note "removed superseded branch-based federated credential"
  }
} elseif ($DryRun) { Note "[dry-run] would: remove any superseded branch-based federated credential" }

Stop-If-Past 4
# --- 4. Contributor RBAC on the env RG ONLY (D7) ---
Info "4. Contributor on $ResourceGroup (RG scope only, never subscription)"
$rgScope = "/subscriptions/$subId/resourceGroups/$ResourceGroup"
$haveRole = $null
if ($appId -and -not $DryRun) {
  $haveRole = az role assignment list --assignee $appId --scope $rgScope --role Contributor --query "[0].id" -o tsv --only-show-errors 2>$null
}
if ($haveRole) {
  Ok "already assigned"
} else {
  Do-Or-Show "az role assignment create --role Contributor --scope $rgScope" {
    az role assignment create --assignee $appId --role Contributor --scope $rgScope --only-show-errors | Out-Null
  }
  if (-not $DryRun) { Assert-LastOk "role assignment create"; Ok "assigned" }
}

Stop-If-Past 5
# --- 5. GitHub environment + deployment-branch policy (the deploy-trust target + the prod gate) ---
Info "5. GitHub environment '$Env' ($(if ($RestrictDeployToBranch) { "only branch '$RestrictDeployToBranch'" } else { 'any branch' }))"
if ($RestrictDeployToBranch) {
  Do-Or-Show "gh api PUT environments/$Env (custom branch policy) + add branch policy '$RestrictDeployToBranch'" {
    '{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}' | gh api --method PUT "repos/$ghRepo/environments/$Env" --input - --silent 2>$null
    $existing = @(gh api "repos/$ghRepo/environments/$Env/deployment-branch-policies" --jq ".branch_policies[].name" 2>$null)
    if ($existing -notcontains $RestrictDeployToBranch) {
      gh api --method POST "repos/$ghRepo/environments/$Env/deployment-branch-policies" -f "name=$RestrictDeployToBranch" --silent 2>$null
    }
  }
} else {
  Do-Or-Show "gh api PUT environments/$Env (any-branch policy)" {
    gh api --method PUT "repos/$ghRepo/environments/$Env" --silent 2>$null
  }
}
if (-not $DryRun) { Assert-LastOk "gh environment configure"; Ok "environment '$Env' configured" }

Stop-If-Past 6
# --- 6. Environment SECRETS for the OIDC IDENTIFIERS (env-scoped; delete repo-scoped leftovers) ---
# They're really plain identifiers, but stored as secrets on a PUBLIC repo so an accidental log echo
# can't become a recon breadcrumb (GitHub masks secrets, not variables). Piped via stdin.
Info "6. Environment secrets: OIDC identifiers (env-scoped on '$Env')"
$ids = @{ 'AZURE_CLIENT_ID' = $appId; 'AZURE_TENANT_ID' = $tenantId; 'AZURE_SUBSCRIPTION_ID' = $subId }
foreach ($k in $idSecretNames) {
  Do-Or-Show "gh secret set $k --env $Env (identifier; piped)" { $ids[$k] | gh secret set $k --env $Env --repo $ghRepo 2>$null }
  if (-not $DryRun) { Assert-LastOk "gh secret set $k --env $Env"; Ok "$k set (env '$Env')" }
  # delete any superseded REPO-scoped copy (so there's one source of truth)
  if (-not $DryRun) { gh secret delete $k --repo $ghRepo 2>$null | Out-Null }
}

Stop-If-Past 7
# --- 7. Environment SECRETS for the CONNECTION STRINGS (env-scoped; fetched live; delete repo copies) ---
Info "7. Environment secrets: connection strings (env-scoped on '$Env'; genuinely sensitive)"
Note "D37: the SWA deployment token is intentionally NOT set here -- break-glass only, gitignored notes."
$stConn = az storage account show-connection-string -n $storageName -g $ResourceGroup --query connectionString -o tsv --only-show-errors 2>$null
if ($stConn) {
  Do-Or-Show "gh secret set AZURE_STORAGE_CONNECTION_STRING --env $Env (piped)" {
    $stConn | gh secret set AZURE_STORAGE_CONNECTION_STRING --env $Env --repo $ghRepo 2>$null
  }
  if (-not $DryRun) { Assert-LastOk "gh secret set AZURE_STORAGE_CONNECTION_STRING --env $Env"; Ok "AZURE_STORAGE_CONNECTION_STRING set (env '$Env')"; gh secret delete AZURE_STORAGE_CONNECTION_STRING --repo $ghRepo 2>$null | Out-Null }
} else { Note "WARN: could not fetch storage connection string for $storageName (skipped)" }
$aiConn = az resource show -g $ResourceGroup -n $appInsightsName --resource-type "Microsoft.Insights/components" --query "properties.ConnectionString" -o tsv --only-show-errors 2>$null
if ($aiConn) {
  Do-Or-Show "gh secret set APPINSIGHTS_CONNECTION_STRING --env $Env (piped)" {
    $aiConn | gh secret set APPINSIGHTS_CONNECTION_STRING --env $Env --repo $ghRepo 2>$null
  }
  if (-not $DryRun) { Assert-LastOk "gh secret set APPINSIGHTS_CONNECTION_STRING --env $Env"; Ok "APPINSIGHTS_CONNECTION_STRING set (env '$Env')"; gh secret delete APPINSIGHTS_CONNECTION_STRING --repo $ghRepo 2>$null | Out-Null }
} else { Note "WARN: could not fetch App Insights connection string for $appInsightsName (skipped)" }

Stop-If-Past 8
# --- 8. Verify + summary ---
Write-Host ""
Info "=== Verify (expect 5 ENVIRONMENT secrets; NO SWA deploy token, D37; repo-scoped + variables empty) ==="
if ($DryRun) {
  Write-Host "(dry-run: skipping live verification)" -ForegroundColor Yellow
} else {
  Write-Host "-- gh secret list --env $Env (expect the 5) --" -ForegroundColor DarkGray
  gh secret list --env $Env --repo $ghRepo 2>$null
  Write-Host "-- gh secret list --repo (expect EMPTY -- superseded by env-scoped) --" -ForegroundColor DarkGray
  gh secret list --repo $ghRepo 2>$null
  Write-Host "-- gh variable list (expect empty) --" -ForegroundColor DarkGray
  gh variable list --repo $ghRepo 2>$null
  Write-Host ""
  Ok "Bootstrap complete for env=$Env. The 2.2 workflow's deploy job uses 'environment: $Env',"
  Note "which makes GitHub mint an OIDC token matching the environment federated credential, and exposes"
  Note "the env-scoped secrets to that job only. Record the secret list in gitignored infra/<env>-resources.md."
}
