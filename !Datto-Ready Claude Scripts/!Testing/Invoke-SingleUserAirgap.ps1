<#
.SYNOPSIS
    Block all outbound internet traffic for a specific domain user account
    using a Windows Firewall rule scoped to that account's SID.

.DESCRIPTION
    Resolves the SID of the target domain account, creates a persistent
    outbound block rule in Windows Firewall with Advanced Security, and
    verifies the rule was created successfully. Run once as local admin.

.NOTES
    Version : 1.0.0.1
    Author  : (your name)
    Requires: Windows 10/11 Pro or Enterprise, run as local administrator
#>

# -----------------------------------------------------------------------
# CONFIGURE THESE TWO VALUES BEFORE RUNNING
# -----------------------------------------------------------------------
$DomainName   = "arc.local"          # Your NetBIOS domain name
$AccountName  = "training"         # The training account username
# -----------------------------------------------------------------------

$RuleName     = "Block Internet - Training Account"
$FullAccount  = "$DomainName\$AccountName"

Write-Host "`n[1/3] Resolving SID for '$FullAccount'..." -ForegroundColor Cyan

try {
    $NTAccount = New-Object System.Security.Principal.NTAccount($FullAccount)
    $SID = $NTAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
    Write-Host "      SID resolved: $SID" -ForegroundColor Green
}
catch {
    Write-Error "Could not resolve SID for '$FullAccount'. Verify the domain and account name are correct."
    exit 1
}

Write-Host "`n[2/3] Creating outbound block rule in Windows Firewall..." -ForegroundColor Cyan

# Remove any existing rule with the same name to avoid duplicates
$Existing = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
if ($Existing) {
    Write-Host "      Removing existing rule with same name..." -ForegroundColor Yellow
    Remove-NetFirewallRule -DisplayName $RuleName
}

try {
    New-NetFirewallRule `
        -DisplayName  $RuleName `
        -Description  "Blocks all outbound internet traffic for the $FullAccount training account." `
        -Direction    Outbound `
        -Action       Block `
        -Owner        $SID `
        -RemoteAddress Internet `
        -Enabled      True `
        -Profile      Any | Out-Null

    Write-Host "      Rule created successfully." -ForegroundColor Green
}
catch {
    Write-Error "Failed to create firewall rule: $_"
    exit 1
}

Write-Host "`n[3/3] Verifying rule..." -ForegroundColor Cyan

$Rule = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
if ($Rule -and $Rule.Enabled -eq "True") {
    Write-Host "      Rule verified: '$RuleName'" -ForegroundColor Green
    Write-Host "      Enabled : $($Rule.Enabled)"
    Write-Host "      Action  : $($Rule.Action)"
    Write-Host "      Profile : $($Rule.Profile)"
    Write-Host "`nDone. The '$FullAccount' account is now blocked from internet access." -ForegroundColor Green
}
else {
    Write-Warning "Rule was not found after creation. Please check Windows Firewall manually."
}