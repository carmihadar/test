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

        $assignedUser = ($userSessions = Get-AzWvdSessionHost -ResourceGroupName $rgName -HostPoolName $HPName -SessionHostName $name -SubscriptionId $subscription).AssignedUser

        $oldSH = Update-AzWvdSessionHost -ResourceGroupName $rgName -HostPoolName $HPName -SessionHostName $name -AssignedUser $null -Force -SubscriptionId $subscription
        if(-not [string]::IsNullOrEmpty($oldSH.AssignedUser)){
            return ""
        }
        return $assignedUser
    }
    else{
        return ""
    }
}
Function Add-Assignment{

    [CmdletBinding(SupportsShouldProcess)]    
    param(
        [Parameter(Mandatory,HelpMessage="Resource ID of new VM. All identifier will be extracted by it.",ParameterSetName="ID")]
        [Parameter(Mandatory,HelpMessage="Resource ID of new VM. Subscription and resource group will be extracted by it.",ParameterSetName="ExplicitName")]
        [string]$VMId,
        [Parameter(Mandatory,HelpMessage="Session host name. Use if the hostname is differnt from the resource name",ParameterSetName="ExplicitName")]
        [Parameter(Mandatory,HelpMessage="Session host name",ParameterSetName="Explicit")]
        [string]$SessionHostName,
        [Parameter(Mandatory,HelpMessage="Resource group of the session host",ParameterSetName="Explicit")]
        [string]$ResourceGroup,
        [Parameter(Mandatory,HelpMessage="Session host name",ParameterSetName="Explicit")]
        [string]$SubscriptionID,
        [Parameter(Mandatory,HelpMessage="Destination HostPool name")]
        [string]$HPName,
        [Parameter(Mandatory,HelpMessage="UPN of user to assign")]
        [string]$AssignedUser
    )

    if($VMId){ #Id was given, parameter set ID or ExplicitName
        $idArr = $VmId.Split("/",[System.StringSplitOptions]::RemoveEmptyEntries)


        $subscription = $idArr[1]
        $rgName = $idArr[3]
        $name = if($PSCmdlet.ParameterSetName -eq "ID") {$idArr[7]} ELSE {$SessionHostName}
    }
    else{ #No id was given. Parameter set Explicit 
        $subscription = $SubscriptionID
        $rgName = $ResourceGroup
        $name = $SessionHostName
    }

    if($PSCmdlet.ShouldProcess("$name - $AssignedUser","Assignment")){

        $newSH = Update-AzWvdSessionHost -ResourceGroupName $rgName -HostPoolName $HPName -SessionHostName $name -AssignedUser $assignedUser -SubscriptionId $subscription
        if($newSH.AssignedUser -ne $assignedUser){
            return $false
        }
        return $true
    }
    else{
        return $false
    }

}


$migrations = Import-Csv -Path .\MigrationResult.csv -Encoding UTF8


$entraRes = @()

$l = @($migrations | ?{$_.IsSuccessfull -eq 'True'}).Count
$i = 0

