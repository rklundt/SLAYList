// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

// Name-generator module — single source of truth for the CAF naming pattern
// per `infra/naming-convention.md`. Every other module consumes these outputs
// so `dev` → `prod` is purely a parameter substitution.
//
// Pattern: <type-prefix>-<workload>-<app>-<env>-<region>
// Special case: storage account name has stricter rules (no hyphens, lowercase,
// 3-24 chars, globally unique) — handled below with length-aware fallback.

@description('Environment slug — typically dev, prod, or validate (for IaC throwaway).')
param env string

@description('Region code — typically use2 (East US 2). Used in resource names.')
param region string

@description('Workload slug.')
param workload string

@description('App slug.')
param app string

// CAF-pattern names (hyphenated, lowercase)
output rgName string = 'rg-${workload}-${app}-${env}-${region}'
output lawName string = 'log-${workload}-${app}-${env}-${region}'
output appInsightsName string = 'appi-${workload}-${app}-${env}-${region}'
output swaName string = 'swa-${workload}-${app}-${env}-${region}'
output caeName string = 'cae-${workload}-${app}-${env}-${region}'
output caName string = 'ca-${workload}-${app}-${env}-${region}'
output egstName string = 'egst-${workload}-${app}-${env}-${region}'

// Budget — no region per convention (cost is RG-scoped)
output budgetName string = 'budget-${workload}-${app}-${env}'

// Diagnostic-setting names (suffix only; full setting names are scoped to a parent resource)
output diagBlobName string = 'diag-blob-to-law-${env}'
output diagTableName string = 'diag-table-to-law-${env}'
output diagQueueName string = 'diag-queue-to-law-${env}'
output diagEgstName string = 'diag-egst-to-law-${env}'

// Storage account: special-case naming (no hyphens, lowercase only, 3-24 chars, globally unique)
// Try fullName first; if >24 chars (e.g. for `env=validate` → 27 chars), drop workload;
// if still >24, drop region. Matches `infra/naming-convention.md` "storage-account exception".
var storageFullName = toLower('st${workload}${app}${env}${region}')
var storageNoWorkload = toLower('st${app}${env}${region}')
var storageNoWorkloadOrRegion = toLower('st${app}${env}')

output storageName string = length(storageFullName) <= 24
  ? storageFullName
  : (length(storageNoWorkload) <= 24 ? storageNoWorkload : storageNoWorkloadOrRegion)
