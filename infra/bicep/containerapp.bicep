// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

// Container App module — Container App Environment (LAW-linked per D24) + Container App
// running the transcoder placeholder, with a system-assigned managed identity and two
// RBAC role assignments scoped to the storage account (D25 runtime auth), matching the
// live dev MI as provisioned in Sprint 1.4:
//   - Storage Blob Data Contributor  (read raw, write finished)
//   - Storage Table Data Contributor (flip the Songs record to `ready` on completion)
//
// Sprint 6.1 replaces the placeholder image with the real transcoder; Epic 7 adds the
// Event Grid → queue subscription AND the queue-data-plane RBAC the consumer needs
// (Storage Queue Data Message Processor) — deliberately not captured here because the live
// dev MI does not carry it yet. RBAC is captured so the MI is ready for blob/table work.

@description('Azure region (full name).')
param location string

@description('Common tag set.')
param tags object

@description('Container App Environment name (from naming module).')
param caeName string

@description('Container App name (from naming module).')
param caName string

@description('Container image reference. Defaults to the same public placeholder the live dev Container App runs (Sprint 1.4). Sprint 6.1 swaps in the real transcoder image via this parameter.')
param containerAppImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Storage account name — for RBAC scope (same RG as this deployment).')
param storageName string

@description('Log Analytics workspace name — for CAE log-ingestion key lookup (same RG).')
param lawName string

// --- Sizing (parameterized so prod can run a tier or two above dev without forking the
//     template — D39 "same templates, parameter substitution"). Defaults are the live dev
//     values, so dev stays byte-identical and the drift-check stays CLEAN. ---
@description('Container vCPU. Consumption-profile locks the pair to 1 vCPU : 2 GiB, so memory is DERIVED below from this single value (you cannot pick an invalid pair). dev default 0.25; prod typically a tier or two up (e.g. 0.5 or 1.0). ffmpeg is CPU-bound, so this is the lever that speeds transcodes.')
@allowed([
  '0.25'
  '0.5'
  '0.75'
  '1.0'
  '1.25'
  '1.5'
  '1.75'
  '2.0'
])
param containerCpu string = '0.25'

@description('Scale ceiling (max concurrent replicas). minReplicas stays 0 for scale-to-zero per D4 (idle ~= free), so this is the only scale knob. dev default 1; prod may want 2-3 for concurrent transcodes.')
@minValue(1)
@maxValue(30)
param maxReplicas int = 1

// Memory is derived from vCPU to guarantee a valid Consumption-profile pair (Gi = 2 x vCPU).
// Keyed by the same @allowed set above; an unmapped value fails fast at deploy.
var cpuToMemory = {
  '0.25': '0.5Gi'
  '0.5': '1Gi'
  '0.75': '1.5Gi'
  '1.0': '2Gi'
  '1.25': '2.5Gi'
  '1.5': '3Gi'
  '1.75': '3.5Gi'
  '2.0': '4Gi'
}
var containerMemory = cpuToMemory[containerCpu]

// Same-RG existing-resource lookups (CAE needs LAW's customerId + sharedKey explicitly;
// RBAC needs storage as the scope target).
resource lawRef 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: lawName
}

resource storageRef 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageName
}

// --- Container App Environment ---
resource cae 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: caeName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: lawRef.properties.customerId
        sharedKey: lawRef.listKeys().primarySharedKey
      }
    }
    zoneRedundant: false // dev: single-zone fine; prod can override
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

// --- Container App (transcoder placeholder until Sprint 6.1) ---
resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: caName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: cae.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: null // no inbound HTTP; queue-driven only
    }
    template: {
      containers: [
        {
          name: 'transcoder'
          image: containerAppImage
          resources: {
            // CPU/memory from the parameterized sizing above (dev default 0.25 vCPU / 0.5 GiB;
            // prod can pass a higher tier). Memory is derived to the valid Consumption pair.
            cpu: json(containerCpu)
            memory: containerMemory
          }
          // No env vars on the placeholder — matches the live dev Container App (Sprint 1.4).
          // Runtime auth is MI + RBAC per D25 (no storage connection string here). Sprint 6.1
          // adds the real transcoder's env wiring (App Insights connection string, queue name,
          // etc.) when there's an actual workload that needs it.
        }
      ]
      scale: {
        minReplicas: 0 // scale-to-zero per D4 (idle ~= free) — kept for dev AND prod
        maxReplicas: maxReplicas // parameterized; dev default 1, prod may raise
      }
    }
  }
}

// --- RBAC: Storage Blob Data Contributor on the storage account ---
// Built-in role ID: ba92f5b4-2d11-453d-a403-e96b0029c9fe
var blobDataContributorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
)

resource blobDataContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageRef
  name: guid(storageRef.id, containerApp.id, blobDataContributorRoleId)
  properties: {
    roleDefinitionId: blobDataContributorRoleId
    principalId: containerApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// --- RBAC: Storage Table Data Contributor on the storage account ---
// Built-in role ID: 0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3
// Matches the live dev Container App MI (Sprint 1.4): the transcoder updates the Songs
// table record to `ready` on completion, so it needs table data-plane write access.
//
// NOTE (Epic 7 forward question): the transcoder will ALSO need to dequeue/delete messages
// from the work queue (and write to the poison queue), which requires Storage Queue Data
// Message Processor. That role is intentionally NOT assigned here because the live dev MI
// does not have it today — the queue trigger + its RBAC are wired in Epic 7, not captured at
// Sprint 1.6. Add the queue role to this module when Epic 7 provisions the queue consumer.
var tableDataContributorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
)

resource tableDataContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageRef
  name: guid(storageRef.id, containerApp.id, tableDataContributorRoleId)
  properties: {
    roleDefinitionId: tableDataContributorRoleId
    principalId: containerApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output caeId string = cae.id
output containerAppId string = containerApp.id
output containerAppPrincipalId string = containerApp.identity.principalId
