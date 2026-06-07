param virtualMachines_temp_name string = 'pls-wrk-0'
param galleries_bob_externalid string = '/subscriptions/2778f2e9-1113-4cf0-80a2-06909b26a1b7/resourceGroups/Gilad-Tst-Idf-Cld/providers/Microsoft.Compute/galleries/bob'
param networkInterfaces_test_nic_name string = 'test-nic'
param virtualNetworks_externalid string = '/subscriptions/8e8fecdc-e0f1-48b2-94ab-cc8c728dc080/resourceGroups/idf-test/providers/Microsoft.Network/virtualNetworks/ahhhhh'
param location string = 'israelcentral'
param size string = 'Standard_D2as_v4'
@secure()
param temp string = 'eyJhbGciOiJSUzI1NiIsImtpZCI6Ijk0RDQxQUY3MjUyMDFDQzg2MDcwRDQwODI1MkQzMzk2OUEyOEQ0RTciLCJ0eXAiOiJKV1QifQ.eyJSZWdpc3RyYXRpb25JZCI6IjM3NTcwZmE4LTJlNzYtNDU5MC1iYjhhLTQ3NjkzMDQ4YWEyYSIsIkJyb2tlclVyaSI6Imh0dHBzOi8vcmRicm9rZXItZy11cy1yMS53dmQubWljcm9zb2Z0LmNvbS8iLCJEaWFnbm9zdGljc1VyaSI6Imh0dHBzOi8vcmRkaWFnbm9zdGljcy1nLXVzLXIxLnd2ZC5taWNyb3NvZnQuY29tLyIsIkVuZHBvaW50UG9vbElkIjoiZmVjOGExM2ItZjY4OS00YjI3LWE0ZGMtYjA4NzlhZWYzNmJjIiwiR2xvYmFsQnJva2VyVXJpIjoiaHR0cHM6Ly9yZGJyb2tlci53dmQubWljcm9zb2Z0LmNvbS8iLCJHZW9ncmFwaHkiOiJVUyIsIkdsb2JhbEJyb2tlclJlc291cmNlSWRVcmkiOiJodHRwczovL2ZlYzhhMTNiLWY2ODktNGIyNy1hNGRjLWIwODc5YWVmMzZiYy5yZGJyb2tlci53dmQubWljcm9zb2Z0LmNvbS8iLCJCcm9rZXJSZXNvdXJjZUlkVXJpIjoiaHR0cHM6Ly9mZWM4YTEzYi1mNjg5LTRiMjctYTRkYy1iMDg3OWFlZjM2YmMucmRicm9rZXItZy11cy1yMS53dmQubWljcm9zb2Z0LmNvbS8iLCJEaWFnbm9zdGljc1Jlc291cmNlSWRVcmkiOiJodHRwczovL2ZlYzhhMTNiLWY2ODktNGIyNy1hNGRjLWIwODc5YWVmMzZiYy5yZGRpYWdub3N0aWNzLWctdXMtcjEud3ZkLm1pY3Jvc29mdC5jb20vIiwiQUFEVGVuYW50SWQiOiJhMTMwNTVjMS0yZDg2LTRmODktOGE5NS0yYTIyODYyNmIzZDAiLCJuYmYiOjE3NjYxNDY3NjEsImV4cCI6MTc2NjE4MTYwMCwiaXNzIjoiUkRJbmZyYVRva2VuTWFuYWdlciIsImF1ZCI6IlJEbWkifQ.JgJBxdss42pseadE9xXIvVjFTX24tDZ6JA6kSwExUylBECza6KkuqvTJNaBixuhLnRYuIoAv2wI2akHQ-cYCTj1OPvFLZgH-O8BNvElsEOt-xEAogA_QEQp7ZpoyFb3oTpuryl0RX4tQjdh82UYGEBQyYVEwMp0-O5zUoJeWord0jtRaq4fNOo91kuM7tMdkr-6_3hXA9tcm8gh60atUmw6X4-qZQq-1mvTbvKdPznWagxfcfTC9xnnwv2SL7-PmePCxJVHZBHICO_YE27TtiPMLtkwd3zJIZHvz8z58_j2RWJYksXtsKoYLXmcM0Z3wZq89JlRQQNkPVbRjMusJ3g'

resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' existing = {
  name: 'ahhhhh'
}
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2025-03-01' existing = {
  name: '/default'
}

resource networkInterfaces_test_nic_name_resource 'Microsoft.Network/networkInterfaces@2024-07-01' = {
  name: networkInterfaces_test_nic_name
  location: location
  tags: {
    'cm-resource-parent': '/subscriptions/2778f2e9-1113-4cf0-80a2-06909b26a1b7/resourceGroups/Gilad-Tst-Idf-Cld/providers/Microsoft.DesktopVirtualization/test1-avd'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        id: '${split(virtualNetworks_externalid,'virtualNetworks')[0]}networkInterfaces/${networkInterfaces_test_nic_name}/ipConfigurations/ipconfig'
        type: 'Microsoft.Network/networkInterfaces/ipConfigurations'
        properties: {
          privateIPAddress: '10.0.0.5'
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets','ahhhhh','default')
          }
          primary: true
          privateIPAddressVersion: 'IPv4'
        }
      }
    ]
    dnsSettings: {
      dnsServers: []
    }
    enableAcceleratedNetworking: false
    enableIPForwarding: false
    disableTcpStateTracking: false
    nicType: 'Standard'
    auxiliaryMode: 'None'
    auxiliarySku: 'None'
  }
}

resource virtualMachines_temp_name_resource 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: virtualMachines_temp_name
  location: location
  properties: {
    hardwareProfile: {
      vmSize: size
    }
    additionalCapabilities: {
      hibernationEnabled: false
    }
    storageProfile: {
      imageReference: {
        id: '${galleries_bob_externalid}/images/mike'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
        deleteOption: 'Detach'
        diskSizeGB: 128
      }
      dataDisks: []
      diskControllerType: 'SCSI'
    }
    securityProfile: {
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
      securityType: 'TrustedLaunch'
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterfaces_test_nic_name_resource.id
          properties: {
            deleteOption: 'Detach'
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
    licenseType: 'Windows_Server'
    priority: 'Spot'
    evictionPolicy: 'Deallocate'
    billingProfile: {
      maxPrice: json('-1')
    }
  }
}
resource virtualMachines_temp_name_Microsoft_PowerShell_DSC 'Microsoft.Compute/virtualMachines/extensions@2024-11-01' = {
  parent: virtualMachines_temp_name_resource
  name: 'Microsoft.PowerShell.DSC'
  location: 'westus2'
  properties: {
    autoUpgradeMinorVersion: true
    publisher: 'Microsoft.Powershell'
    type: 'DSC'
    typeHandlerVersion: '2.73'
    settings: {
      modulesUrl: 'https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_1.0.03266.1110.zip'
      configurationFunction: 'Configuration.ps1\\AddSessionHost'
      properties: {
        hostPoolName: 'test1-avd'
        registrationInfoTokenCredential: {
          UserName: 'PLACEHOLDER_DO_NOT_USE'
          Password: 'PrivateSettingsRef:MyPassword'
        }
        aadJoin: true
        UseAgentDownloadEndpoint: true
        aadJoinPreview: false
        mdmId: '0000000a-0000-0000-c000-000000000000'
        sessionHostConfigurationLastUpdateTime: ''
      }
    }
    protectedSettings: {
      Items: {
        MyPassword: temp
      }
    }
  }
}

