// -----------------------------------------------------------------------
// FinOps Demo App 005 — Redundant / Expensive Resources Violation
// -----------------------------------------------------------------------
// This template INTENTIONALLY deploys redundant and unnecessarily
// expensive Azure resources:
//   - 2 duplicate S3 App Service Plans in expensive non-approved regions
//     (westeurope, southeastasia) instead of consolidating on 1 plan
//   - GRS storage where LRS would suffice for a dev workload
//   - Web apps on each plan, duplicating workload across regions
// -----------------------------------------------------------------------

@description('Primary resource location (used for storage only)')
param location string = 'eastus'

@description('Storage Account name')
param storageAccountName string = 'stfinops005${uniqueString(resourceGroup().id)}'

var commonTags = {
  Environment: 'Development'
  Application: 'finops-demo-005'
  CostCenter: 'CC-1234'
  Owner: 'team@contoso.com'
  Department: 'Engineering'
  Project: 'FinOps-Scanner'
  ManagedBy: 'Bicep'
}

// INTENTIONAL-FINOPS-ISSUE: S3 App Service Plan in westeurope — expensive non-approved region (~$200/month)
// Approved regions are: eastus, eastus2, centralus. This plan duplicates the workload unnecessarily.
resource appServicePlanEurope 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'asp-finops-demo-005-eu'
  location: 'westeurope'
  sku: {
    name: 'S3'
    tier: 'Standard'
    capacity: 1
  }
  tags: commonTags
}

// INTENTIONAL-FINOPS-ISSUE: S3 App Service Plan in southeastasia — expensive non-approved region (~$200/month)
// This is a duplicate of the Europe plan, doubling costs for the same workload
resource appServicePlanAsia 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'asp-finops-demo-005-sea'
  location: 'southeastasia'
  sku: {
    name: 'S3'
    tier: 'Standard'
    capacity: 1
  }
  tags: commonTags
}

resource webAppEurope 'Microsoft.Web/sites@2023-12-01' = {
  name: 'app-finops-demo-005-eu-${uniqueString(resourceGroup().id)}'
  location: 'westeurope'
  properties: {
    serverFarmId: appServicePlanEurope.id
    httpsOnly: true
    siteConfig: {
      minTlsVersion: '1.2'
    }
  }
  tags: commonTags
}

resource webAppAsia 'Microsoft.Web/sites@2023-12-01' = {
  name: 'app-finops-demo-005-sea-${uniqueString(resourceGroup().id)}'
  location: 'southeastasia'
  properties: {
    serverFarmId: appServicePlanAsia.id
    httpsOnly: true
    siteConfig: {
      minTlsVersion: '1.2'
    }
  }
  tags: commonTags
}

// INTENTIONAL-FINOPS-ISSUE: GRS storage where LRS would suffice for a dev static site (~$50/month vs ~$2/month)
// Development workloads do not require geo-redundant storage
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_GRS'
  }
  tags: commonTags
}

output webAppUrlEurope string = 'https://${webAppEurope.properties.defaultHostName}'
output webAppUrlAsia string = 'https://${webAppAsia.properties.defaultHostName}'
