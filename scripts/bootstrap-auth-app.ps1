# Copyright (c) 2026 Ray Klundt
# SPDX-License-Identifier: AGPL-3.0-or-later

<#
.SYNOPSIS
  Bootstraps the user-auth Entra app registration + the three app roles for one environment
  (D2/D11/D20/D22/D41). Sprint 3.1.

.DESCRIPTION
  Idempotent, parameterized, operator-run "seed" script. It creates the Entra APP REGISTRATION that
  the SPA uses for client-side MSAL sign-in (Epic 3), and defines the three app roles
  (listener / uploader / admin) that ride in the user's token. Like the deploy identity (D41), this is
  a Microsoft Graph object, NOT an ARM resource -- so it lives in a committed bootstrap script, never
  in the Bicep (CLAUDE.md: "Graph/Entra identity objects = bootstrap script").

  BIG PICTURE (plain English, if you're new to this):
    - Epic 2 shipped a gate that trusts ANY Microsoft account (the pre-configured SWA provider). That's
      too broad for real content -- anyone with a Microsoft account could sign in.
    - Epic 3 replaces that with OUR OWN app registration: a custom identity in Entra that (a) only lets
      in users an admin has ASSIGNED a role to (the family), and (b) puts that role in the login token
      so the API can enforce it. This script creates that registration and defines the roles.
    - Jargon decoder: "app registration" = the identity definition of our app in Entra; "app role" = a
      named permission (listener/uploader/admin) the registration declares; "service principal" =
      the registration's account in this tenant, which is what users actually get ASSIGNED to.
    - SEPARATE app per environment (D7, same as the deploy identity): app is `slaylist-auth-<env>`, so
      dev test assignments can never grant prod access. Run again with -Env prod at Epic 9.

  THE THREE ROLES (D20 -- library-scoped, NOT a platform/global admin): the `value` strings are the
  contract with the code -- they MUST equal shared/src/types.ts `ROLES = ['listener','uploader','admin']`
  (a shared test asserts that). The role IDs are fixed GUIDs (hardcoded for idempotency: re-runs keep
  the same IDs so role assignments from Sprint 3.2 never break). They are role-definition identifiers,
  not environment GUIDs, so they are safe to commit (D17).

  STEPS (what -> why). Each is check-then-create / declarative-set, so the whole script is idempotent:
    1. App registration               -> the identity the SWA logs users in against (created per-env).
    2. App roles                       -> declare listener/uploader/admin on the registration (the
                                          token's `roles` claim; values must match the shared ROLES).
    3. Service principal               -> the registration's account in this tenant; role ASSIGNMENT
                                          (Sprint 3.2) and the SWA auth flow both need it.
    4. Require user assignment         -> set appRoleAssignmentRequired=true so ONLY users an admin has
                                          assigned a role can sign in. This is the mechanism that closes
                                          Epic 2's any-Microsoft-account gap. No users are assigned yet
                                          (Sprint 3.2 does that) -- so until then nobody can sign in,
                                          which is fine: the gate isn't swapped to this provider until 3.3.
    5. Redirect URIs (Sprint 3.3)      -> SPA redirect URIs (the SWA origin + http://localhost:5193) for
                                          MSAL, the active path. The Web reply URL (/.auth/login/aad/
                                          callback) is also kept but DORMANT -- pre-wires a future switch
                                          to SWA built-in auth on Standard.
    6. Expose API scope (Sprint 3.3)   -> App ID URI api://<appId> + the access_as_user scope + v2 access
                                          tokens, so MSAL can request a token the API validates.
    7. Client secret (dormant)         -> NOT used by MSAL (public client, PKCE). Kept available for the
                                          future built-in-auth switch; created only if none exists (printed
                                          ONCE; stored as a GitHub secret + gitignored notes), 24-month
                                          expiry; -RotateSecret forces a new one. Not wired into SWA today.
    8. Verify                          -> print roles / assignment flag / SPA URIs / scope / secret count + appId.

  WHAT THIS SCRIPT DELIBERATELY DOES NOT DO:
    - Does NOT store the client secret anywhere but the console -- the operator copies it to the GitHub
      `dev`-env secret AAD_CLIENT_SECRET + gitignored notes (step 6 prints it once; D17).
    - No role ASSIGNMENT to people (Sprint 3.2, manual/guided).
    - No change to staticwebapp.config.json (that gate swap is committed code, Sprint 3.3 Phase A).

  D17: no secrets/GUIDs hardcoded -- the appId/tenantId are READ from az and printed for the operator to
  capture into gitignored infra/<env>-resources.md; nothing identifying is written to the repo.

.PARAMETER DryRun
  Print every create/set command instead of running it. Read-only checks still run. Run this first.

.PARAMETER RunUpToStep
  Run only steps 1..N then stop (cautious, incremental). 0 (default) runs everything. Composes with
  -DryRun. Steps: 1 app, 2 roles, 3 SP, 4 require-assignment, 5 redirect-URIs, 6 expose-API-scope,
  7 client-secret (dormant), 8 verify.

.EXAMPLE
  ./scripts/bootstrap-auth-app.ps1 -DryRun
  Preview the dev auth-app bootstrap (no changes).

.EXAMPLE
  ./scripts/bootstrap-auth-app.ps1 -RunUpToStep 2
  Cautiously create the app registration + roles, then stop.

.EXAMPLE
  ./scripts/bootstrap-auth-app.ps1 -Env prod
  Bootstrap the prod auth app (Epic 9) as a SEPARATE app registration.

.NOTES
  Requires `az login` to the tenant that will own the app registration. Creating an app registration +
  service principal requires directory permission (Application Administrator / Cloud Application
  Administrator, or a personal tenant where you are the owner). Cross-platform: Windows PowerShell 5.1
  and pwsh 7.
#>

param(
  [string]$Env = 'dev',
  [string]$App = 'slaylist',
  [string]$Workload = 'music',
  [string]$Region = 'use2',
  # Entra app display name. Defaults to slaylist-auth-<env> -- a SEPARATE app per environment (D7).
  [string]$AppDisplayName = '',
  # SWA reply URL for the login callback. Empty = derive from the env's SWA default hostname (via az).
  [string]$RedirectUri = '',
  # Force a NEW client secret even if one already exists (deliberate rotation). Default: create only
  # when none exists -- secrets can't be re-read, so we don't churn them. See the 24-month note, step 6.
  [switch]$RotateSecret,
  # Run only steps 1..N and stop. 0 = everything. Steps: 1 app, 2 roles, 3 SP, 4 require-assignment,
  # 5 redirect-URIs, 6 expose-API-scope, 7 client-secret(dormant), 8 verify. Composes with -DryRun.
  [ValidateRange(0, 8)][int]$RunUpToStep = 0,
  [switch]$DryRun
)

# Continue, not Stop: az writes to stderr for ordinary conditions (e.g. "no SP found yet"); under Stop
# that would halt the script. We check results explicitly (if/$LASTEXITCODE) instead.
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

# --- Resolve names ---
if (-not $AppDisplayName) { $AppDisplayName = "$App-auth-$Env" }
$resourceGroup = "rg-$Workload-$App-$Env-$Region"
$swaName = "swa-$Workload-$App-$Env-$Region"

# The three app roles (D20). `value` MUST match shared/src/types.ts ROLES. The `id` GUIDs are fixed
# (hardcoded) so re-runs are idempotent and Sprint 3.2 role assignments never break -- they are
# role-definition identifiers, not environment GUIDs, so committing them is fine (D17).
# NOTE (D20): these roles are app-GLOBAL -- they carry no libraryId. Library-scoped authorization
# ("can this person act within THIS library") is enforced in the API authz layer (Epic 3.3+), not in
# the Entra role. Correct for the one library today; multi-library later adds a separate
# library-membership concept (D20), not more app roles.
$ROLE_ID_LISTENER = '7e3a1c54-9b2d-4f86-a1b0-3c5d7e9f1a2b'
$ROLE_ID_UPLOADER = '8f4b2d65-0c3e-4a97-b2c1-4d6e8f0a2b3c'
$ROLE_ID_ADMIN    = '9a5c3e76-1d4f-4ba8-83d2-5e7f9a1b3c4d'
$appRolesJson = @"
[
  { "allowedMemberTypes": ["User"], "description": "Can browse and play songs in the library.", "displayName": "Listener", "id": "$ROLE_ID_LISTENER", "isEnabled": true, "value": "listener" },
  { "allowedMemberTypes": ["User"], "description": "Can upload songs to the library (plus listener rights).", "displayName": "Uploader", "id": "$ROLE_ID_UPLOADER", "isEnabled": true, "value": "uploader" },
  { "allowedMemberTypes": ["User"], "description": "Library administrator within this single library (D20: library-scoped, not a platform/global admin).", "displayName": "Admin", "id": "$ROLE_ID_ADMIN", "isEnabled": true, "value": "admin" }
]
"@

Info "=== Bootstrap user-auth app: env=$Env ==="
Note "App registration: $AppDisplayName  (separate app per environment, D7)"
Note "Roles: listener, uploader, admin  (D20 library-scoped; values must match shared ROLES)"
if ($DryRun) { Write-Host "(DRY RUN -- no changes will be made)" -ForegroundColor Yellow }
Write-Host ""

# --- Preflight: az authenticated ---
Info "Preflight: checking az session"
$acct = az account show --only-show-errors 2>$null | ConvertFrom-Json
if (-not $acct) { Write-Error "Not logged in to az. Run: az login (to the tenant that will own this app)."; exit 2 }
$tenantId = $acct.tenantId
Ok "az: $($acct.user.name) / tenant $tenantId"
Write-Host ""

# --- 1. App registration (idempotent; duplicate-name guard) ---
# PLAIN ENGLISH: this creates the app's identity in our directory. --sign-in-audience AzureADMyOrg makes
# it SINGLE-TENANT -- only accounts in OUR Entra directory can even be considered (the rest of the
# world's Microsoft accounts are shut out right here). Step 4 then narrows "our directory" down to just
# the assigned family members. (This single-tenant choice is the first of the two "family only" layers.)
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
  $appId = Do-Or-Show "az ad app create --display-name $AppDisplayName --sign-in-audience AzureADMyOrg" {
    az ad app create --display-name $AppDisplayName --sign-in-audience AzureADMyOrg --query appId -o tsv --only-show-errors
  }
  Assert-LastOk "app registration create"
  if (-not $DryRun) { Ok "created (appId $appId)" }
}
if ($DryRun -and -not $appId) { $appId = '<new-app-id>' }

Stop-If-Past 2
# --- 2. App roles (declarative set; idempotent -- re-asserts the same 3 roles with the same IDs) ---
# We only ever assert the SAME three roles (same values + IDs), so a plain re-set is safe. CAUTION for
# future editors: Microsoft Graph REJECTS renaming or removing an app role in a single update while it
# is still enabled -- you must first PATCH that role to isEnabled=false, then change/remove it in a
# second update. Adding a brand-new role (e.g. a 4th) is fine in one shot.
Info "2. App roles: listener, uploader, admin (D20)"
if ($appId -and $appId -ne '<new-app-id>') {
  Do-Or-Show "az ad app update --id $appId --app-roles <listener,uploader,admin>" {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "approles-$Env.json"
    Set-Content -Path $tmp -Value $appRolesJson -Encoding ascii
    az ad app update --id $appId --app-roles "@$tmp" --only-show-errors | Out-Null
    $script:rolesRc = $LASTEXITCODE
    Remove-Item $tmp -Force
  }
  if (-not $DryRun) { $global:LASTEXITCODE = $script:rolesRc; Assert-LastOk "app-roles update"; Ok "roles set (listener, uploader, admin)" }
} elseif ($DryRun) { Note "[dry-run] would: set app roles listener/uploader/admin" }

Stop-If-Past 3
# --- 3. Service principal (sp list, not sp show; retry for AAD replication) ---
Info "3. Service principal (needed for role assignment in Sprint 3.2 + the SWA auth flow)"
if ($appId -and $appId -ne '<new-app-id>') {
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
} elseif ($DryRun) { Note "[dry-run] would: create the service principal" }

# --- 3b. Tag the SP so it shows under the portal's DEFAULT Enterprise Applications filter ---
# The portal adds the WindowsAzureActiveDirectoryIntegratedApp tag to UI-registered apps; the CLI does
# NOT, so a script-created SP is hidden unless you switch the filter to "All applications". Purely
# cosmetic -- the SP authenticates and authorizes identically with or without the tag.
Info "3b. Tag SP for default Enterprise Applications visibility"
$integratedTag = 'WindowsAzureActiveDirectoryIntegratedApp'
if ($appId -and $appId -ne '<new-app-id>') {
  $spObjId = az ad sp show --id $appId --query id -o tsv --only-show-errors 2>$null
  $curTags = az ad sp show --id $appId --query tags -o tsv --only-show-errors 2>$null
  if ($curTags -match $integratedTag) {
    Ok "already tagged"
  } elseif ($spObjId) {
    Do-Or-Show "az rest PATCH servicePrincipal tags += $integratedTag" {
      $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "sptags-auth-$Env.json"
      Set-Content -Path $tmp -Value ('{"tags":["' + $integratedTag + '"]}') -Encoding ascii
      az rest --method PATCH --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$spObjId" --headers "Content-Type=application/json" --body "@$tmp" --only-show-errors | Out-Null
      $script:tagRc = $LASTEXITCODE
      Remove-Item $tmp -Force
    }
    if (-not $DryRun) { $global:LASTEXITCODE = $script:tagRc; Assert-LastOk "tag SP"; Ok "tagged (visible in default Enterprise Applications view)" }
  }
} elseif ($DryRun) { Note "[dry-run] would: tag the SP $integratedTag for default Enterprise Apps visibility" }

Stop-If-Past 4
# --- 4. Require user assignment (the gatekeeper switch -- closes Epic 2's any-Microsoft-account gap) ---
# PLAIN ENGLISH (for non-Azure folks): this flips ONE switch on the app's sign-in behaviour.
#   - OFF (the default): anyone in our Entra directory could sign in -- no invite needed.
#   - ON  (what we set): ONLY people an admin has explicitly assigned to the app (Sprint 3.2) can sign
#     in; everyone else is turned away at the login screen.
# Two layers stack to get us to "family only":
#   (a) single-tenant audience from step 1 already shuts out the whole outside world (only OUR directory),
#   (b) THIS switch then trims it down to just the specific family members we hand-pick and assign.
# It also means signing in REQUIRES having a role -- which is exactly how the role ends up in the user's
# token for the API to read.
# Expect: right after this, NOBODY can sign in yet (nobody's assigned). Sprint 3.2 assigns the first
# person; the live site is unaffected until Sprint 3.3 points it at this app.
Info "4. Require user assignment (appRoleAssignmentRequired=true)"
Note "Only users an admin has assigned a role (Sprint 3.2) can sign in. None assigned yet -- expected."
if ($appId -and $appId -ne '<new-app-id>') {
  $req = az ad sp show --id $appId --query "appRoleAssignmentRequired" -o tsv --only-show-errors 2>$null
  if ($req -eq 'true') {
    Ok "already required"
  } else {
    Do-Or-Show "az ad sp update --id $appId --set appRoleAssignmentRequired=true" {
      az ad sp update --id $appId --set appRoleAssignmentRequired=true --only-show-errors | Out-Null
    }
    if (-not $DryRun) { Assert-LastOk "set appRoleAssignmentRequired"; Ok "user assignment now required" }
  }
} elseif ($DryRun) { Note "[dry-run] would: set appRoleAssignmentRequired=true" }

Stop-If-Past 5
# --- 5. Redirect URIs: SPA (active -- MSAL) + Web reply URL (dormant -- future built-in auth) ---
# MSAL (client-side) returns to the SPA origin, so we register SPA redirect URIs: the deployed SWA
# origin + http://localhost:5193 (the `pnpm dev` Vite server). We ALSO keep the Web reply URL
# (/.auth/login/aad/callback) registered but DORMANT -- it costs nothing and pre-wires a future
# switch to SWA built-in auth on the Standard SKU (see DECISIONS: MSAL-now / built-in-later).
Info "5. Redirect URIs (SPA for MSAL; Web reply URL kept dormant)"
$appObjId = az ad app show --id $appId --query id -o tsv --only-show-errors 2>$null
if (-not $RedirectUri) {
  $swaHost = az staticwebapp show -n $swaName -g $resourceGroup --query defaultHostname -o tsv --only-show-errors 2>$null
  if ($swaHost) { $RedirectUri = "https://$swaHost/.auth/login/aad/callback" }
}
if (-not $swaHost -and $RedirectUri -match '^https://([^/]+)/') { $swaHost = $Matches[1] }
$spaUris = @()
if ($swaHost) { $spaUris += "https://$swaHost" }
$spaUris += 'http://localhost:5193'
if ($appId -and $appId -ne '<new-app-id>' -and $appObjId) {
  # 5a. SPA redirect URIs (the active path for MSAL). Set via Graph PATCH -- az ad app update has no
  # --spa-redirect-uris flag. JSON built by hand so a single-element array never collapses to a scalar.
  $existingSpa = @(az ad app show --id $appId --query "spa.redirectUris" -o tsv --only-show-errors 2>$null)
  $missingSpa = @($spaUris | Where-Object { $existingSpa -notcontains $_ })
  if ($missingSpa.Count -eq 0) {
    Ok "SPA redirect URIs already set ($($spaUris -join ', '))"
  } else {
    Note "SPA redirect URIs: $($spaUris -join ', ')"
    Do-Or-Show "az rest PATCH spa.redirectUris" {
      $spaArr = ($spaUris | ForEach-Object { '"' + $_ + '"' }) -join ','
      $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "spa-auth-$Env.json"
      Set-Content -Path $tmp -Value ('{"spa":{"redirectUris":[' + $spaArr + ']}}') -Encoding ascii
      az rest --method PATCH --uri "https://graph.microsoft.com/v1.0/applications/$appObjId" --headers "Content-Type=application/json" --body "@$tmp" --only-show-errors | Out-Null
      $script:spaRc = $LASTEXITCODE
      Remove-Item $tmp -Force
    }
    if (-not $DryRun) { $global:LASTEXITCODE = $script:spaRc; Assert-LastOk "set SPA redirect URIs"; Ok "SPA redirect URIs set" }
  }
  # 5b. Web reply URL (dormant -- for a future SWA built-in-auth switch).
  if ($RedirectUri) {
    $existingWeb = @(az ad app show --id $appId --query "web.redirectUris" -o tsv --only-show-errors 2>$null)
    if ($existingWeb -contains $RedirectUri) {
      Ok "Web reply URL already set (dormant): $RedirectUri"
    } else {
      Do-Or-Show "az ad app update --web-redirect-uris $RedirectUri (dormant)" {
        az ad app update --id $appId --web-redirect-uris $RedirectUri --only-show-errors | Out-Null
      }
      if (-not $DryRun) { Assert-LastOk "set Web redirect URI"; Ok "Web reply URL set (dormant)" }
    }
  } else {
    Note "WARN: could not derive the SWA host (is $swaName created?). SPA localhost set; pass -RedirectUri for the Web reply URL."
  }
} elseif ($DryRun) { Note "[dry-run] would: set SPA redirect URIs $($spaUris -join ', ') + the dormant Web reply URL" }

Stop-If-Past 6
# --- 6. Expose an API scope (MSAL access tokens are audienced for THIS app's API) ---
# The SPA requests an access token for api://<appId>/access_as_user; the API validates it. Set the App
# ID URI + the scope + requestedAccessTokenVersion=2 (so tokens carry the v2 issuer the API checks).
# Declarative set with a fixed scope id -> idempotent (same discipline as the app roles). az ad app
# update has no scope flag, so this is a Graph PATCH.
Info "6. Expose API scope 'access_as_user' + App ID URI (api://$appId), v2 access tokens"
$SCOPE_ID_ACCESS = 'a1b2c3d4-e5f6-4789-a0b1-c2d3e4f5a6b7'
if ($appId -and $appId -ne '<new-app-id>' -and $appObjId) {
  $existingScopes = @(az ad app show --id $appId --query "api.oauth2PermissionScopes[].value" -o tsv --only-show-errors 2>$null)
  $existingIdUris = @(az ad app show --id $appId --query "identifierUris" -o tsv --only-show-errors 2>$null)
  if (($existingScopes -contains 'access_as_user') -and ($existingIdUris -contains "api://$appId")) {
    Ok "API scope + App ID URI already set"
  } else {
    Do-Or-Show "az rest PATCH identifierUris + api.oauth2PermissionScopes(access_as_user) + requestedAccessTokenVersion=2" {
      $apiJson = @"
{
  "identifierUris": ["api://$appId"],
  "api": {
    "requestedAccessTokenVersion": 2,
    "oauth2PermissionScopes": [
      {
        "id": "$SCOPE_ID_ACCESS",
        "adminConsentDescription": "Allow the SLAYList SPA to call the SLAYList API as the signed-in user.",
        "adminConsentDisplayName": "Access the SLAYList API as the signed-in user",
        "userConsentDescription": "Allow SLAYList to call its API on your behalf.",
        "userConsentDisplayName": "Access the SLAYList API",
        "value": "access_as_user",
        "type": "User",
        "isEnabled": true
      }
    ]
  }
}
"@
      $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "apiscope-auth-$Env.json"
      Set-Content -Path $tmp -Value $apiJson -Encoding ascii
      az rest --method PATCH --uri "https://graph.microsoft.com/v1.0/applications/$appObjId" --headers "Content-Type=application/json" --body "@$tmp" --only-show-errors | Out-Null
      $script:scopeRc = $LASTEXITCODE
      Remove-Item $tmp -Force
    }
    if (-not $DryRun) { $global:LASTEXITCODE = $script:scopeRc; Assert-LastOk "expose API scope"; Ok "API scope 'access_as_user' + App ID URI set" }
  }
} elseif ($DryRun) { Note "[dry-run] would: set App ID URI api://<appId> + expose the access_as_user scope (v2 tokens)" }

Stop-If-Past 7
# --- 7. Client secret -- DORMANT (kept for a future SWA built-in-auth switch; MSAL uses none) ---
# MSAL (public client, PKCE) needs NO client secret. We keep one available so the future switch to SWA
# built-in auth on Standard is pre-wired. Create only if none exists (secrets can't be re-read); pass
# -RotateSecret to force a new one. Store the printed value as the GitHub dev-env secret
# AAD_CLIENT_SECRET + gitignored notes -- NEVER in the repo (D17). It is NOT wired into SWA app settings
# today (the deploy workflow omits it while MSAL is in use).
Info "7. Client secret (dormant -- for a future built-in-auth switch; 24-month expiry)"
if ($appId -and $appId -ne '<new-app-id>') {
  # Count via [].keyId (paren-free): a "length(@)" JMESPath gets mangled when PowerShell hands the bare
  # parentheses to az.cmd (cmd.exe treats () as special, az exits 255), so count returned lines instead.
  $secretCount = @(az ad app credential list --id $appId --query "[].keyId" -o tsv --only-show-errors 2>$null).Count
  if ($secretCount -gt 0 -and -not $RotateSecret) {
    Ok "a client secret already exists ($secretCount). Not creating another -- pass -RotateSecret to rotate."
    Note "If you don't have the value, you must rotate (secrets cannot be re-read)."
  } else {
    Do-Or-Show "az ad app credential reset --id $appId --years 2 (prints the value ONCE)" {
      $secret = az ad app credential reset --id $appId --years 2 --display-name "swa-auth-$Env" --query password -o tsv --only-show-errors
      $script:secretRc = $LASTEXITCODE
      if ($secret) {
        Write-Host ""
        Write-Host "  >>> CLIENT SECRET (shown ONCE -- store it NOW) <<<" -ForegroundColor Yellow
        Write-Host "  $secret" -ForegroundColor Yellow
        Write-Host "  Store as GitHub dev-env secret AAD_CLIENT_SECRET + gitignored notes. NEVER commit it." -ForegroundColor Yellow
        Write-Host ""
      }
    }
    if (-not $DryRun) { $global:LASTEXITCODE = $script:secretRc; Assert-LastOk "client secret reset"; Ok "client secret created (expires in 24 months)" }
  }
} elseif ($DryRun) { Note "[dry-run] would: create a 24-month client secret and print it once" }

Stop-If-Past 8
# --- 8. Verify + summary ---
Write-Host ""
Info "=== Verify ==="
if ($DryRun) {
  Write-Host "(dry-run: skipping live verification)" -ForegroundColor Yellow
} else {
  Write-Host "-- app roles (expect exactly: admin, listener, uploader) --" -ForegroundColor DarkGray
  az ad app show --id $appId --query "appRoles[].value" -o tsv --only-show-errors 2>$null
  Write-Host "-- user assignment required (expect: true) --" -ForegroundColor DarkGray
  az ad sp show --id $appId --query "appRoleAssignmentRequired" -o tsv --only-show-errors 2>$null
  Write-Host "-- SPA redirect URIs (expect the SWA origin + http://localhost:5193) --" -ForegroundColor DarkGray
  az ad app show --id $appId --query "spa.redirectUris" -o tsv --only-show-errors 2>$null
  Write-Host "-- App ID URI + exposed scope (expect api://$appId + access_as_user) --" -ForegroundColor DarkGray
  az ad app show --id $appId --query "identifierUris" -o tsv --only-show-errors 2>$null
  az ad app show --id $appId --query "api.oauth2PermissionScopes[].value" -o tsv --only-show-errors 2>$null
  Write-Host "-- client secret count (dormant; values are write-once) --" -ForegroundColor DarkGray
  @(az ad app credential list --id $appId --query "[].keyId" -o tsv --only-show-errors 2>$null).Count
  Write-Host ""
  Ok "Auth app bootstrap complete for env=$Env."
  Note "appId    : $appId  -> GitHub dev-env secret AAD_CLIENT_ID + gitignored infra/$Env-resources.md"
  Note "tenantId : $tenantId  -> GitHub dev-env secret AZURE_TENANT_ID (API audience/issuer + SPA authority)"
  Note "The deploy workflow bakes VITE_AAD_CLIENT_ID/VITE_AAD_TENANT_ID into the SPA and wires"
  Note "AAD_CLIENT_ID/AAD_TENANT_ID into SWA app settings for the API's token validation. Then a push"
  Note "deploys. Sign in as an assigned account to verify login + role (Sprint 3.3/3.4)."
}