foreach($migration in $migrations | ?{$_.IsSuccessfull -eq 'True'}){
    $newName = $migration.NewVMId.Split("/")[-1]
    $oldName = $migration.OldVMId.Split("/")[-1]

    $p = $i * 100 / $l

    #Had an asssigned user
    if($migration.Assignee){

        Write-Progress -Activity "Moving Users" -Status "Finished $i out of $l machines ($($p.ToString("#0.00"))%)" -CurrentOperation "Granting $($migration.Assignee) Security group for $newName"
        # Adding assignment to successfull migrations
        
        $res = Add-EntraGroup -Assignee $migration.Assignee -VMId $migration.NewVMId -Confirm

        if($res){
            #Upadte group membership completed successfully. Removing Assignments  
            Write-Progress -Activity "Moving Users" -Status "Finished $i out of $l machines ($($p.ToString("#0.00"))%)" -CurrentOperation "Unassigning $($migration.Assignee) from $oldName"

            $assigned = $true#Remove-Assignment -VmId $migration.OldVMId -HPName $migration.SrcHP -Confirm
            if($assigned){
                #Successfuly unassigned user. Assigning to new Session Host.
                Write-Debug "Updated Assignment for $oldName"
                Write-Debug "Assigning $assigned to $newName"

                Write-Progress -Activity "Moving Users" -Status "Finished $i out of $l machines ($($p.ToString("#0.00"))%)" -CurrentOperation "Assigning $($migration.Assignee) to $newName"
                $res = Add-Assignment -VMId $migration.NewVMId -HPName $migration.DstHP -AssignedUser $migration.Assignee -SessionHostName $oldName -Confirm
                if($res){
                    # Successfully assigned user to new Session Host.
                    Write-Debug "Successfully assigned $assigned to $newName"
                    
                    Write-Debug "Renaming $oldName to $newName"
                    Write-Progress -Activity "Moving Users" -Status "Finished $i out of $l machines ($($p.ToString("#0.00"))%)" -CurrentOperation "Renaming $oldName to $newName"
    
                    $renameOutput = Rename-ManagedDev -OldVMName $oldName -NewVMName $newName -Confirm
                    $renameOutput[0..($renameOutput.Count-2)] -join "`n" | Write-Debug

                    $res = -not[bool][int]$renameOutput[-1]

                    if($res){
                        #Rename and restart requests sent successfully
                        Write-Debug "Sent rename request to $oldName"
                        $migration | Add-Member -MemberType NoteProperty -Name "Message" -Value "Sent rename request to $oldName"
                    }
                    else{
                        #Failed to send rename or restart request
                        Write-Warning "Failed renaming $oldName"  
                        $migration | Add-Member -MemberType NoteProperty -Name "Message" -Value "Failed renaming $oldName"
                         
                    }

                }
                else{
                    # Assignment failed
                    Write-Warning "Failed to assign $assigned to $newName"
                    $migration | Add-Member -MemberType NoteProperty -Name "Message" -Value "Failed to assign $assigned to $newName"
                }
            }
            else{
                # Unassignment failed

                Write-Warning "Failed to remove assignment for $oldName"
                $migration | Add-Member -MemberType NoteProperty -Name "Message" -Value "Failed to remove assignment for $oldName"
            }
        }
        else{
            #Failed to add membership to group
            Write-Warning "Failed adding permissions to $($migration.Assignee)"
            $migration | Add-Member -MemberType NoteProperty -Name "Message" -Value "Failed adding permissions to $($migration.Assignee)"
        }
    }
    else{
        #Did not had an assigned user
        Write-Debug "Renaming $oldName to $newName"
        Write-Progress -Activity "Moving Users" -Status "Finished $i out of $l machines ($($p.ToString("#0.00"))%)" -CurrentOperation "Renaming $oldName to $newName"

        $renameOutput = Rename-ManagedDev -OldVMName $oldName -NewVMName $newName -Confirm
        #Write-Debug $renameOutput[0..$renameOutput.Count-2]
        $renameOutput[0..($renameOutput.Count-2)] -join "`n" | Write-Debug
        $res = -not[bool][int]$renameOutput[-1]

        if($res){
            #Rename and restart requests sent successfully
            Write-Debug "Sent rename request to $oldName"
            $migration | Add-Member -MemberType NoteProperty -Name "Message" -Value "Sent rename request to $oldName"
        }
        else{
            #Failed to send rename or restart request
            Write-Warning "Failed renaming $oldName"  
            $migration | Add-Member -MemberType NoteProperty -Name "Message" -Value "Failed renaming $oldName"
             
        }
    }
    $entraRes += $migration

    $i++
}

$i = 0
$l = ($migrations | ?{ -not $_.IsSuccessfull}).Count

#Restoring old group if failed
foreach($migration in $migrations | ?{ -not $_.IsSuccessfull}){
    $p = $i * 100 / $l
    Write-Progress -Activity "Restoring groups for failed VMs" -Status "Finished $i out of $l groups ($($p.ToString("#0.00"))%)" -PercentComplete $p
    Restore-EntraGroup -VMId $migration.OldVMId -Confirm
}