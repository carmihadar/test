<#param(
    [Parameter(Mandatory,HelpMessage = "Your actual source subscription ID")]
    [string]$Source_subscription_Id,
    [Parameter(Mandatory,HelpMessage = "Your actual destination subscription ID")]
    [string]$Destination_subscription_Id,
    [Parameter(Mandatory,HelpMessage = 'Session hosts source resource group name',ParameterSetName='SplitRG')]
    [string]$SourcevmResourceGroupName,
    [Parameter(Mandatory,HelpMessage = 'Host pools source resource group name',ParameterSetName='SplitRG')]
    [string]$SourceHostpoolResourceGroupName,
    [Parameter(Mandatory,HelpMessage = 'Session hosts destination resource group name',ParameterSetName='SplitRG')]
    [string]$DestinationvmResourceGroupName,
    [Parameter(Mandatory,HelpMessage='Compute gallery name')]
    [string]$galleryName,
    [Parameter(HelpMessage='Region of all new resources. Default is israelcentral')]
    [string]$location = 'israelcentral',
    [Parameter(Mandatory,HelpMessage = 'Host pools destination resource group name',ParameterSetName='SplitRG')]
    [string]$DestHPresourceGroupName,
    [Parameter(Mandatory,HelpMessage = 'Destination host pools name')]
    [string]$DesthostPoolName,
    [Parameter(Mandatory,HelpMessage = 'The prefix of the new session-host name')]
    [string]$DestinationSessionHostPrefix,
    [Parameter(Mandatory,HelpMessage = 'Source host pools name')]
    [string]$SourceHostPoolName,
    [Parameter(Mandatory,HelpMessage = 'The virtual network to which the new VMs will be deployed')]
    [string]$vnetName,
    [Parameter(Mandatory,HelpMessage = 'The resource group of the virtual network to which the new VMs will be deployed')]
    [string]$vnetrg,
    [Parameter(Mandatory,HelpMessage = 'The subnet to which the new VMs will be deployed')]
    [string]$DestSubnetName,
    [Parameter(Mandatory,HelpMessage = 'The tag name (key) that the source VM will be filtered by')]
    [string]$TagName,
    [Parameter(Mandatory,HelpMessage = 'The value for TagName. VMs that have the tag specified in TagName with this value in the SourcevmResourceGroupName will be migrated.')]
    [string]$Tag,
    [Parameter(Mandatory,HelpMessage = 'The resource group of all the source resources. Works only if all the source items are in the same RG, and all the destination items are in the same RG. This parameter can shorten input',ParameterSetName='SingleRG')]
    [string]$SourceRG,
    [Parameter(Mandatory,HelpMessage = 'The resource group of all the new resources. Works only if all the source items are in the same RG, and all the destination items are in the same RG. This parameter can shorten input',ParameterSetName='SingleRG')]
    [string]$DestRG,
    [Parameter(Mandatory,HelpMessage = 'The application Id of the app registration that will be used to connect to azure and graph')]
    [string]$AppId,
    [Parameter(HelpMessage = 'Path to txt file that contains the app registration client secret as SecureString. Default is $env:USERPROFILE\Documents\appsecret.txt')]
    [string]$PathToAppRegPass = "$env:USERPROFILE\Documents\appsecret.txt",
    [Parameter(Mandatory,HelpMessage = 'Tenant id for the app registration authentication')]
    [string]$TenantId,
    [Parameter(HelpMessage = 'Use this switch to explicitly delete old resources at the end')]
    [switch]$DeleteOldResources


)
#>

