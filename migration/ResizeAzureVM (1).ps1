param(
    [Parameter(Mandatory,HelpMessage = "Subscription of the VMs to resize")]
    [string]$subscriptionId,
    [Parameter(Mandatory,HelpMessage = 'Resource group of the vm to resize')]
    [string]$resourceGroupName,
    [Parameter(Mandatory,HelpMessage = 'The tag name (key) that the VM will be filtered by.')]
    [string]$TagName,
    [Parameter(HelpMessage = 'The value for TagName. VMs that have the tag specified in TagName with this value in the resource group specified in resourceGroupName will be resize. If this value is not specified, all the VMs in the resource group specified in resourceGroupName with the tag specified in Tag will be resized.')]
    [string]$Tag

)


#region variables

### Define required variables ###
#################################

$subscriptionId = "31076e3c-fc5e-4f0b-be52-0eb744e89036" # Replace with your actual destination subscription ID
$resourceGroupName= "AVD-9900-NM-DEV-RG" # Replace with your sessionhosts destination resource group name
$TagName = "subunit" # Replace with the name (key) of the tag used to identify VMs.
$Tag = "TTTest1"

#endregion


Set-AzContext -Subscription $subscriptionId -ErrorAction SilentlyContinue | Out-Null
if($Tag){
    $vmList = Get-AzVM -ResourceGroupName $resourceGroupName | ?{$_.Tags[$TagName] -eq $Tag}
}
else{
    $vmList = Get-AzVM -ResourceGroupName $resourceGroupName | ?{$_.Tags.ContainsKey($TagName)}
}

$resizeJobs = @()
foreach($vm in $vmList){

    $resizeJobs += Start-Job -Name $vm.Name -ScriptBlock{
        $sizeMap = @{
            "Standard_B2s" = "Standard_D4as_v5"
            "Standard_B2s_v2" = "Standard_D4as_v5"
            "Standard_B2ms" = "Standard_D4as_v5"
            "Standard_B4ms" = "Standard_D8as_v5"
            "Standard_B8ms" = "Standard_D16as_v5"
            "Standard_B12ms" = "Standard_D16as_v5"
            "Standard_D2as_v5" = "Standard_D4as_v5"
            "Standard_D2ls_v5" = "Standard_D4as_v5"
            "Standard_D2ds_v5" = "Standard_D4as_v5"
            "Standard_D2s_v3" = "Standard_D4as_v5"
            "Standard_D4as_v5" = "Standard_D4as_v5"
            "Standard_D4ads_v5" = "Standard_D4as_v5"
            "Standard_D4ds_v5" = "Standard_D4as_v5"
            "Standard_D4s_v3" = "Standard_D4as_v5"
            "Standard_D4s_v5" = "Standard_D4as_v5"
            "Standard_D16s_v5" = "Standard_D16as_v5"
            "Standard_D16ls_v5" = "Standard_D16as_v5"
            "Standard_D16as_v5" = "Standard_D16as_v5"
        }
        
        $vmId = $args[0]
        $vm = Get-AzVM -ResourceId $vmId
        Stop-AzVM -Id $vmId -ErrorAction Stop

        $vmSize = $vm.HardwareProfile.VmSize
        $vmSize = $sizeMap[$vmSize]
        $vm.HardwareProfile.VmSize = $vmSize
        Update-AzVM -VM $vm -Id $vmId -ErrorAction Stop
        Start-AzVM -Id $vmId -ErrorAction Stop
    } -ArgumentList $vm.Id
}

Write-Host "Waiting for resize job to finish..."

for(;;){
    Write-Host '.' -NoNewline
    $resizeJobs | Wait-Job -Timeout 10 | Out-Null
    if($resizeJobs.State -notcontains "Running"){
        Write-Host ""
        break;
    }
}
Write-Host "===Done===" -ForegroundColor Green
$resizeJobs
