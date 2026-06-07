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
        
        $newSessionHost = Get-AzWvdSessionHost -ResourceGroupName $rgName -HostPoolName $DesthostPoolName -Name $name -ErrorAction Ignore
        if(-not $newSessionHost){
            # Could not find new session host
            return $false
        }

        $newSH = Update-AzWvdSessionHost -ResourceGroupName $rgName -HostPoolName $DstHPName -SessionHostName $name -AssignedUser $assignedUser -SubscriptionId $subscription
        if($newSH.AssignedUser -ne $assignedUser){
            return $false
        }
        return $true
        
    }
    else{
        return $false
    }

}


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


$migrations = Import-Csv -Path .\RenameResult.csv -Encoding UTF8


$l = ($migrations | ?{$_.IsSuccessfull -eq 'True'}).Count
$i = 0


foreach($migration in $migrations | ?{$_.IsSuccessfull -eq 'True' -and $migration.Assignee}){
    $newName = $migration.NewVMId.Split("/")[-1]
    $oldName = $migration.OldVMId.Split("/")[-1]
    
    
    $p = $i * 100 / $l
    Write-Progress -Activity "Assigning Users" -Status "Processesed $i out of $l Session Hosts" -CurrentOperation "Granting entra permissions to $($migration.Assignee)" -PercentComplete $p
    $res = Add-EntraGroup -Assignee $migration.Assignee -VMId $migration.NewVMId -Confirm
    if($res){
        Write-Progress -Activity "Assigning Users" -Status "Processesed $i out of $l Session Hosts" -CurrentOperation "Assigning $($migration.Assignee) to $newName" -PercentComplete $p
    
        #Added users to session host security group. Assigning user
        Write-Debug "Assigning $assigned to $newName"
        
        $res = Add-Assignment -VMId $migration.NewVMId -HPName $migration.DstHP -AssignedUser $migration.Assignee -SessionHostName $newName -Confirm
    
        if($res){
            Write-Debug "Successfully assigned $assigned to $newName"
    
        }
        else{
        
            Write-Warning "Failed renaming $newName"  
            $migration.Message = "Failed renaming $newName"
        }
        
    
    }else{
        #Failed to add membership to group
        Write-Warning "Failed adding permissions to $($migration.Assignee)"
        $migration.Message = "Failed adding permissions to $($migration.Assignee)"
    }
    
    $i++
}