#parameters
$Source_subscription_Id = "31076e3c-fc5e-4f0b-be52-0eb744e89036"
$Destination_subscription_Id = "31076e3c-fc5e-4f0b-be52-0eb744e89036"
$SourcevmResourceGroupName = "AVD-Test-Env-RG"
$SourceHostpoolResourceGroupName = "AVD-Test-Env-RG"
$DestinationvmResourceGroupName = "AVD-Test-Env-RG"
$galleryName = "test_gallery"
$location = "israelcentral"
$galleryResourceGroupName = "AVD-Test-Env-RG"
$DestHPresourceGroupName = "AVD-Test-Env-RG"
$DesthostPoolName = "AVD-Test-Env-Hostpool"
$DestinationSessionHostPrefix = "avd-tst-dev"
$SourceHostPoolName = "AVD-Test-Env-Hostpool"
$vnetName = "AVD-Test-Env-VNet"
$vnetrg = "AVD-Test-Env-RG"
$DestSubnetName = "AVD-Test-Env-VM-Sub"
$TagName = "test1"
$Tag = "true"
$SourceRG = "AVD-Test-Env-RG"
$DestRG = "AVD-Test-Env-RG"
$AppId = "88abefd9-4f32-450c-a5fc-27f69e780cfe"
$PathToAppRegPass = "$env:USERPROFILE\Documents\appsecret.txt"
$TenantId = "a986ce9f-e1ca-45ab-942e-e1ce27106918"


if($PSCmdlet.ParameterSetName -eq 'SingleRG'){
    $SourcevmResourceGroupName = $SourceRG
    $SourceHostpoolResourceGroupName = $SourceRG
    $galleryResourceGroupName = $SourceRG

    $DestinationvmResourceGroupName = $DestRG
    $DestHPresourceGroupName = $DestRG
}



