<#
.SYNOPSIS
    For every host pool in the list, iterates its session hosts, reads the
    AssignedUser's Entra custom security attribute UserData.CompanyName, and
    applies that value as an Azure resource tag "CompanyName" on the session
    host VM.

.REQUIREMENTS
    App Registration (service principal) needs:
      * Microsoft Graph application permissions (admin consent):
          - CustomSecAttributeAssignment.Read.All
          - User.Read.All
      * Entra role assignment:
          - Attribute Assignment Reader (on the "UserData" attribute set)
      * Azure RBAC on the AVD resource groups / VMs:
          - Reader on the host pools
          - Tag Contributor (or Contributor) on the session host VMs
#>

# ------------------------------------------------------------------
# CONFIG
# ------------------------------------------------------------------
$TenantId       = "78820852-55fa-450b-908d-45c0d911e76b"
$ApplicationId  = "03acb776-8e3c-476a-96db-6817eadc126d"
$SubscriptionId = "69d34344-d7b7-4dc2-aefa-fda3c77fb570"
$ClientSecret   = "ys58Q~pPgeXrJOKo6gYaeWAXg27qZ2uc3s-xGbMg"

$AttributeSet  = "UserData"
$AttributeName = "CompanyName"
$TagName       = "CompanyName"

# Host pool names only - RG is resolved automatically via Get-AzWvdHostPool
$hostPools = @(
    "PAVD-ANM-hp",
    "PAVD-DevAZP-hp",
    "PAVD-DevIAF-hp",
    "PAVD-DevMRM-hp",
    "PAVD-DevMRP-hp",
    "PAVD-DevSHR-hp",
    "PAVD-DevYSD-hp",
    "PAVD-DevZRY-hp",
    "PAVD-DT-hp",
    "PAVD-MRM-hp",
    "PAVD-ProdAZP-hp",
    "PAVD-ProdIAF-hp",
    "PAVD-ProdMRP-hp",
    "PAVD-ProdSHR-hp",
    "PAVD-ProdZRY-hp",
    "PAVD-SHR-hp",
    "PAVD-DevDTS-hp",
    "PAVD-ProdDSI-hp"
)

# ------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------

<#
.SYNOPSIS
    Authenticates to Azure and Microsoft Graph using an App Registration
    (client credentials flow).
.DESCRIPTION
    Builds a PSCredential from the ApplicationId and ClientSecret, signs in
    to Azure as the service principal, sets the target subscription context,
    and connects Microsoft Graph with the same credential.
#>
function Connect-Services {
    param(
        [Parameter(Mandatory)] [string] $TenantId,
        [Parameter(Mandatory)] [string] $ApplicationId,
        [Parameter(Mandatory)] [string] $SubscriptionId,
        [Parameter(Mandatory)] [string] $ClientSecret
    )

    $cred = New-Object System.Management.Automation.PSCredential(
        $ApplicationId,
        (ConvertTo-SecureString $ClientSecret -AsPlainText -Force)
    )

    Connect-AzAccount -ServicePrincipal -Tenant $TenantId -Credential $cred | Out-Null
    Set-AzContext     -SubscriptionId $SubscriptionId | Out-Null
    Connect-MgGraph   -TenantId $TenantId -ClientSecretCredential $cred -NoWelcome
}

<#
.SYNOPSIS
    Resolves the resource group name of a host pool by looking it up in a
    pre-loaded host pool catalog.
.DESCRIPTION
    Searches the supplied catalog (output of Get-AzWvdHostPool) for a host
    pool matching HostPoolName and extracts the resource group segment from
    its Azure resource Id. Returns $null when the host pool is not found.
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
.DESCRIPTION
    Session host names come in the form '<hostpool>/<fqdn>'. This function
    strips the host pool prefix and the DNS suffix, returning only the
    short computer / VM name.
#>
function Get-SessionHostVmName {
    param([Parameter(Mandatory)] [object] $SessionHost)

    $short = ($SessionHost.Name -split "/")[-1]
    return  ($short             -split "\.")[0]
}

<#
.SYNOPSIS
    Reads the UserData.CompanyName custom security attribute of an Entra user.
.DESCRIPTION
    Calls Microsoft Graph to fetch the user's customSecurityAttributes bag,
    navigates to the configured attribute set and attribute name, and returns
    its string value. Returns $null if the attribute set or attribute is not
    assigned to the user.
