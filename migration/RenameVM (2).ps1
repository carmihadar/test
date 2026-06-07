param(
        [Parameter(Mandatory,HelpMessage="Old name of the VM",Position=0)]
        [string]$OldVMName,
        [Parameter(Mandatory,HelpMessage="New name for the VM",Position=1)]
        [string]$NewVMName
)

$moduleNames = @("Microsoft.Graph.DeviceManagement","Microsoft.Graph.Beta.DeviceManagement.Actions")
$moduleNames | %{if(-not (Get-Module -Name $_)){Write-Host "Importing $_" -ForegroundColor Gray ; Import-Module -Name $_ -Force}}


if(-not $(Get-MgContext)){
    Write-Host "Attempting to connect to Graph"
    if($PSScriptRoot){ # If running as script and not as a standalone command
        cd $PSScriptRoot
        $cred = Import-Clixml -Path ".\EncryptedCreds.xml"
        $tenant = Get-AzTenant -ErrorAction Ignore
        if($tenant){
            $tenantId = $tenant.Id           
        }
        else{
            $tenantId = Read-Host "Enter tenant ID manually"
        }

        try{
            Connect-MgGraph -ClientSecretCredential $cred -TenantId $tenantId -NoWelcome -ErrorAction Stop
        }catch{
            Write-Error "Connection to MSGraph failed: $_"
            exit
        }
    }
}

Write-Host "Connected to MSGraph" -ForegroundColor Cyan

$Device = Get-MgDeviceManagementManagedDevice -Filter  "deviceName eq '$OldVMName'"
    
if(-not $Device){
    Write-Debug "Failed to find Managed Device $OldVMName"
    return 1
}

Write-Debug -Message "$OldVMName ID: $($Device.Id)"

try{
    Set-MgBetaDeviceManagementManagedDeviceName -ManagedDeviceId $Device.Id -DeviceName "$NewVMName" -ErrorAction Stop
}catch{
    Write-Debug "Error: Device rename request failed"
    return 2
}

Write-Debug "Sent Rename request to $OldVMName"
    
try{
    Restart-MgDeviceManagementManagedDeviceNow -ManagedDeviceId $Device.Id -ErrorAction Stop
}catch{
    Write-Debug "Warning: Device rename request failed"
    return 3
}    
     
Write-Debug "Sent restart request to $NewVMName"
return 0