$functions = {

    Function Upload-VMImageToComputeGallery{
    param(
        [Parameter(Mandatory,Position=0,ValueFromPipeline)]
        [xml]$VMXml,
        [Parameter(HelpMessage="Region on which the image will be avalilable. Replica Count is set to 1. Default is israelcentral. If you don't like it you are welcome to write your own function.")]
        [string]$Location = 'israelcentral',
        [Parameter(Mandatory)]
        [string]$galleryResourceGroupName,
        [Parameter(Mandatory)]
        [string]$galleryName
    )

    ## DEBUG ##
    #return Get-AzGalleryImageVersion -GalleryImageDefinitionName $galleryImageDefinitionName -ResourceGroupName $galleryResourceGroupName -GalleryName $galleryName -ErrorAction SilentlyContinue
    ###########

    $xml = $VMXml.Objects.Object.Property

    $vmName = $xml | ?{$_.Name -eq 'Name'} | select -ExpandProperty "#text"
    $vmId = $xml | ?{$_.Name -eq 'Id'} | Select -ExpandProperty "#text"

    $region1 = @{Name=$Location;ReplicaCount=1}
    $targetRegions = @($region1)

    #create Image Definition
    $galleryImageDefinitionName = "$vmName-Image"
    $publisherName = "MCS"
    $offerName = ((($xml | ?{$_.Name -eq 'StorageProfile'}).Property | ?{$_.Name -eq "ImageReference"}).Property | ?{$_.Name -eq "Offer"})."#text"
    if(-not $offerName){
        $offerName = "microsoftwindowsdesktop-$publisherName"
    }
    $skuName = "$vmName"
    $osType = $VMXml.Objects.Object.SelectSingleNode("//Property[@Name='StorageProfile']//Property[@Name='OsDisk']//Property[@Name='OsType']").Property."#text" # find the os type
    try{
        $enumType = [Microsoft.Azure.Commands.Common.Compute.Version_2018_04.Models.OperatingSystemTypes]
        #check if ostype is well defined. If not, fallback to Windows. If so, set the OSType appropriately.
        if(-not $osType){
            $osType = "Windows"        
        }
        elseif([enum]::IsDefined($enumType,$osType)){
            $osType = [enum]::GetName($enumType,$osType)
        }
        else{
            $osType = "Windows"
        }
    }catch{
        $osType = "Windows"
    }
    $description = "Snapshot for Session Host $vmName (Specialized)"
    $trustedLaunch = @{Name='SecurityType';Value='TrustedLaunch'}

    Write-Host "[IMAGE DEFINITION]: Stopping & Capturing a VM image from $vmName. This will take about 10 minutes"

    try{
        $imageDef = Get-AzGalleryImageDefinition -ResourceGroupName $galleryResourceGroupName -GalleryName $galleryName -Name $galleryImageDefinitionName -ErrorAction SilentlyContinue
        if(-not $imageDef){ # Image definition does not exists
            $null = New-AzGalleryImageDefinition -ResourceGroupName $galleryResourceGroupName -GalleryName $galleryName -Name $galleryImageDefinitionName -Location $Location -Publisher $publisherName -Offer $offerName -Sku $skuName -OsState "Specialized" -OsType $osType -Description $description -Feature @($trustedLaunch)
        }
        $version = Get-AzGalleryImageVersion -GalleryImageDefinitionName $galleryImageDefinitionName -ResourceGroupName $galleryResourceGroupName -GalleryName $galleryName -ErrorAction SilentlyContinue | sort -Property Name -Descending | select -First 1 -ExpandProperty Name -ErrorAction SilentlyContinue | %{$lastVersion = [version]$_ ; [version]::new($lastVersion.Major,$lastVersion.Minor,$lastVersion.Build + 1)}
        if(-not $version){
            Write-Host "[IMAGE DEFINITION]: Could not find versions. Setting to default (1.0.0)" -ForegroundColor Gray
            $version = "1.0.0"
        }
        $image = New-AzGalleryImageVersion -ResourceGroupName $galleryResourceGroupName -GalleryName $galleryName -GalleryImageDefinitionName $galleryImageDefinitionName -Name $version -Location $Location -SourceImageVMId $vmId -TargetRegion $targetRegions
        if(-not $image){
            Write-Warning "[IMAGE DEFINITION]: Failed capturing image: $vmName"
            Write-Host "[IMAGE DEFINITION]: Skipping to next VM..."
            return;
        }
        Write-Host "[IMAGE DEFINITION]: Image Definition Created successfully" -ForegroundColor Green

        #Capture the specialized image
        $sourceRG = ($xml | ?{$_.Name -eq 'ResourceGroupName'})."#text"
        $stopRes = Stop-AzVM -ResourceGroupName $sourceRG -Name $vmName -Force
        if($stopRes){
            if($stopRes.Status -eq "Succeeded"){
                Write-Host "[IMAGE DEFINITION]: VM Stopped: $vmName"

                Write-Host "[IMAGE DEFINITION]: VM Image created succesfully" -ForegroundColor Cyan
                return $image
            }
        }

        Write-Warning "[IMAGE DEFINITION]: Catch: Failed shutdown image: $vmName"
        Write-Host "[IMAGE DEFINITION]: Skipping to next VM..."
        return;
        
    }
    catch{
        Write-Host $_ -ForegroundColor Red
        Write-Warning "[IMAGE DEFINITION]: Catch: Failed capturing image: $vmName"
        Write-Host "[IMAGE DEFINITION]: Skipping to next VM..."
        return;
    }
}
    
    Function New-VMConfiguration{
        param(
            [Parameter(Mandatory)]
            [string]$VMName,
            [Parameter(Mandatory)]
            [string]$VMSize,
            [Parameter(Mandatory, HelpMessage='$nic.id')]
            [string]$nicId,
            [Parameter(Mandatory, HelpMessage='$image.id')]
            [string]$imageId,
            [Parameter()]
            [hashtable]$tags = @{}

        )
    Write-Host "[VM Configuration]: Creating VM with size: $VMSize"
    $vmConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize -Tags $tags
    $vmConfig = Set-AzVMSourceImage -VM $vmConfig -Id $imageId
    $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nicId
    $vmConfig = Set-AzVMOSDisk -VM $vmConfig -Name "osdisk$VMName" -CreateOption FromImage -StorageAccountType "StandardSSD_LRS"
    $vmConfig.SecurityProfile = @{
        SecurityType = "TrustedLaunch"
    }

    return $vmConfig
}
    
    Function New-MyVM{
    param(
        [Parameter()]
        [string]$location = "israelcentral",
        [Parameter(Mandatory)]
        [string]$DestinationvmResourceGroupName,
        [Parameter(Mandatory, HelpMessage="PSVirtualMachineConfig Object")]
        [object]$VMConfig,
        [Parameter(Mandatory, HelpMessage="Registration Token for the destination host pool")]
        [string]$registrationToken
    )

    # Create a new VM configuration
    
    #why did he returned to the source subscription. Would it be more accurate to create the new vm in the destination subscription?
    #Set-AzContext -Subscription $Source_subscription_Id -ErrorAction SilentlyContinue | Out-Null
    

    $vmName = $VMConfig.Name

    #region create new vm

    try{
        # Create the VM in the destination resource group from the captured image
        $newVM = New-AzVM -ResourceGroupName $DestinationvmResourceGroupName -Location $location -VM $vmConfig -WarningAction SilentlyContinue -ErrorAction Stop

        if(-not $newVM.IsSuccessStatusCode){
            Write-Warning "[VM Creation]: Failed to create $vmName"
            return $false;
        }
        

        Write-Host "[VM Creation]: VM deployment completed successfully" -ForegroundColor Cyan
    }
    catch{
        Write-Warning "[VM Creation]: Failed to create $vmName"
        Write-Error $_
        return $false;
    }finally{
        $newVM = $null
    }
    try{
        # Register the VM to the destination host pool

        $script = @"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\RDInfraAgent" -Name "IsRegistered" -Value 0 -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\RDInfraAgent" -Name "RegistrationToken" -Value $registrationToken -Force
"@
    
        # Invoke command to register the VM to the host pool
        $activityRes = Invoke-AzVMRunCommand -ResourceGroupName $DestinationvmResourceGroupName -Name $vmName -CommandId 'RunPowerShellScript' -ScriptString $script
        if($activityRes.Status -ne "Succeeded")
        {
            Write-Warning "[VM Creation]: Failed registering VM $vmName to AVD (script execution)"
            return $false;
        }
        $activityRes = Restart-AzVM -ResourceGroupName $DestinationvmResourceGroupName -Name $vmName
        if($activityRes.Status -ne "Succeeded"){
            Write-Warning "[VM Creation]: Failed registering VM $vmName to AVD (restart)"
            return $false;
        }
        Write-Host "[VM Creation]: VM registered to host pool successfully" -ForegroundColor Green

        return $true;
    }
    catch{
        Write-Warning "[VM Creation]: Failed registering VM $vmName to AVD (general)"
        return $false;
    }finally{
        $activityRes = $null
    }
    
}
    
    
}


