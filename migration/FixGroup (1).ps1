param(
    [Parameter(Mandatory,HelpMessage="UPN of an assignee",ParameterSetName = "Normal")]
    [string]$Assignee,
    [Parameter(Mandatory,HelpMessage="Resource ID for the VM in process (source if removing or recovering, destination if adding)")]
    [string]$VMId,
    [Parameter(HelpMessage="Mark flag to add members to a group")]
    [switch]$Adding
)

#Save path for backup
$scriptDir  = Split-Path -Path $($MyInvocation.MyCommand.Path) -Parent
$path = "$scriptDir\MembershipBackup\$($VMId.Split("/")[-1]).csv"


Function Add-MgGroupMember{
    param(
        [Parameter(Mandatory,HelpMessage="Object Id of the group member")]
        [string]$MemberId,
        [Parameter(Mandatory,HelpMessage="Object Id of the group")]
        [string]$GroupId
    )

    $membership = (Get-MgGroupMember -GroupId $GroupId).Id
    if($membership -contains $MemberId){
        # The directory object is already a member of the group.
        return $true
    }

    $params = @{
	    "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$MemberId"
    }

    return New-MgGroupMemberByRef -GroupId $GroupId -BodyParameter $params -PassThru
}

#region normal flow

#Adding or removing members normally. Not Recovery flow.
if($PSCmdlet.ParameterSetName -eq "Normal"){

    $assigneeId = Get-MgUser -Filter "userPrincipalName eq '$Assignee'" | select -ExpandProperty Id
    

    #Adding members to destination AVD group
    if($Adding){
        $isDev = $VMId.Split("/")[-1] -like "*dev*"
        
        
        $roleName = IF($isDev) {"Virtual Machine Administrator Login"} ELSE {"Virtual Machine User Login"}

        $accessGroupId = Get-AzRoleAssignment -Scope $VMId -RoleDefinitionName $roleName | Select -ExpandProperty ObjectId

        if(-not $accessGroupId){
            Write-Error "Failed to retrive IAM for VM $VMId"
            return $false;
        }
        
        return Add-MgGroupMember -MemberId $assigneeId -GroupId $accessGroupId
    }
    else{ #Removing the member

        $adminIAM = Get-AzRoleAssignment -Scope $VMId -RoleDefinitionName "Virtual Machine Administrator Login"
        $userIAM = Get-AzRoleAssignment -Scope $VMId -RoleDefinitionName "Virtual Machine User Login"

        $res = $true

        foreach($groupId in $adminIAM.ObjectId){
            $membership = (Get-MgGroupMember -GroupId $groupId).Id
            if($assigneeId -in $membership){
                $memberships += [pscustomobject]@{GroupID = $groupId ; ObjectId = $assigneeId}
                $currRes = $true
                try{
                    Remove-MgGroupMemberByRef -GroupId $groupId -DirectoryObjectId $assigneeId -ErrorAction Stop
                }catch{
                    $currRes = $false
                }

                if(-not $currRes){
                    Write-Warning "Failed to remove membership of $assignee in $groupId"
                }

                $res = $currRes -and $res
            }
            $membership = $null
        }
    
        foreach($groupId in $userIAM.ObjectId){
            $membership = (Get-MgGroupMember -GroupId $groupId).Id
            if($assigneeId -in $membership){
                $memberships += [pscustomobject]@{GroupID = $groupId ; ObjectId = $assigneeId}
                $currRes = Remove-MgGroupMemberByRef -GroupId $groupId -DirectoryObjectId $directoryObjectId

                if(-not $currRes){
                    Write-Warning "Failed to remove membership of $assignee in $groupId"
                }

                $res = $currRes -and $res
            }
            $membership = $null
        }
        
       if($memberships){
            $memberships | Export-Csv -NoTypeInformation -Path $path -Encoding UTF8 -Append
       }

       return $res;
    }
}


#endregion

#region rollback

if( -not (Test-Path $path)){
    Write-Error "Could not find backup files for $VMId"
    return $false
}

$membership = Import-Csv -Path $path -Encoding UTF8

$res = 1

foreach($member in $membership){

    $res *= Add-MgGroupMember -MemberId $member.ObjectId -GroupId $member.GroupId
}

return [bool]$res

#endregion