# needs contributer on the session host VM resource groups

Param
(
    [Parameter (Mandatory= $true)]
    [string] $workspaceName,

    [Parameter (Mandatory= $true)]
    [string] $userName
)

Connect-AzAccount -Identity | Out-Null
Set-AzContext -SubscriptionId "69d34344-d7b7-4dc2-aefa-fda3c77fb570" | Out-Null

$upn = "xd.$userName@idf.il"

# Find the workspace by name across the subscription.
$workspace = Get-AzWvdWorkspace | Where-Object { $_.Name -ieq $workspaceName }

if (-not $workspace) {
    Write-Output "[ERROR] Workspace - $workspaceName not found 🚩"
    Write-Error  "[ERROR] Workspace - $workspaceName not found 🚩"
    throw
}

if (@($workspace).Count -gt 1) {
    Write-Output "[ERROR] Multiple workspaces found with name - $workspaceName 🚩. Name must be unique."
    Write-Error  "[ERROR] Multiple workspaces found with name - $workspaceName 🚩."
    throw
}

# Resolve the hostpools behind the workspace through its application groups.
$hostpoolIds = @()
foreach ($appGroupId in $workspace.ApplicationGroupReference) {
    $parts       = $appGroupId -split "/"
    $appGroupRg  = $parts[4]
    $appGroupName = $parts[-1]

    $appGroup = Get-AzWvdApplicationGroup -Name $appGroupName -ResourceGroupName $appGroupRg
    if ($appGroup.HostPoolArmPath) {
        $hostpoolIds += $appGroup.HostPoolArmPath
    }
}

$hostpoolIds = $hostpoolIds | Select-Object -Unique

if (-not $hostpoolIds) {
    Write-Output "[ERROR] No hostpools linked to workspace - $workspaceName 🚩"
    Write-Error  "[ERROR] No hostpools linked to workspace - $workspaceName 🚩"
    throw
}

# Look through every hostpool's session hosts for the one assigned to the user.
$userSessionHost = $null
foreach ($hostpoolId in $hostpoolIds) {
    $hpParts   = $hostpoolId -split "/"
    $hpRgName  = $hpParts[4]
    $hpName    = $hpParts[-1]

    $sessionHosts = Get-AzWvdSessionHost -HostPoolName $hpName -ResourceGroupName $hpRgName
    foreach ($sessionHost in $sessionHosts) {
        if ($sessionHost.AssignedUser -ieq $upn) {
            $userSessionHost = $sessionHost
            break
        }
    }

    if ($userSessionHost) { break }
}

if (-not $userSessionHost) {
    Write-Output "[ERROR] No session host found for user - $upn in workspace - $workspaceName 😢"
    Write-Error  "[ERROR] No session host found for user - $upn in workspace - $workspaceName 😢"
    throw
}

# Session host name has the form "hostpoolName/vmName.domain" — take the VM name.
$vmName = ($userSessionHost.Name -split "/")[-1].Split(".")[0]

$vm = Get-AzVM | Where-Object { $_.Name -ieq $vmName }

if (-not $vm) {
    Write-Output "[ERROR] VM - $vmName for user - $upn not found 🚩"
    Write-Error  "[ERROR] VM - $vmName for user - $upn not found 🚩"
    throw
}

# Determine current power state so a stopped, deallocated or hibernated VM is started before restarting.
$powerState = (Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vmName -Status).Statuses |
    Where-Object { $_.Code -like "PowerState/*" } |
    Select-Object -First 1 -ExpandProperty Code

if ($powerState -ne "PowerState/running") {
    Write-Output "[INFO] Session host VM - $vmName is not running ($powerState). Starting it... ⚡"
    Start-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vmName | Out-Null
    Write-Output "[INFO] Session host VM - $vmName started ✅"
}

Write-Output "[INFO] Restarting session host VM - $vmName for user - $upn... 🔄"

Restart-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vmName | Out-Null

Write-Output "[INFO] Successfully restarted session host VM - $vmName for user - $upn 🎉"
