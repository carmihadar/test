Function Add-EntraGroup{

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory,HelpMessage="UPN of an assignee",ParameterSetName = "Normal")]
        [string]$Assignee,
        [Parameter(Mandatory,HelpMessage="Resource ID for the VM in process (destination if adding)")]
        [string]$VMId
    )

    if($PSCmdlet.ShouldProcess($Assignee, "Add permission to user")){
        
        return .\FixGroup.ps1 -Assignee $Assignee -VMId $VMId -Adding
    }
}
Function Remove-EntraGroup{

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory,HelpMessage="UPN of an assignee",ParameterSetName = "Normal")]
        [string]$Assignee,
        [Parameter(Mandatory,HelpMessage="Resource ID for the VM in process (source)")]
        [string]$VMId
    )

    if($PSCmdlet.ShouldProcess($Assignee, "Remove permissions")){
        return .\FixGroup.ps1 -Assignee $Assignee -VMId $VMId
    }
    return $false
}
Function Restore-EntraGroup{

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory,HelpMessage="Resource ID for the VM in process (source)")]
        [string]$VMId
    )

    if($PSCmdlet.ShouldProcess($VMId, "Restore groups membership")){
        return .\FixGroup.ps1 -VMId $VMId
    }

    return $false
}

Function Rename-ManagedDev{

    [CmdletBinding(SupportsShouldProcess)]    
    param(
        [Parameter(Mandatory,HelpMessage="Old name of the VM",Position=0)]
        [string]$OldVMName,
        [Parameter(Mandatory,HelpMessage="New name for the VM",Position=1)]
        [string]$NewVMName
    )

    if($PSCmdlet.ShouldProcess($OldVMName, "Rename VM")){
     return pwsh -file ".\RenameVM.ps1" $OldVMName $NewVMName
    }

    return 1
}

Function Remove-Assignment{

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory,HelpMessage="Resource ID of old VM")]
        [string]$VmId,
        [Parameter(Mandatory,HelpMessage="Source HostPool name")]
        [string]$HPName
    )

    $idArr = $VmId.Split("/",[System.StringSplitOptions]::RemoveEmptyEntries)


    $subscription = $idArr[1]
    $rgName = $idArr[3]
    $name = $idArr[7]

    if($PSCmdlet.ShouldProcess($name, "Remove User Assignment")){

        $assignedUser = ($userSessions = Get-AzWvdSessionHost -ResourceGroupName $rgName -HostPoolName $SrcHPName -SessionHostName $name -SubscriptionId $subscription).AssignedUser

   #     $oldSH = Update-AzWvdSessionHost -ResourceGroupName $rgName -HostPoolName $SrcHPName -SessionHostName $name -AssignedUser $null -Force -SubscriptionId $subscription
   #     if(-not [string]::IsNullOrEmpty($oldSH.AssignedUser)){
   #         return ""
   #     }
   #     return $assignedUser
   # }
   # else{
   #     return ""
   # }

    return $assignedUser
}


$migrations = Import-Csv -Path .\MigrationResult.csv -Encoding UTF8



$l = $migrations | ?{$_.IsSuccessfull -eq 'True' -and $_.Assignee} | measure | select -ExpandProperty count
$i = 0

Write-Host "Removing assignments" -ForegroundColor Cyan
foreach($migration in $migrations){

    $migrations.IsSuccessfull = $migration.IsSuccessfull -eq 'True'
    $migration | Add-Member -MemberType NoteProperty -Name "Message" -Value ""

    if($migration.IsSuccessfull -and $migration.Assignee){
        $p = $i * 100 / $l
        $newName = $migration.NewVMId.Split("/")[-1]
        $oldName = $migration.OldVMId.Split("/")[-1]

        Write-Progress -Activity "Unassigning users from Session Hosts" -Status "Processed $i session hosts out of $l" -CurrentOperation "Unassining user $($migration.Assignee) from $oldName" -PercentComplete $p


        $assigned = Remove-Assignment -VmId $migration.OldVMId -HPName $migration.SrcHP -Confirm

        if($assigned){
            Write-Debug "Updated Assignment for $oldName"
            $migration.Message = "Updated Assignment for $oldName"
            $migration.IsSuccessfull = $true

            
        }else{
            # Unassignment failed

            Write-Warning "Failed to remove assignment for $oldName"
            $migration.Message = "Failed to remove assignment for $oldName"
            $migration.IsSuccessfull = $false
        }

        $i++
    }

}
Write-Host "Done.`nRenaming Session Hosts..."


$l = $migrations | ?{$_.IsSuccessfull} | measure | select -ExpandProperty count
$i = 0

foreach($migration in $migrations | ?{$_.IsSuccessfull}){
    $newName = $migration.NewVMId.Split("/")[-1]
    $oldName = $migration.OldVMId.Split("/")[-1]
    
    $p = $i * 100 / $l
    Write-Progress -Activity "Renaming Session Hosts" -Status "Processed $i machines out of $l" -PercentComplete $p -CurrentOperation "Renaming $oldName to $newName"
    
    Write-Debug "Renaming $oldName to $newName"
    $renameOutput = Rename-ManagedDev -OldVMName $oldName -NewVMName $newName -Confirm
    Write-Debug $renameOutput[0..$renameOutput.Count-2]
    $res = -not[bool][int]$renameOutput[-1]
    
    if($res){
        #Rename and restart requests sent successfully
        Write-Debug "Sent rename request to $oldName"
        $migration.Message = "Sent rename request to $oldName"
        $migration.IsSuccessfull = $true
    }
    else{
        #Failed to send rename or restart request
        Write-Warning "Failed renaming $oldName"  
        $migration.Message = "Failed renaming $oldName"
        $migration.IsSuccessfull = $false
         
    }
    
    $i++
}

$migrations | Export-Csv -Path .\RenameResult.csv -NoTypeInformation -Force -Encoding UTF8


$migrations1 = Import-Csv -Path .\MigrationResult.csv -Encoding UTF8

$i = 0
$l = [int](($migrations1 | ?{$_.IsSuccessfull -eq 'False'}).Count)

Write-Host "Done. Restoring groups for $l failed vm"

#Restoring old group if failed
foreach($migration in $migrations1 | ?{$_.IsSuccessfull -eq 'False'}){
    $p = $i * 100 / $l
    Write-Progress -Activity "Restoring groups for failed VMs" -Status "Finished $i out of $l groups ($($p.ToString("#0.00"))%)" -PercentComplete $p
    Restore-EntraGroup -VMId $migration.OldVMId -Confirm
}

Write-Host "Done. See you in 8 hours :)" -ForegroundColor Cyan
