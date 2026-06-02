// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

// Observability module — Log Analytics workspace + workspace-based Application Insights
// + RG-scoped cost-management budget alert. Implements D24 (single AI sink),
// D36 (AI public network access stays enabled), and Sprint 1.1's $5/$12/$15 budget rungs.

@description('Azure region (full name, e.g. eastus2).')
param location string

@description('Common tag set applied to all resources.')
param tags object

@description('Log Analytics workspace name (from naming module).')
param lawName string

@description('Application Insights name (from naming module).')
param appInsightsName string

@description('Budget resource name (from naming module).')
param budgetName string

@description('Budget amount in USD per month. Default $15 per Sprint 1.1.')
param budgetAmountUsd int = 15

@description('Email address for budget alert notifications. Pass at deploy time — never committed.')
param notificationEmail string

@description('Budget start date (ISO 8601, first-of-month, e.g. 2026-06-01). Azure Consumption requires monthly budgets to start in the current month or later. Computed at the top-level template via utcNow() and passed in here.')
param budgetStartDate string

// Log Analytics workspace — backs the workspace-based App Insights
resource law 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: lawName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    workspaceCapping: {
      dailyQuotaGb: -1 // No cap; we control cost via the budget alert
    }
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights (workspace-based, the only modern option since classic was deprecated 2024)
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: law.id
    publicNetworkAccessForIngestion: 'Enabled' // D36
    publicNetworkAccessForQuery: 'Enabled' // D36
  }
}

// Budget alert — RG-scoped per Sprint 1.1 (subscription is shared with other workloads;
// a sub-scoped budget would measure the wrong total). Three Actual-cost rungs:
// $5 (33% — early warning), $12 (80% — warning), $15 (100% — action needed).
resource budget 'Microsoft.Consumption/budgets@2023-11-01' = {
  name: budgetName
  properties: {
    timePeriod: {
      startDate: budgetStartDate
    }
    timeGrain: 'Monthly'
    amount: budgetAmountUsd
    category: 'Cost'
    // Notification keys use Azure's portal-generated naming (actual_GreaterThan_<n>_Percent)
    // so a what-if / redeploy against the live dev budget shows no churn. The three Actual-cost
    // rungs are the $5 (33%) / $12 (80%) / $15 (100%) early-warning/warning/action ladder.
    notifications: {
      actual_GreaterThan_33_Percent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 33
        thresholdType: 'Actual'
        contactEmails: [
          notificationEmail
        ]
        locale: 'en-us'
      }
      actual_GreaterThan_80_Percent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        thresholdType: 'Actual'
        contactEmails: [
          notificationEmail
        ]
        locale: 'en-us'
      }
      actual_GreaterThan_100_Percent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        thresholdType: 'Actual'
        contactEmails: [
          notificationEmail
        ]
        locale: 'en-us'
      }
    }
  }
}

// Outputs consumed by downstream modules
output lawId string = law.id
output lawName string = law.name
output appInsightsId string = appInsights.id
output appInsightsName string = appInsights.name
// AI connection string is non-secret (telemetry-write-only); safe to output for reference
output appInsightsConnectionString string = appInsights.properties.ConnectionString
