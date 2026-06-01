// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

// Static Web App module — Free tier per D26, with deliberately empty repositoryUrl/branch
// per the D22 safeguard from Sprint 1.2 Step 3 (keeps SWA from auto-creating a deploy workflow
// against develop without the D22 gate config — that gate lands at Sprint 2.2's first real deploy).

@description('Azure region (full name, e.g. eastus2).')
param location string

@description('Common tag set.')
param tags object

@description('Static Web App resource name.')
param swaName string

resource swa 'Microsoft.Web/staticSites@2024-04-01' = {
  name: swaName
  location: location
  tags: tags
  sku: {
    name: 'Free'
    tier: 'Free'
  }
  properties: {
    // D22 safeguard from Sprint 1.2: NO repositoryUrl / branch / buildProperties.
    // Leaving these empty matches the portal "Deployment source = Other" path that
    // prevents SWA from generating an auto-deploy workflow against develop before
    // the D22 gate config ships at Sprint 2.2.
    repositoryUrl: ''
    branch: ''
    buildProperties: {}
    allowConfigFileUpdates: true
    stagingEnvironmentPolicy: 'Enabled'
    provider: 'None' // Explicit: no source-control integration
  }
}

output swaResourceId string = swa.id
output swaName string = swa.name
output swaDefaultHostname string = swa.properties.defaultHostname
// Sensitive: SWA deployment token is NOT output here per D17 + D37 (it's a break-glass
// fallback only; retrieve post-deploy via `az staticwebapp secrets list -n <name> -g <rg>`
// when the operator needs it for an ad-hoc emergency deploy).
