Write-Host "SCRIPT STARTED"
$TenantId = "a986ce9f-e1ca-45ab-942e-e1ce27106918"
$ApplicationId = "88abefd9-4f32-450c-a5fc-27f69e780cfe"
$SubscriptionId = "31076e3c-fc5e-4f0b-be52-0eb744e89036"
$ClientSecret = "_1k8Q~je-Cy7FG9xd0cjJQ5mxWh4TDRmaNV6sdf3"

$secureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
$azCredential = New-Object PSCredential($ApplicationId, $secureSecret)

Connect-AzAccount -ServicePrincipal `
  -Tenant $TenantId `
  -Credential $azCredential | Out-Null

Connect-MgGraph -ClientSecretCredential $azCredential -TenantId $TenantId -NoWelcome

Set-AzContext -SubscriptionId $SubscriptionId | Out-Null

$OnlyIntune = $false 

$hostPools = @(
    @{ Name = "O19-UT-AVD-hp";             RG = "O19-UT-AVD-rg" },
    @{ Name = "O19-T-AVD-hp";              RG = "O19-T-AVD-rg" },
    @{ Name = "hostpool-OpenSky-Trusted";  RG = "IAF-RG" },
    @{ Name = "hostpool-OpenSky-Untrusted";RG = "IAF-RG" },
    @{ Name = "AVD-Test-Env-Hostpool";     RG = "AVD-Test-Env-RG" },
    @{ Name = "hostpool-9900-Dev";         RG = "AVD-9900-Dev-RG" },
    @{ Name = "hostpool-9900-DMZ";         RG = "AVD-9900-DMZ-RG" },
    @{ Name = "hostpool-9900-Plat";        RG = "AVD-9900-Platform-RG" },
    @{ Name = "hostpool-9900-Trust";       RG = "AVD-9900-Trust-RG" },
    @{ Name = "hostpool-9900-Untrst";      RG = "AVD-9900-Untrust-RG" },
    @{ Name = "hostpool-dev";              RG = "AVD-Dev-RG" },
    @{ Name = "hostpool-plat";             RG = "AVD-Platform-RG" },
    @{ Name = "MZP-DEV-AVD-hp";            RG = "MZP-DEV-AVD-rg" }
)


# =========================
# COLLECT DATA
# =========================

$all = @()

foreach ($hp in $hostPools) {

    Write-Host "Processing: $($hp.Name)" -ForegroundColor Cyan

    try {
        $sessionHosts = Get-AzWvdSessionHost `
            -ResourceGroupName $hp.RG `
            -HostPoolName $hp.Name
    }
    catch {
        Write-Warning "Failed: $($hp.Name)"
        continue
    }

    foreach ($sh in $sessionHosts) {

        $vmName = ($sh.Name -split "/")[-1]

        # קריטי: לקחת פרטים מלאים
        $devices = Get-MgDevice -Filter "displayName eq '$vmName'" `
            -Property Id,DisplayName,DeviceTrustType,TrustType,DeviceManagementType,MdmAppId

        # אם אין device בכלל
        if (-not $devices) {
            $all += [PSCustomObject]@{
                HostPool      = $hp.Name
                VM            = $vmName
                DeviceId      = ""
                IsEntraJoined = $false
                IsIntune      = $false
            }
            continue
        }

        foreach ($d in $devices) {

            # =========================
            # ENTRA JOIN (אמיתי בלבד)
            # =========================
            $isEntraJoined =
                ($d.DeviceTrustType -eq "AzureAd") -or
                ($d.TrustType -eq "AzureAd")

            # =========================
            # INTUNE (MDM)
            # =========================
            $isIntune =
                ($d.DeviceManagementType -eq "MDM") -or
                ($null -ne $d.MdmAppId)

            $all += [PSCustomObject]@{
                HostPool      = $hp.Name
                VM            = $vmName
                DeviceId      = $d.Id
                IsEntraJoined = $isEntraJoined
                IsIntune      = $isIntune
            }
        }
    }
}

# =========================
# DUPLICATES ONLY
# =========================

$duplicates = $all | Group-Object VM | Where-Object { $_.Count -gt 1 }

# =========================
# OPTIONAL FILTER
# =========================

if ($OnlyIntune) {
    $duplicates = $duplicates | ForEach-Object {
        $_.Group = $_.Group | Where-Object { $_.IsIntune -eq $true }
        $_
    } | Where-Object { $_.Group.Count -gt 1 }
}

# =========================
# OUTPUT
# =========================

Write-Host "`n===== DUPLICATE REPORT =====`n"

$i = 1

foreach ($group in $duplicates) {

    Write-Host "$i. VM: $($group.Name)" -ForegroundColor Red

    $j = 1

    foreach ($item in $group.Group) {

        # status logic
        $status =
            if (-not $item.IsEntraJoined) { "NOT ENTRA JOINED" }
            elseif ($item.IsIntune) { "ENTRA + INTUNE" }
            else { "ENTRA ONLY" }

        # colors
        $color =
            if ($status -eq "NOT ENTRA JOINED") { "Red" }
            elseif ($status -eq "ENTRA ONLY") { "Yellow" }
            else { "Green" }

        Write-Host "   $i.$j HostPool: $($item.HostPool)" -ForegroundColor $color
        Write-Host "       Entra Joined: $($item.IsEntraJoined)" -ForegroundColor $color
        Write-Host "       Intune: $($item.IsIntune)" -ForegroundColor $color
        Write-Host "       DeviceId: $($item.DeviceId)" -ForegroundColor $color

        $j++
    }

    Write-Host ""
    $i++
}

# =========================
# SUMMARY
# =========================

Write-Host "`n===== SUMMARY ====="

Write-Host "Total VM duplicates: $($duplicates.Count)"
Write-Host "Total records analyzed: $($all.Count)"
Write-Host "Only Intune mode: $OnlyIntune"

# =========================
# DUPLICATES ONLY (base filter)
# =========================
$duplicates = $all | Group-Object VM | Where-Object { $_.Count -gt 1 }

# flatten duplicates back to records
$dupRecords = $duplicates | ForEach-Object { $_.Group }

# =========================
# HEALTHY ONLY FROM DUPLICATES
# =========================
$healthyFromDuplicates = $dupRecords |
Where-Object {
    $_.IsEntraJoined -eq $true -and
    $_.IsIntune -eq $true -and
    -not [string]::IsNullOrWhiteSpace($_.DeviceId)
}

# unique devices (important!)
$healthyUnique = ($healthyFromDuplicates | Select-Object -ExpandProperty DeviceId -Unique).Count

Write-Host "`n===== HEALTHY (ONLY FROM DUPLICATES) ====="
Write-Host "Duplicate records total: $($dupRecords.Count)"
Write-Host "Healthy records inside duplicates: $($healthyFromDuplicates.Count)"
Write-Host "Unique healthy devices: $healthyUnique"