#region Connections

#Retrive app registration secret
while(-not (Test-Path $PathToAppRegPass)){
    Write-Warning "Could not find path $PathToAppRegPass because it does not exists."
    $PathToAppRegPass = Read-Host "try to enter the path again"
}
try{
    $appRegSecret = ConvertTo-SecureString -String $(Get-Content $PathToAppRegPass) -Force -ErrorAction Stop
}catch{
    Write-Error "FATAL: Failed to read the password file, probebly because the password was not encrypted by $(whoami) on $(hostname)." -Category InvalidArgument -CategoryActivity ConvertTo-SecureString -CategoryReason CryptographicException -ErrorId "ImportSecureString_InvalidArgument_CryptographicError,Microsoft.PowerShell.Commands.ConvertToSecureStringCommand"
    $plainTextPass = Read-Host "Insert password as plain text. In the next run it will be saved on $PathToAppRegPass (it will override whatever file currently in there)"
    $secure = ConvertTo-SecureString -AsPlainText -String $plainTextPass -Force
    $encrypted = ConvertFrom-SecureString -SecureString $secure
    Set-Content -Value $encrypted -Path $PathToAppRegPass -Force
    $appRegSecret = $secure
}


$cred = New-Object System.Management.Automation.PSCredential($AppId, $appRegSecret)
$cred | Export-Clixml -Path ".\EncryptedCreds.xml" -Force

