// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

// Storage module — single account holding blobs (raw-uploads + finished + _test-artifacts),
// the Songs table, and the work + poison queues. Plus three diagnostic settings (blob/table/queue)
// streaming into the LAW per D24.
//
// Decisions referenced:
//   D6  — hand-rolled DLQ: explicit work-queue + poison-queue pair
//   D17 — public-repo hygiene (no real names in this file)
//   D24 — three storage-service diag settings as separate feeder legs
//   D28 — raw-uploads is the canonical archive; no deletion-class lifecycle rule
//   D33 — soft-delete + versioning on blobs (kid-friendly safety net)
//   D38 — publicNetworkAccess stays Enabled; auth is the real boundary

@description('Azure region (full name, e.g. eastus2).')
param location string

@description('Common tag set.')
param tags object

@description('Storage account name (from naming module — already length-validated to ≤24).')
param storageName string

@description('Log Analytics workspace resource ID, for diagnostic-setting routing.')
param lawId string

@description('Diagnostic setting names (from naming module).')
param diagBlobName string
param diagTableName string
param diagQueueName string

// --- Storage account ---
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS' // D-cost: LRS is enough for dev; prod can override at Sprint 9.1
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowSharedKeyAccess: true // D25: SWA managed-functions API uses connection-string auth
    publicNetworkAccess: 'Enabled' // D38: auth is the real boundary; no PE in dev
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// --- Blob service: enable soft-delete + versioning per D33 ---
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {
    // 30-day retention matches the live dev account (Sprint 1.3). This is a data-safety
    // floor — never lower it; a smaller window shrinks the kids'-songs recovery period.
    deleteRetentionPolicy: {
      enabled: true
      days: 30
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 30
    }
    isVersioningEnabled: true
    // changeFeed deliberately not set — dev never enabled it; leaving it unmanaged keeps
    // the what-if diff against dev clean.
  }
}

// Three containers per Sprint 1.3 + D33:
//   raw-uploads   — D28 canonical archive (kids' original creations)
//   finished      — transcoded derivatives, regeneratable
//   table-backups — D33 nightly Table Storage JSON exports (same-account, separate container)
var containerNames = [
  'raw-uploads'
  'finished'
  'table-backups'
]

resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [for c in containerNames: {
  parent: blobService
  name: c
  properties: {
    publicAccess: 'None'
  }
}]

// --- Table service: Songs table ---
resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {}
}

resource songsTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: 'Songs'
  properties: {}
}

// --- Queue service: work + poison pair (D6 hand-rolled DLQ) ---
resource queueService 'Microsoft.Storage/storageAccounts/queueServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {}
}

resource transcodeQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-05-01' = {
  parent: queueService
  name: 'transcode-jobs'
  properties: {}
}

resource transcodePoisonQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-05-01' = {
  parent: queueService
  name: 'transcode-jobs-poison'
  properties: {}
}

// --- Diagnostic settings: three feeder legs into LAW per D24 ---
// Scope is the *service* sub-resource, not the storage account; that's the only way
// to get StorageRead/StorageWrite/StorageDelete logs per service.
resource diagBlob 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: blobService
  name: diagBlobName
  properties: {
    workspaceId: lawId
    logs: [
      {
        category: 'StorageRead'
        enabled: true
      }
      {
        category: 'StorageWrite'
        enabled: true
      }
      {
        category: 'StorageDelete'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'Transaction'
        enabled: true
      }
    ]
  }
}

resource diagTable 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: tableService
  name: diagTableName
  properties: {
    workspaceId: lawId
    logs: [
      {
        category: 'StorageRead'
        enabled: true
      }
      {
        category: 'StorageWrite'
        enabled: true
      }
      {
        category: 'StorageDelete'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'Transaction'
        enabled: true
      }
    ]
  }
}

resource diagQueue 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: queueService
  name: diagQueueName
  properties: {
    workspaceId: lawId
    logs: [
      {
        category: 'StorageRead'
        enabled: true
      }
      {
        category: 'StorageWrite'
        enabled: true
      }
      {
        category: 'StorageDelete'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'Transaction'
        enabled: true
      }
    ]
  }
}

// Outputs consumed by Event Grid + Container App modules
output storageId string = storage.id
output storageName string = storage.name
output blobEndpoint string = storage.properties.primaryEndpoints.blob
output queueEndpoint string = storage.properties.primaryEndpoints.queue
output tableEndpoint string = storage.properties.primaryEndpoints.table
// Sensitive: account key NOT output. Retrieve post-deploy via:
//   az storage account keys list -n <name> -g <rg>
// (per D17/D37 hygiene — keep secrets out of deploy outputs).
