// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

// Main orchestrator — composes the full Epic 1 landing zone in a single RG-scoped deployment.
//
// Deploy:
//   az deployment group create \
//     -g rg-<workload>-<app>-<env>-<region> \
//     --template-file infra/bicep/dev/main.bicep \
//     -p env=<dev|prod|validate> \
//     -p region=<use2> \
//     -p workload=<workload> \
//     -p app=<app> \
//     -p notificationEmail=<your-email>
//
// The RG itself is NOT provisioned here — create it first with `az group create`, then
// run this deployment against it. (Subscription-scoped Bicep can do both; we keep this
// at RG scope to match how dev was hand-built and to avoid subscription-scope auth
// requirements during the throwaway validate deployment.)

targetScope = 'resourceGroup'

@description('Environment slug — dev, prod, or validate.')
param env string

@description('Region code — use2 (East US 2).')
param region string = 'use2'

@description('Workload slug.')
param workload string

@description('App slug.')
param app string

@description('Email address for budget alerts. Pass at deploy time — never committed.')
param notificationEmail string

@description('Budget amount in USD per month.')
param budgetAmountUsd int = 15

@description('Container image reference for the transcoder. Defaults to the same public placeholder the live dev Container App runs (Sprint 1.4). Sprint 6.1 swaps in the real transcoder image.')
param containerAppImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Azure region full name (resolved from region code). Override only if region != use2.')
param location string = 'eastus2'

@description('Budget start date, ISO 8601 first-of-month. Defaults to the first of the current UTC month at deploy time so Azure Consumption never rejects a past-month start. Override only if reproducing a specific historical budget identity.')
param budgetStartDate string = utcNow('yyyy-MM-01')

@description('Cost-center tag value, used for cost attribution at subscription level. Defaults to `personal` (the SLAYList project shares a personal-use Azure sub with other personal workloads).')
param costCenter string = 'personal'

// Common tag set per `infra/naming-convention.md`
var tags = {
  workload: workload
  app: app
  env: env
  region: region
  'cost-center': costCenter
  'managed-by': 'bicep'
}

// --- Naming module: produces all resource names ---
module names 'naming.bicep' = {
  name: 'names'
  params: {
    env: env
    region: region
    workload: workload
    app: app
  }
}

// --- Observability: LAW + AI + budget ---
module observability 'observability.bicep' = {
  name: 'observability'
  params: {
    location: location
    tags: tags
    lawName: names.outputs.lawName
    appInsightsName: names.outputs.appInsightsName
    budgetName: names.outputs.budgetName
    budgetAmountUsd: budgetAmountUsd
    notificationEmail: notificationEmail
    budgetStartDate: budgetStartDate
  }
}

// --- SWA ---
module swa 'swa.bicep' = {
  name: 'swa'
  params: {
    location: location
    tags: tags
    swaName: names.outputs.swaName
  }
}

// --- Storage: account + containers + table + queues + 3 diagnostic settings ---
module storage 'storage.bicep' = {
  name: 'storage'
  params: {
    location: location
    tags: tags
    storageName: names.outputs.storageName
    lawId: observability.outputs.lawId
    diagBlobName: names.outputs.diagBlobName
    diagTableName: names.outputs.diagTableName
    diagQueueName: names.outputs.diagQueueName
  }
}

// --- Container App: CAE + CA + MI + RBAC ---
module containerApp 'containerapp.bicep' = {
  name: 'containerApp'
  params: {
    location: location
    tags: tags
    caeName: names.outputs.caeName
    caName: names.outputs.caName
    lawName: observability.outputs.lawName
    containerAppImage: containerAppImage
    storageName: storage.outputs.storageName
  }
}

// --- Event Grid system topic + MI + diag setting ---
module eventGrid 'eventgrid.bicep' = {
  name: 'eventGrid'
  params: {
    location: location
    tags: tags
    egstName: names.outputs.egstName
    storageId: storage.outputs.storageId
    lawId: observability.outputs.lawId
    diagEgstName: names.outputs.diagEgstName
  }
}

// --- Non-sensitive outputs for operator reference and post-deploy comparison ---
output storageName string = storage.outputs.storageName
output swaName string = swa.outputs.swaName
output swaDefaultHostname string = swa.outputs.swaDefaultHostname
output containerAppPrincipalId string = containerApp.outputs.containerAppPrincipalId
output egstPrincipalId string = eventGrid.outputs.egstPrincipalId
output appInsightsName string = observability.outputs.appInsightsName
output lawName string = observability.outputs.lawName