# Login to Azure
Connect-AzAccount -Subscription $Source_subscription_Id -Credential $cred -Tenant $TenantId -ServicePrincipal

#Login to Entra
Connect-MgGraph -ClientSecretCredential $cred -TenantId $tenantId -NoWelcome

#Set working directory
if($PSScriptRoot){ # If running as script and not as a standalone command
    cd $PSScriptRoot
}

#Connect-Entra
$scriptStartTime = Get-Date
Write-Output "Script started at: $($scriptStartTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Output "Working directory is: $(pwd | select -ExpandProperty Path)"

#Save the password securly
#ConvertTo-SecureString -AsPlainText "<password_goes_here>" -Force | ConvertFrom-SecureString | New-Item -Path $env:USERPROFILE\Documents\appsecret.txt -ItemType File -Force

#endregion

$migrationResults = @()

#region obtain registration token
# Obtain destination hostpool RdsRegistrationInfotoken - valid for 12 hours
Set-AzContext -Subscription $Destination_subscription_Id -ErrorAction SilentlyContinue | Out-Null
$Registered = Get-AzWvdRegistrationInfo -SubscriptionId $Destination_subscription_Id -ResourceGroupName $DestHPresourceGroupName -HostPoolName $DesthostPoolName -ErrorAction Ignore
if (-not(-Not $Registered.Token)){$registrationTokenValidFor = (NEW-TIMESPAN -Start (get-date) -End $Registered.ExpirationTime | select Days,Hours,Minutes,Seconds)}
$registrationTokenValidFor
if ((-Not $Registered.Token) -or ($Registered.ExpirationTime -le (get-date)))
{
    $Registered = New-AzWvdRegistrationInfo -SubscriptionId $Destination_subscription_Id -ResourceGroupName $DestHPresourceGroupName -HostPoolName $DesthostPoolName -ExpirationTime (Get-Date).AddHours(12) -ErrorAction SilentlyContinue
}
$registrationToken = $Registered.Token

#endregion

Set-AzContext -Subscription $Source_subscription_Id -ErrorAction SilentlyContinue | Out-Null
# retrieve all VMs that are session host of the source Host Pool
$vmList = Get-AzVM -ResourceGroupName $SourcevmResourceGroupName | ?{$_.Tags[$TagName] -eq $Tag}
if(-not $vmList){
    Write-Warning "No VM found. Exiting..."
    return
}

$vmImageHash = @{}


foreach ($vm in $vmList) {
    
    $resourceTag = $null
    $assignedUser = ($userSessions = Get-AzWvdSessionHost -ResourceGroupName $SourceHostpoolResourceGroupName -HostPoolName $SourceHostPoolName -SessionHostName $vm.Name -SubscriptionId $Source_subscription_Id).AssignedUser
    
    if($assignedUser){
        
        Write-Host "Backuping assigned user $assignedUser of sessionhost $($vm.Name)"
        $resourceTag = (Update-AzTag -ResourceId $vm.Id -Tag @{'AssignedUser' = $assignedUser} -Operation Merge).Properties.TagsProperty["AssignedUser"]

        if(-not $resourceTag){
            Write-Warning "Failed saving $($vm.Name) assigned user. Skipping for VM..."
            continue
        }
    }

############################################################################################################   
    # Remove the existing session host object from the source host pool
    try {
        $sessionHost = Get-AzWvdSessionHost `
            -ResourceGroupName $SourceHostpoolResourceGroupName `
            -HostPoolName $SourceHostPoolName `
            -SessionHostName $vm.Name `
            -SubscriptionId $Source_subscription_Id `
            -ErrorAction SilentlyContinue

        if ($sessionHost) {
            Write-Host "Removing session host $($sessionHost.Name) from source host pool"

            Remove-AzWvdSessionHost `
                -ResourceGroupName $SourceHostpoolResourceGroupName `
                -HostPoolName $SourceHostPoolName `
                -Name ($sessionHost.Name).split("/")[-1] `
                -SubscriptionId $Source_subscription_Id `
                -Force

            Write-Host "Session host removed successfully"
        }
    }
    catch {
        Write-Warning "Failed to remove session host for $($vm.Name): $_"
        continue
    }

