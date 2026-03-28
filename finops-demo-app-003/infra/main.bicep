// -----------------------------------------------------------------------
// FinOps Demo App 003 — Orphaned Resources Violation
// -----------------------------------------------------------------------
// This template INTENTIONALLY deploys Azure resources that are not
// attached to any compute workload. These represent orphaned resources
// that accumulate cost without providing value:
//   - Public IP (Standard, Static) — not attached to any NIC or LB
//   - NIC — not attached to any VM
//   - Managed Disk (Premium, 128GB) — not attached to any VM
//   - NSG — not associated with any subnet or NIC
// -----------------------------------------------------------------------

@description('Azure region for all resources')
param location string = 'canadacentral'

var commonTags = {
  Environment: 'Development'
  Application: 'finops-demo-003'
  CostCenter: 'CC-1234'
  Owner: 'team@contoso.com'
  Department: 'Engineering'
  Project: 'FinOps-Scanner'
  ManagedBy: 'Bicep'
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'vnet-finops-demo-003'
  location: location
  tags: commonTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.0.1.0/24'
        }
      }
    ]
  }
}

// INTENTIONAL-FINOPS-ISSUE: Public IP not attached to any resource — wasted cost (~$3.65/month)
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'pip-orphaned-003'
  location: location
  tags: commonTags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// INTENTIONAL-FINOPS-ISSUE: Network interface not attached to any VM — orphaned resource
resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: 'nic-orphaned-003'
  location: location
  tags: commonTags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

// INTENTIONAL-FINOPS-ISSUE: Managed disk not attached to any VM — wasted cost (~$19.71/month for 128GB Premium)
resource disk 'Microsoft.Compute/disks@2023-10-02' = {
  name: 'disk-orphaned-003'
  location: location
  tags: commonTags
  sku: {
    name: 'Premium_LRS'
  }
  properties: {
    diskSizeGB: 128
    creationData: {
      createOption: 'Empty'
    }
  }
}

// INTENTIONAL-FINOPS-ISSUE: NSG not associated with any subnet or NIC — orphaned resource
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-orphaned-003'
  location: location
  tags: commonTags
  properties: {
    securityRules: [
      {
        name: 'AllowHTTP'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

output resourceGroupName string = resourceGroup().name