#>
function Get-UserCompanyName {
    param([Parameter(Mandatory)] [string] $UserPrincipalNameOrId)

    $u = Get-MgUser -UserId $UserPrincipalNameOrId `
                    -Property "id,userPrincipalName,customSecurityAttributes" `
                    -ErrorAction Stop

    $csa = $u.CustomSecurityAttributes
    if (-not $csa -or -not $csa.AdditionalProperties) { return $null }
    if (-not $csa.AdditionalProperties.ContainsKey($AttributeSet)) { return $null }

    $set = $csa.AdditionalProperties[$AttributeSet]
    if ($set -is [System.Collections.IDictionary] -and $set.ContainsKey($AttributeName)) {
        return $set[$AttributeName]
    }
    return $null
}

<#
.SYNOPSIS
    Merges the CompanyName tag onto an Azure VM without overwriting other tags.
.DESCRIPTION
    Uses Update-AzTag with -Operation Merge so existing tags on the VM are
    preserved. Only the CompanyName tag is added or updated to the supplied
    value.
#>
function Set-VmCompanyNameTag {
    param(
        [Parameter(Mandatory)] [string] $VmResourceId,
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
.DESCRIPTION
    Returns a PSCustomObject with a fixed schema (HostPool, SessionHost,
    AssignedUser, CompanyName, Status) so all callers emit consistent rows
    that render cleanly in Format-Table.
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
    Processes a single session host: reads the assigned user's CompanyName
    attribute and tags the underlying VM with it.
.DESCRIPTION
    Skips session hosts with no assigned user or whose user has no
    UserData.CompanyName attribute. If a value is found and the VM exists,
    the tag is merged onto the VM. Always returns a result row describing
    the outcome (Tagged / Skipped / Failed).
#>
function Invoke-SessionHostTagging {
    param(
        [Parameter(Mandatory)] [string] $HostPoolName,
        [Parameter(Mandatory)] [object] $SessionHost
    )

    $vmName = Get-SessionHostVmName -SessionHost $SessionHost
    $user   = $SessionHost.AssignedUser

    if ([string]::IsNullOrWhiteSpace($user)) {
        Write-Host "  $vmName : no AssignedUser - skipped" -ForegroundColor DarkGray
        return New-Result -HostPool $HostPoolName -SessionHost $vmName `
                          -Status   "Skipped (no assigned user)"
    }

    try {
        $companyName = Get-UserCompanyName -UserPrincipalNameOrId $user
    }
    catch {
        Write-Warning "  $vmName : failed to read user '$user' - $($_.Exception.Message)"
        return New-Result -HostPool $HostPoolName -SessionHost $vmName `
                          -AssignedUser $user -Status "Failed (read user)"
    }

    if ([string]::IsNullOrWhiteSpace($companyName)) {
        Write-Host "  $vmName : user '$user' has no $AttributeSet.$AttributeName - skipped" -ForegroundColor Yellow
        return New-Result -HostPool $HostPoolName -SessionHost $vmName `
                          -AssignedUser $user -Status "Skipped (attribute empty)"
    }

    $vm = Get-AzVM -Name $vmName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $vm) {
        Write-Warning "  $vmName : VM not found in subscription"
        return New-Result -HostPool $HostPoolName -SessionHost $vmName `
                          -AssignedUser $user -CompanyName $companyName `
                          -Status "Failed (VM not found)"
    }

    try {
        Set-VmCompanyNameTag -VmResourceId $vm.Id -Value $companyName
        Write-Host "  $vmName : $user -> tag $TagName='$companyName'" -ForegroundColor Green
        $status = "Tagged"
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
.DESCRIPTION
    Resolves the host pool's resource group from the catalog, lists its
    session hosts via Get-AzWvdSessionHost, and delegates each session host
    to Invoke-SessionHostTagging. Emits the per-session-host result rows to
    the pipeline. Returns nothing (and logs a warning) if the host pool is
    missing or the listing fails.
#>
function Invoke-HostPoolProcessing {
    param(
        [Parameter(Mandatory)] [string]   $HostPoolName,
        [Parameter(Mandatory)] [object[]] $Catalog
    )

    Write-Host "`nHost Pool: $HostPoolName" -ForegroundColor Cyan

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
        Invoke-SessionHostTagging -HostPoolName $HostPoolName -SessionHost $sh
    }
}

# ------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------

Connect-Services -TenantId $TenantId `
                 -ApplicationId $ApplicationId `
                 -SubscriptionId $SubscriptionId `
                 -ClientSecret $ClientSecret

Write-Host "Loading host pool catalog..." -ForegroundColor DarkGray
$allHostPools = Get-AzWvdHostPool

$results = foreach ($hpName in $hostPools) {
    Invoke-HostPoolProcessing -HostPoolName $hpName -Catalog $allHostPools
}

Write-Host "`n===== SUMMARY =====" -ForegroundColor Cyan
$results | Format-Table -AutoSize

Disconnect-MgGraph | Out-Null