###############################################################################################################

    Write-Host "Starting upload for VM: $($vm.Name)" -ForegroundColor Cyan    
    $vmxml = ConvertTo-Xml $vm.ToPSVirtualMachine() -Depth 10
    $vmImageHash[$vm.Name] = [pscustomobject]@{ImageJob = $(Start-Job -Name $vm.Name -InitializationScript $functions -ScriptBlock {Upload-VMImageToComputeGallery -VMXml $args[0] -galleryResourceGroupName $args[1] -galleryName $args[2]} -ArgumentList $vmxml,$galleryResourceGroupName,$galleryName) ; VMImageSize = $vm.HardwareProfile.VmSize ; VMTags = $vm.Tags ; VMId = $vm.Id ; AssignedUser = $assignedUser}
}


Write-Host "Removing all group memberships"
$failedVM = @()
foreach ($vmName in $vmImageHash.Keys){

    
    $sourceVMId = $vmImageHash[$vmName].VMId
    $assignedUser = $vmImageHash[$vmName].AssignedUser

    if($assignedUser){
        $removalState = .\FixGroup.ps1 -VMId $sourceVMId -Assignee $assignedUser
        if(-not $removalState){
            Write-Warning "Failed to remove the membership of $assignedUser, who was assigned to $vmName. Stopping the process for this VM"
            $failedVM += $vmName
        }
    }
}
$failedVM | %{
    $vmImageHash.Remove($_)
}

if($vmImageHash.Count -eq 0){
    Write-Warning "Failed to extract members of all groups. Exiting..."
    return;
}

Write-Host "Finished Removing memberships"

Write-Host "Waiting for all VM to be uploaded to Compute Gallery. Go drink coffee or something."

$l = $vmImageHash.Count
$i = 0

for(;;){
    $vmImageHash.Values.ImageJob | Wait-Job -Timeout 10 | Out-Null

    $i = ($vmImageHash | ?{$_.Values.Image.State -notcontains "Running"}).Count
    $p = $i * 100 / $l

    Write-Progress "Uploading snapshots to Compute Gallery" -Status "Finished $i out of $l images ($($p.ToString("#0.00"))%)" -PercentComplete $p
    if($vmImageHash.Values.ImageJob.State -notcontains "Running")
    {
        break;
    }
}

Write-Host "Finished uploading images"

#region prepare VM periferials
Set-AzContext -Subscription $Destination_subscription_Id -ErrorAction SilentlyContinue | Out-Null
$vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $vnetrg
$subnet = $vnet.Subnets | Where-Object { $_.Name -eq $DestSubnetName }

if (-not $subnet) {
    Write-Error "Subnet '$DestSubnetName' not found in VNet '$vnetName'. Available subnets: $($vnet.Subnets.Name -join ', ')"
    return;
}
#endregion


$vmCreateJobs = @()

$destHostPool = Get-AzWvdHostPool -Name $DesthostPoolName -ResourceGroupName $DestinationvmResourceGroupName
#Find the highest index of SH in destination and add 1
$index = Get-AzWvdSessionHost -HostPoolName $DesthostPoolName -ResourceGroupName $DestinationvmResourceGroupName | Select -ExpandProperty Name | %{[int]([regex]::Match($_,'\d*$').Value) + 1} | sort -Descending | select -Index 0

if(-not $index){
    $index = 0
}

