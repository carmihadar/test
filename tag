<#
.SYNOPSIS
    Azure Automation Runbook.
    For every host pool in the list, iterates its session hosts, reads the
    AssignedUser's Entra custom security attribute UserData.CompanyName, and
    applies that value as an Azure resource tag on the session host VM.

.DESCRIPTION
    Designed to run inside an Azure Automation Account using its Managed
    Identity (system-assigned by default, or user-assigned when a client id
    is supplied). No secrets are stored in the runbook.

.REQUIREMENTS
    Automation Account Managed Identity needs:
      * Microsoft Graph application permissions (admin consent), assigned to
        the managed identity as app roles:
          - CustomSecAttributeAssignment.Read.All
          - User.Read.All
      * Entra role assignment:
          - Attribute Assignment Reader (on the "UserData" attribute set)
      * Azure RBAC on the AVD resource groups / VMs:
          - Reader on the host pools
          - Tag Contributor (or Contributor) on the session host VMs

    Automation Account modules required (import from the gallery):
      * Az.Accounts, Az.Compute, Az.Resources, Az.DesktopVirtualization
      * Microsoft.Graph.Authentication, Microsoft.Graph.Users
#>

# ------------------------------------------------------------------
# PARAMETERS
# ------------------------------------------------------------------
param(
    [string]   $SubscriptionId = "31076e3c-fc5e-4f0b-be52-0eb744e89036",
    [string]   $AttributeSet  = "UserData",
    [string]   $AttributeName = "CompanyName",
    [string]   $TagName       = "unit-number",

    [string[]] $HostPools = @(
        "O19-UT-AVD-hp",
        "O19-T-AVD-hp",
        "hostpool-OpenSky-Trusted",
        "hostpool-OpenSky-Untrusted",
        "hostpool-9900-Dev",
        "hostpool-9900-DMZ",
        "hostpool-9900-Plat",
        "hostpool-9900-Trust",
        "hostpool-9900-Untrst",
        "hostpool-dev",
        "hostpool-plat",
        "MZP-DEV-AVD-hp"
    )
)

$ErrorActionPreference = "Stop"
Write-Output "SCRIPT STARTED"

# ------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------

<#
.SYNOPSIS
    Authenticates to Azure and Microsoft Graph using the Automation Account
    Managed Identity.
.DESCRIPTION
    Signs in to Azure with the managed identity, sets the target subscription
    context, and connects Microsoft Graph with the same identity. When a
    client id is supplied a user-assigned identity is used; otherwise the
    system-assigned identity is used.
#>
function Connect-Services {
    param(
        [Parameter(Mandatory)] [string] $SubscriptionId
    )
    Connect-AzAccount -Identity | Out-Null
    Connect-MgGraph   -Identity -NoWelcome
    

    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
}

<#
.SYNOPSIS
    Resolves the resource group name of a host pool by looking it up in a
    pre-loaded host pool catalog.
#>
function Get-HostPoolResourceGroup {
    param(
        [Parameter(Mandatory)] [string]   $HostPoolName,
        [Parameter(Mandatory)] [object[]] $Catalog
    )

    $hp = $Catalog | Where-Object { $_.Name -eq $HostPoolName } | Select-Object -First 1
    if (-not $hp) { return $null }
    return ($hp.Id -split "/")[4]
}

<#
.SYNOPSIS
    Extracts the underlying VM name from an AVD session host object.
#>
function Get-SessionHostVmName {
    param([Parameter(Mandatory)] [object] $SessionHost)

    $short = ($SessionHost.Name -split "/")[-1]
    return  ($short             -split "\.")[0]
}

<#
.SYNOPSIS
    Reads the UserData.CompanyName custom security attribute of an Entra user.
