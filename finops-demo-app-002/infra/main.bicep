// -----------------------------------------------------------------------
// FinOps Demo App 002 — Oversized Resources Violation
// -----------------------------------------------------------------------
// This template INTENTIONALLY deploys oversized Azure resources for a
// development workload. A P3v3 App Service Plan (~$700/month) and
// Premium_LRS Storage (~$100/month) are used where B1 and Standard_LRS
// would suffice. Resources are tagged as Environment: Development to
// highlight the cost-tier mismatch.
// -----------------------------------------------------------------------

@description('Azure region for all resources')
param location string = 'eastus'

@description('App Service Plan name')
param appServicePlanName string = 'asp-finops-demo-002'

@description('Web App name')
param webAppName string = 'app-finops-demo-002-${uniqueString(resourceGroup().id)}'

@description('Storage Account name')
param storageAccountName string = 'stfinops002${uniqueString(resourceGroup().id)}'

var commonTags = {
  Environment: 'Development'
  Application: 'finops-demo-002'
  CostCenter: 'CC-1234'
  Owner: 'team@contoso.com'
  Department: 'Engineering'
  Project: 'FinOps-Scanner'
  ManagedBy: 'Bicep'
}

// INTENTIONAL-FINOPS-ISSUE: P3v3 plan is massively oversized for a development static site (~$700/month)
// A B1 plan ($13/month) is the maximum allowed SKU for dev environments per governance policy
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'P3v3'
    tier: 'PremiumV3'
    capacity: 1
  }
  tags: commonTags
}

// INTENTIONAL-FINOPS-ISSUE: Premium_LRS storage for a static site dev workload (~$100/month)
// Standard_LRS ($2/month) is the maximum allowed tier for dev environments per governance policy
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Premium_LRS'
  }
  tags: commonTags
}

resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: webAppName
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      minTlsVersion: '1.2'
    }
  }
  tags: commonTags
}
