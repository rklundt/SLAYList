// Copyright (c) 2026 Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later

// Main orchestrator — composes the full Epic 1 landing zone in a single RG-scoped deployment.
//
// Deploy:
//   az deployment group create \
//     -g rg-<workload>-<app>-<env>-<region> \
//     --template-file infra/bicep/main.bicep \
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

@description('Region code — use2 (East US 2). Must be a key in the regionToLocation map below; the physical Azure location is derived from it so the name and the deployed region can never diverge.')
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

@description('Container App vCPU tier. Memory is derived to the valid Consumption-profile pair in containerapp.bicep. dev default 0.25; prod passes a higher tier (e.g. 0.5 / 1.0) for faster transcodes.')
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

@description('Container App max replica count (scale ceiling). minReplicas stays 0 (scale-to-zero, D4). dev default 1; prod may raise for concurrent transcodes.')
@minValue(1)
@maxValue(30)
param maxReplicas int = 1

// Physical Azure location is DERIVED from the region code, never passed independently —
// this makes it impossible to deploy resources named `...-usw2` into East US 2 by forgetting
// to also change a separate location param. Adding a new region is a deliberate code change:
// add its key here (and the deploy fails fast with a clear error if an unmapped region is passed).
var regionToLocation = {
  use2: 'eastus2'
}
var location = regionToLocation[region]

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
    containerCpu: containerCpu
    maxReplicas: maxReplicas
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
