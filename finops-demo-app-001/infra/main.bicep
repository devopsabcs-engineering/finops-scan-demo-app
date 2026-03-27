// -----------------------------------------------------------------------
// FinOps Demo App 001 — Missing Tags Violation
// -----------------------------------------------------------------------
// This template INTENTIONALLY deploys Azure resources with ZERO tags.
// The FinOps scanner should flag every resource for missing required tags:
//   CostCenter, Owner, Environment, Application, Department, Project, ManagedBy
// -----------------------------------------------------------------------

@description('Azure region for all resources')
param location string = 'eastus'

@description('App Service Plan name')
param appServicePlanName string = 'asp-finops-demo-001'

@description('Web App name')
param webAppName string = 'app-finops-demo-001-${uniqueString(resourceGroup().id)}'

@description('Storage Account name')
param storageAccountName string = 'stfinops001${uniqueString(resourceGroup().id)}'

// INTENTIONAL-FINOPS-ISSUE: Missing all 7 required tags (CostCenter, Owner, Environment, Application, Department, Project, ManagedBy)
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  // tags: {} — deliberately omitted to trigger FinOps scanner findings
}

// INTENTIONAL-FINOPS-ISSUE: Missing all 7 required tags (CostCenter, Owner, Environment, Application, Department, Project, ManagedBy)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'B1'
    tier: 'Basic'
    capacity: 1
  }
  // tags: {} — deliberately omitted to trigger FinOps scanner findings
}

// INTENTIONAL-FINOPS-ISSUE: Missing all 7 required tags (CostCenter, Owner, Environment, Application, Department, Project, ManagedBy)
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
  // tags: {} — deliberately omitted to trigger FinOps scanner findings
}
