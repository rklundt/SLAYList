// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

// Container App module — Container App Environment (LAW-linked per D24) + Container App
// running the transcoder placeholder, with a system-assigned managed identity and two
// RBAC role assignments scoped to the storage account (D25 runtime auth):
//   - Storage Blob Data Contributor (read raw, write finished, write _test-artifacts)
//   - Storage Queue Data Message Processor (dequeue work, enqueue poison on failure)
//
// Sprint 6.1 will replace the placeholder image with the real transcoder; Sprint 7.1 will
// add the Event Grid → queue subscription. RBAC is captured here so the MI is ready to use.

@description('Azure region (full name).')
param location string

@description('Common tag set.')
param tags object

@description('Container App Environment name (from naming module).')
param caeName string

@description('Container App name (from naming module).')
param caName string

@description('Container image reference. Defaults to a public placeholder until Sprint 6.1 ships the real transcoder image.')
param containerAppImage string = 'mcr.microsoft.com/k8se/quickstart:latest'

@description('Storage account name — for RBAC scope (same RG as this deployment).')
param storageName string

@description('Log Analytics workspace name — for CAE log-ingestion key lookup (same RG).')
param lawName string

@description('Application Insights connection string for telemetry plumbing (non-secret per AI semantics).')
param appInsightsConnectionString string

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
            // Minimal CPU/memory — Sprint 1.4 settled at 0.25 vCPU / 0.5 GiB for the placeholder.
            // Sprint 6.1 may revise once real ffmpeg load is measured.
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          env: [
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: appInsightsConnectionString
            }
            // No storage connection string here per D25: runtime auth is MI + RBAC,
            // not shared-key. The MI is wired via `identity` above; consuming code
            // uses DefaultAzureCredential / ManagedIdentityCredential.
          ]
        }
      ]
      scale: {
        minReplicas: 0 // scale-to-zero per Sprint 1.4
        maxReplicas: 3 // Sprint 1.4 chose 3 as a tight cap
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

// --- RBAC: Storage Queue Data Message Processor on the storage account ---
// Built-in role ID: 8a0f0c08-91a1-4084-bc3d-661d67233fed
var queueMessageProcessorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '8a0f0c08-91a1-4084-bc3d-661d67233fed'
)

resource queueMessageProcessorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageRef
  name: guid(storageRef.id, containerApp.id, queueMessageProcessorRoleId)
  properties: {
    roleDefinitionId: queueMessageProcessorRoleId
    principalId: containerApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output caeId string = cae.id
output containerAppId string = containerApp.id
output containerAppPrincipalId string = containerApp.identity.principalId