foreach ($vmName in $vmImageHash.Keys){

    $nic = $null
    $image = $null
    $vmExist = $null


    $sourceVMId = $vmImageHash[$vmName].VMId

    $newVMName = "$DestinationSessionHostPrefix-$index"

    $vmExist = Get-AzVM -ResourceGroupName $DestinationvmResourceGroupName -Name $newVMName -ErrorAction SilentlyContinue
    while($vmExist){
        $index++
        Write-Warning "There is already a VM with the name $newVMName in resource group $DestinationvmResourceGroupName."
        $newVMName = "$DestinationSessionHostPrefix-$index"
        Write-Warning "Renaming the VM to $newVMName"
        $vmExist = Get-AzVM -ResourceGroupName $DestinationvmResourceGroupName -Name $newVMName -ErrorAction SilentlyContinue
    }

    if($vmImageHash[$vmName].ImageJob.HasMoreData) {
        $image = $vmImageHash[$vmName].ImageJob | Receive-Job -Wait -AutoRemoveJob
    } 
    else{
        Set-AzContext $Source_subscription_Id | Out-Null
        $image = Get-AzGalleryImageVersion -ResourceGroupName $galleryResourceGroupName -GalleryName $galleryName -GalleryImageDefinitionName "$($vmName)-Image" | sort -Property Name | select -Last 1
        Set-AzContext $Destination_subscription_Id | Out-Null
    }
    if(-not $image){
        Write-Warning "Failed to retrieve image for $vmName. $($image.Count) objects returned. Expected 1. Returned Objects:`n$($image -join "`n")"
    }
    else{

        
        Write-Host "Re-Deploying VM $vmname in $DestinationvmResourceGroupName, in Destination subscription. This will take a few minutes"
        
        # Create a new NIC
        $nic = New-AzNetworkInterface -ResourceGroupName $DestinationvmResourceGroupName -Location $location -Name "$newVMName-nic" -SubnetId $subnet.Id -Force

        $tags = $vmImageHash[$vmName].VMTags

        $tags = [hashtable]$tags

        $tags.Add("avd-mig-src-vm",$vmName)

        $tags.Add("AssignedUserMig",$vmImageHash[$vmName].AssignedUser)

        $imageId = $image.Id
        if($imageId.Count -ne 1){
            Write-Host "Recieved $($imageId.Count) images. Picking the first one."
            $imageId = $imageId[0]
        }


        $vmCreateJobs += Start-Job -InitializationScript $functions -Name $newVMName -ScriptBlock {
            $vmConfig = New-VMConfiguration -VMName $args[0] -VMSize "Standard_D4as_v5" -nicId $args[2] -imageId $args[3] -tags $args[7]
            if($vmConfig){
                Write-Host "Creating new vm $newVMName :"
                $isSuccessful = New-MyVM -location $args[4] -VMConfig $vmConfig -DestinationvmResourceGroupName $args[5] -registrationToken $args[6]
                if($isSuccessful){
                    return $args[8]
                }
            }
            return $null
        } -ArgumentList @($newVMName, $vmImageHash[$vmName].VMImageSize, $nic.Id, $imageId, $location, $DestinationvmResourceGroupName,$registrationToken, $tags, $sourceVMId)

        $index++
    }
}

Write-Host "Creating new VMs..."

$l = $vmCreateJobs.Count

do{
    $i = ($vmCreateJobs | ?{$_.State -notcontains "Running"}).Count
    $p = $i * 100 / $l

    Write-Progress "Creating new VMs from image" -Status "Finished $i out of $l VMs ($($p.ToString("#0.00"))%)" -PercentComplete $p
    $vmCreateJobs | Wait-Job -Timeout 10 | Out-Null
}while($vmCreateJobs.State -contains "Running")

Write-Host "Finished Creating VMs"


foreach($job in $vmCreateJobs | ?{$_.State -eq 'Completed'}){

    $oldVMId = Receive-Job -Job $job -Wait -AutoRemoveJob -ErrorAction SilentlyContinue
    
    if(-not $?){ # If the job failed, print a fitting message and skip

        Write-Warning "Failed to create VM $($job.Name). Skipping..."
    }
    elseif(-not $oldVMId){
        Write-Warning "Could not find source VM for $($job.Name). Skipping..."
    }
    else{
        $oldVM = $oldVMId.Split("/")[-1]

        $assignedUser = $vmImageHash[$oldVM].AssignedUser
        

        $vmName = $job.Name
        $dstVMId = "/subscriptions/$Destination_subscription_Id/resourceGroups/$DestinationvmResourceGroupName/providers/Microsoft.Compute/virtualMachines/$vmName"

        # Register the VM to the destination host pool
        # --- MIGRATE USER ASSIGNMENTS FROM SOURCE HOSTPOOL TO DESTINATION HOSTPOOL HAS BEEN MOVED TO EntraOrc.ps1 ---
 
        $migrationResults += [pscustomobject]@{OldVMId=$oldVMId; NewVMId=$dstVMId; OldName=$oldVM ; NewName=$vmName ; Assignee = $assignedUser ; SrcHP = $SourceHostPoolName ; DstHP = $DesthostPoolName ; IsSuccessfull = $true}
    }

}

#endregion


#region cleanup


$scriptEndTime = Get-Date
$totalRuntime = New-TimeSpan -Start $scriptStartTime -End $scriptEndTime
Write-Host "Migration Summary: $($migrationResults | ?{$_.IsSuccessfull } | measure | select -ExpandProperty Count) out of $($vmList.Count) VMs migrated successfully"

$unknownVMs = Compare-Object $vmList.Name $migrationResults.OldName | select -ExpandProperty InputObject
foreach($unknownVM in $unknownVMs){

    $srcVMId = "/subscriptions/$Source_subscription_Id/resourceGroups/$SourcevmResourceGroupName/providers/Microsoft.Compute/virtualMachines/$unknownVM"    
    $migrationResults += [pscustomobject]@{OldVMId = $srcVMId ; NewVMId = "" ; Assignee = "" ; IsSuccessfull = $false}
}

Write-Host "Failed Migrations:"
$migrationResults | ?{-not $_.IsSuccessfull}

$migrationResults | Export-Csv -Path .\MigrationResult.csv -NoTypeInformation -Force -Encoding UTF8
if($DeleteOldResources){
    Set-AzContext -Subscription $Source_subscription_Id -ErrorAction SilentlyContinue | Out-Null

    #find resource name of vm successfully migrated
    $successfulMigrations = $migrationResults | ?{$_.IsSuccessfull} | %{Split-Path -Leaf -Path $_}
    # Delete old session host dangling object
    $successfulMigrations | %{}
    # Delete successfully migrated VMs from source subscription
    foreach($vmToDelete in $successfulMigrations){
        
        try{
            Write-Host "Attempting to delete $vmToDelete SessionHost object"
            $delRes = Remove-AzWvdSessionHost -HostPoolName $SourceHostPoolName -ResourceGroupName $SourcevmResourceGroupName -Name $_ -SubscriptionId $Source_subscription_Id -Force
            if($delRes){
                Write-Host "Deleted $vmToDelete session host successfully"
            }else{
                Write-Warning "Failed to delete $vmToDelete session host"
            }

            if((Remove-AzVM -ResourceGroupName $SourcevmResourceGroupName -Name $vmToDelete -Force -ErrorAction Stop -AsJob).Status -eq "Success"){
                Write-Host "Removed $vmToDelete Successfully"
            }
            else{
                Write-Warning "Failed to remove $vmToDelete"
            }

        }catch{
            Write-Warning "Failed cleaning after $vmToDelete"
        }
    }
}


$null = Get-Job | Wait-Job
$null = Get-Job | Remove-Job


Write-Output "Total script runtime: $($totalRuntime.Hours)h $($totalRuntime.Minutes)m $($totalRuntime.Seconds)s"
Write-Output "Script completed at: $($scriptEndTime.ToString('yyyy-MM-dd HH:mm:ss'))"

#endregion