#>
function Get-UserCompanyName {
    param(
        [Parameter(Mandatory)] [string] $UserPrincipalNameOrId,
        [Parameter(Mandatory)] [string] $AttributeSet,
        [Parameter(Mandatory)] [string] $AttributeName
    )

    $user = Get-MgUser -UserId $UserPrincipalNameOrId `
                       -Property "customSecurityAttributes" `
                       -ErrorAction Stop

    $ap = $user.CustomSecurityAttributes.AdditionalProperties
    if (-not $ap) { return $null }

    # Case-insensitive key lookup helper (works for Hashtable and Dictionary<,>)
    $getVal = {
        param($bag, $wanted)
        if ($null -eq $bag) { return $null }
        foreach ($k in $bag.Keys) {
            if ($k -ieq $wanted) { return $bag[$k] }
        }
        return $null
    }

    $set = & $getVal $ap $AttributeSet
    if (-not $set) { return $null }

    $val = & $getVal $set $AttributeName
    if ($null -eq $val) { return $null }
    if ($val -is [string] -and [string]::IsNullOrWhiteSpace($val)) { return $null }

    return [string]$val
}

<#
.SYNOPSIS
    Merges the tag onto an Azure VM without overwriting other tags.
#>
function Set-VmCompanyNameTag {
    param(
        [Parameter(Mandatory)] [string] $VmResourceId,
        [Parameter(Mandatory)] [string] $TagName,
        [Parameter(Mandatory)] [string] $Value
    )

    Update-AzTag `
        -ResourceId $VmResourceId `
        -Tag        @{ $TagName = $Value } `
        -Operation  Merge | Out-Null
}

<#
.SYNOPSIS
    Builds a single result row for the summary report.
#>
function New-Result {
    param(
        [string] $HostPool,
        [string] $SessionHost,
        [string] $AssignedUser,
        [string] $CompanyName,
        [string] $Status
    )

    [PSCustomObject]@{
        HostPool     = $HostPool
        SessionHost  = $SessionHost
        AssignedUser = $AssignedUser
        CompanyName  = $CompanyName
        Status       = $Status
    }
}

<#
.SYNOPSIS
    Processes a single session host: reads the CURRENT assigned user's attribute
    and tags the underlying VM with it. The assigned user can change over time,
    so the existing tag is re-checked every run and updated when it has drifted;
    a VM is only skipped when its tag already matches the current user.
#>
function Invoke-SessionHostTagging {
    param(
        [Parameter(Mandatory)] [string]    $HostPoolName,
        [Parameter(Mandatory)] [object]    $SessionHost,
        [Parameter(Mandatory)] [hashtable] $VmLookup,
        [Parameter(Mandatory)] [string]    $AttributeSet,
        [Parameter(Mandatory)] [string]    $AttributeName,
        [Parameter(Mandatory)] [string]    $TagName
    )

    $vmName = Get-SessionHostVmName -SessionHost $SessionHost
    $user   = $SessionHost.AssignedUser

    if ([string]::IsNullOrWhiteSpace($user)) {
        Write-Output "  $vmName : no AssignedUser - skipped"
        return New-Result -HostPool $HostPoolName -SessionHost $vmName `
                          -Status   "Skipped (no assigned user)"
    }

    $vm = $VmLookup[$vmName]
    if (-not $vm) {
        Write-Warning "  $vmName : VM not found in subscription"
        return New-Result -HostPool $HostPoolName -SessionHost $vmName `
                          -AssignedUser $user -Status "Failed (VM not found)"
    }

    # Already tagged? Do NOT skip blindly - the assigned user may have changed,
    # so we still resolve the CURRENT user's CompanyName and compare below.
    try {
        $companyName = Get-UserCompanyName -UserPrincipalNameOrId $user `
                                           -AttributeSet  $AttributeSet `
                                           -AttributeName $AttributeName
    }
    catch {
        Write-Warning "  $vmName : failed to read user '$user' - $($_.Exception.Message)"
        return New-Result -HostPool $HostPoolName -SessionHost $vmName `
                          -AssignedUser $user -Status "Failed (read user)"
    }

    if ([string]::IsNullOrWhiteSpace($companyName)) {
        Write-Output "  $vmName : user '$user' has no $AttributeSet.$AttributeName"
        return New-Result -HostPool $HostPoolName -SessionHost $vmName `
                          -AssignedUser $user -Status "No CompanyName"
    }

    # Compare the current user's CompanyName against the tag already on the VM.
    $currentTag = if ($vm.Tags -and $vm.Tags.ContainsKey($TagName)) { [string]$vm.Tags[$TagName] } else { $null }
    if ($currentTag -eq $companyName) {
        Write-Output "  $vmName : tag $TagName='$companyName' already up to date - skipped"
        return New-Result -HostPool $HostPoolName -SessionHost $vmName `
                          -AssignedUser $user -CompanyName $companyName -Status "Skipped (up to date)"
    }

    if ($currentTag) {
        Write-Output "  $vmName : $user -> $AttributeSet.$AttributeName='$companyName' (was '$currentTag')"
    } else {
        Write-Output "  $vmName : $user -> $AttributeSet.$AttributeName='$companyName'"
    }

    try {
        Set-VmCompanyNameTag -VmResourceId $vm.Id -TagName $TagName -Value $companyName
        $status = if ($currentTag) { "Updated (was '$currentTag')" } else { "Tagged" }
        Write-Output "  $vmName : tag $TagName set to '$companyName'"
    }
    catch {
        Write-Warning "  $vmName : failed to tag - $($_.Exception.Message)"
        $status = "Failed (tag): $($_.Exception.Message)"
    }

    return New-Result -HostPool $HostPoolName -SessionHost $vmName `
                      -AssignedUser $user -CompanyName $companyName -Status $status
}

<#
.SYNOPSIS
    Processes every session host in a single host pool.
#>
function Invoke-HostPoolProcessing {
    param(
        [Parameter(Mandatory)] [string]    $HostPoolName,
        [Parameter(Mandatory)] [object[]]  $Catalog,
        [Parameter(Mandatory)] [hashtable] $VmLookup,
        [Parameter(Mandatory)] [string]    $AttributeSet,
        [Parameter(Mandatory)] [string]    $AttributeName,
        [Parameter(Mandatory)] [string]    $TagName
    )

    Write-Output "`nHost Pool: $HostPoolName"

    $rg = Get-HostPoolResourceGroup -HostPoolName $HostPoolName -Catalog $Catalog
    if (-not $rg) {
        Write-Warning "  Host pool not found in subscription - skipped"
        return
    }

    try {
        $sessionHosts = Get-AzWvdSessionHost `
            -ResourceGroupName $rg `
            -HostPoolName      $HostPoolName `
            -ErrorAction Stop
    }
    catch {
        Write-Warning "  Failed to list session hosts: $($_.Exception.Message)"
        return
    }

    foreach ($sh in $sessionHosts) {
        Invoke-SessionHostTagging -HostPoolName  $HostPoolName `
                                  -SessionHost   $sh `
                                  -VmLookup      $VmLookup `
                                  -AttributeSet  $AttributeSet `
                                  -AttributeName $AttributeName `
                                  -TagName       $TagName
    }
}

# ------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------

Connect-Services -SubscriptionId $SubscriptionId | Out-Null
Write-Output "Loading host pool catalog..."
$allHostPools = Get-AzWvdHostPool

Write-Output "Loading VM inventory..."
$vmLookup = @{}
foreach ($vm in Get-AzVM) {
    $vmLookup[$vm.Name] = $vm
}

$results = foreach ($hpName in $HostPools) {
    Invoke-HostPoolProcessing -HostPoolName  $hpName `
                              -Catalog       $allHostPools `
                              -VmLookup      $vmLookup `
                              -AttributeSet  $AttributeSet `
                              -AttributeName $AttributeName `
                              -TagName       $TagName
}

Write-Output "`n===== SUMMARY ====="
$results | Format-Table -AutoSize | Out-String | Write-Output

Disconnect-MgGraph | Out-Null
