// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

// Event Grid module — system topic on the storage account with a system-assigned
// managed identity (for future SAS-less subscription delivery) + diagnostic setting
// streaming into LAW per D24.
//
// Per Sprint 1.5: the subscription itself + the MI's RBAC role on the work queue
// are deliberately DEFERRED to Sprint 7.1, when there is a real consumer wired up.
// This module captures only what already exists in dev today.

@description('Azure region.')
param location string

@description('Common tag set.')
param tags object

@description('Event Grid system topic name (from naming module).')
param egstName string

@description('Storage account resource ID — the source for BlobCreated events.')
param storageId string

@description('Log Analytics workspace resource ID — diagnostic sink.')
param lawId string

@description('Diagnostic setting name (from naming module).')
param diagEgstName string

resource egst 'Microsoft.EventGrid/systemTopics@2024-06-01-preview' = {
  name: egstName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    source: storageId
    topicType: 'Microsoft.Storage.StorageAccounts'
  }
}

// Diagnostic setting — fourth feeder leg into LAW per D24
resource diagEgst 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: egst
  name: diagEgstName
  properties: {
    workspaceId: lawId
    // System topics (sourced from Azure resources directly) support only DeliveryFailures —
    // PublishFailures + DataPlaneRequests are custom-topic-only categories. Verified against
    // dev's actual diag setting via `az monitor diagnostic-settings categories list`.
    logs: [
      {
        category: 'DeliveryFailures'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// Outputs
output egstId string = egst.id
output egstName string = egst.name
output egstPrincipalId string = egst.identity.principalId
