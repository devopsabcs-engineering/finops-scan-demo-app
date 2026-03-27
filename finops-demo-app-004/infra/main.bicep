// -----------------------------------------------------------------------
// FinOps Demo App 004 — No Auto-Shutdown Violation
// -----------------------------------------------------------------------
// This template INTENTIONALLY deploys a D4s_v5 VM (~$140/month) tagged
// as Environment: Development WITHOUT an auto-shutdown schedule.
// Per governance policy, all non-production VMs must have auto-shutdown
// enabled via Microsoft.DevTestLab/schedules.
// -----------------------------------------------------------------------

@description('Azure region for all resources')
param location string = 'eastus'

@description('VM administrator username')
param adminUsername string = 'azureuser'

@secure()
@description('VM administrator password')
param adminPassword string

@description('Virtual machine name')
param vmName string = 'vm-finops-demo-004'

var commonTags = {
  Environment: 'Development'
  Application: 'finops-demo-004'
  CostCenter: 'CC-1234'
  Owner: 'team@contoso.com'
  Department: 'Engineering'
  Project: 'FinOps-Scanner'
  ManagedBy: 'Bicep'
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'vnet-finops-demo-004'
  location: location
  tags: commonTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.1.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.1.1.0/24'
        }
      }
    ]
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-finops-demo-004'
  location: location
  tags: commonTags
  properties: {
    securityRules: [
      {
        name: 'AllowSSH'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'pip-finops-demo-004'
  location: location
  tags: commonTags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: 'nic-finops-demo-004'
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
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

// INTENTIONAL-FINOPS-ISSUE: D4s_v5 VM running 24/7 without auto-shutdown schedule (~$140/month)
// Per governance policy, all non-production VMs must have Microsoft.DevTestLab/schedules auto-shutdown enabled
resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  tags: commonTags
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D4s_v5'
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

// INTENTIONAL-FINOPS-ISSUE: No Microsoft.DevTestLab/schedules auto-shutdown resource defined
// The following resource SHOULD exist but is deliberately omitted:
//
// resource autoShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = {
//   name: 'shutdown-computevm-${vmName}'
//   location: location
//   properties: {
//     status: 'Enabled'
//     taskType: 'ComputeVmShutdownTask'
//     dailyRecurrence: { time: '1900' }
//     timeZoneId: 'Eastern Standard Time'
//     targetResourceId: vm.id
//   }
// }
