@description('Name of the storage account')
param storageAccountName string

@description('Azure region for all resources')
param location string = resourceGroup().location

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  tags: {
    CostCenter: 'CC-0001'
    Owner: 'finops-team@contoso.com'
    Environment: 'prod'
    Application: 'finops-scanner'
    Department: 'Engineering'
    Project: 'FinOps-Scanner'
    ManagedBy: 'Bicep'
  }
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    isHnsEnabled: true
    allowSharedKeyAccess: false
  }
}

resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource scanResultsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobServices
  name: 'finops-scan-results'
  properties: {
    publicAccess: 'None'
  }
}

// NOTE: Storage Blob Data Contributor must be assigned manually to the pipeline SP
// via Azure Portal > Storage Account > Access Control (IAM).
// The pipeline SP (Contributor role) lacks Microsoft.Authorization/roleAssignments/write.

output storageAccountName string = storageAccount.name
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob
output containerName string = scanResultsContainer.name
