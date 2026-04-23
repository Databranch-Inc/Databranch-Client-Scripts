<#
.SYNOPSIS
Rotates the local Windows ProtectedAccount password and syncs it to IT Glue.

.DESCRIPTION
This script is intended for Datto RMM. It always manages the local account named "ProtectedAccount".
It generates one password per device run, creates or updates the local account, ensures membership in
the local Administrators group, disables the built-in Administrator account, then queries IT Glue for
active configurations matching the device BIOS serial number.

For matched active configurations, it:
- uses the serial number only to build the IT Glue password entry name
- finds all password records with that same exact name and same username
- keeps the most recently updated password record
- updates that kept record
- deletes the other duplicate password records with that same name and username
- links the kept password to the current IT Glue config as an embedded password

.OPTIONAL VARIABLES
ITGluePasswordCategoryName
ITGlueDebugMode = true|false
#>

# TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = 'Stop'

# =========================
# Datto RMM Variables
# =========================
$APIKey               = $env:ITGlueAPIKey
$APIEndpoint          = $env:ITGlueURL
$OrgID                = $env:orgID
$PasswordCategoryName = $env:ITGluePasswordCategoryName
$DebugModeRaw         = $env:ITGlueDebugMode

# =========================
# Validation
# =========================
if ([string]::IsNullOrWhiteSpace($APIKey)) { throw "Missing ITGlueAPIKey" }
if ([string]::IsNullOrWhiteSpace($APIEndpoint)) { $APIEndpoint = "https://api.itglue.com" }
if ([string]::IsNullOrWhiteSpace($OrgID)) { throw "Missing orgID" }

if ([string]::IsNullOrWhiteSpace($PasswordCategoryName)) {
    $PasswordCategoryName = $null
}

$DebugMode = $false
if (-not [string]::IsNullOrWhiteSpace($DebugModeRaw)) {
    try { $DebugMode = [System.Convert]::ToBoolean($DebugModeRaw) } catch { $DebugMode = $false }
}

# =========================
# Hardcoded local admin account
# =========================
$Username = "ProtectedAccount"

# =========================
# Headers
# =========================
$Headers = @{
    "x-api-key"    = $APIKey
    "Content-Type" = "application/vnd.api+json"
    "Accept"       = "application/vnd.api+json"
}

# =========================
# Helper Functions
# =========================
function Invoke-ITGGet($Uri) {
    Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers
}

function Invoke-ITGPost($Uri, $Body) {
    Invoke-RestMethod -Method Post -Uri $Uri -Headers $Headers -Body ($Body | ConvertTo-Json -Depth 10)
}

function Invoke-ITGPatch($Uri, $Body) {
    Invoke-RestMethod -Method Patch -Uri $Uri -Headers $Headers -Body ($Body | ConvertTo-Json -Depth 10)
}

function Invoke-ITGDelete($Uri) {
    Invoke-RestMethod -Method Delete -Uri $Uri -Headers $Headers
}

function Write-DebugLog($Message) {
    if ($DebugMode) {
        Write-Host "[DEBUG] $Message"
    }
}

function Test-ITGArchived($Item) {
    if (-not $Item -or -not $Item.attributes) { return $false }

    $a = $Item.attributes

    if ($null -ne $a.archived) {
        try { return [bool]$a.archived } catch {}
    }

    if ($null -ne $a.'is-archived') {
        try { return [bool]$a.'is-archived' } catch {}
    }

    if ($null -ne $a.'archived-at' -and -not [string]::IsNullOrWhiteSpace([string]$a.'archived-at')) {
        return $true
    }

    return $false
}

function Get-ITGPasswordsByName($Name, $OrgID) {
    $enc = [System.Uri]::EscapeDataString($Name)
    $uri = "$APIEndpoint/passwords?filter[organization_id]=$OrgID&filter[name]=$enc&page[size]=1000"
    $res = Invoke-ITGGet $uri
    if ($res.data) { return @($res.data) }
    return @()
}

function Get-ExactPasswordMatches($Name, $OrgID, $ExpectedUsername) {
    $matches = Get-ITGPasswordsByName -Name $Name -OrgID $OrgID
    if (-not $matches) { return @() }

    return @(
        $matches | Where-Object {
            $_.attributes.name -and
            $_.attributes.username -and
            $_.attributes.name.Trim() -eq $Name.Trim() -and
            $_.attributes.username.Trim() -eq $ExpectedUsername.Trim()
        }
    )
}

function Get-ITGConfigurationsBySerial($SerialNumber, $OrgID) {
    if ([string]::IsNullOrWhiteSpace($SerialNumber)) { return @() }

    $enc = [System.Uri]::EscapeDataString($SerialNumber)
    $uri = "$APIEndpoint/configurations?filter[organization_id]=$OrgID&filter[serial_number]=$enc&page[size]=1000"
    $res = Invoke-ITGGet $uri
    if ($res.data) { return @($res.data) }
    return @()
}

function Get-ITGPasswordCategoryByName($CategoryName) {
    if ([string]::IsNullOrWhiteSpace($CategoryName)) { return $null }

    $enc = [System.Uri]::EscapeDataString($CategoryName)
    $uri = "$APIEndpoint/password_categories?filter[name]=$enc&page[size]=1000"
    $res = Invoke-ITGGet $uri

    if ($res.data) {
        return @($res.data | Where-Object { $_.attributes.name -eq $CategoryName })[0]
    }

    return $null
}

function Ensure-AdminGroup($User) {
    $member = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "\\$([regex]::Escape($User))$" -or $_.Name -eq $User }

    if (-not $member) {
        Add-LocalGroupMember -Group "Administrators" -Member $User
    }
}

function Resolve-LatestUpdatedPasswordRecord($Matches) {
    if (-not $Matches -or $Matches.Count -eq 0) { return $null }

    return @(
        $Matches | Sort-Object @{
            Expression = {
                try { [datetime]$_.attributes.'updated-at' } catch { [datetime]'1900-01-01' }
            }
            Descending = $true
        }
    )[0]
}

function Remove-DuplicatePasswordsByNameAndUsername($Matches, $KeepID, $ExpectedName, $ExpectedUsername) {
    if (-not $Matches -or $Matches.Count -eq 0) { return 0 }

    $DeletedCount = 0

    foreach ($Match in $Matches) {
        if ([string]$Match.id -eq [string]$KeepID) {
            Write-DebugLog "Keeping latest password ID $KeepID for name '$ExpectedName' and username '$ExpectedUsername'"
            continue
        }

        $a = $Match.attributes

        $SafeNameMatch = $a.name -and ($a.name.Trim() -eq $ExpectedName.Trim())
        $SafeUserMatch = $a.username -and ($a.username.Trim() -eq $ExpectedUsername.Trim())

        if ($SafeNameMatch -and $SafeUserMatch) {
            Write-Host "Deleting duplicate password record ID $($Match.id) with name '$($a.name)' and username '$($a.username)'"
            Invoke-ITGDelete "$APIEndpoint/passwords/$($Match.id)" | Out-Null
            $DeletedCount++
        }
    }

    return $DeletedCount
}

function Show-PasswordMatches($Title, $Matches) {
    if (-not $DebugMode) { return }

    Write-Host "[DEBUG] ===== $Title ====="

    if (-not $Matches -or $Matches.Count -eq 0) {
        Write-Host "[DEBUG] No matches found."
        return
    }

    foreach ($m in $Matches) {
        $a = $m.attributes
        $UpdatedAt = $null
        try { $UpdatedAt = $a.'updated-at' } catch {}

        Write-Host ("[DEBUG] ID={0} | Name={1} | Username={2} | ResourceType={3} | ResourceID={4} | UpdatedAt={5}" -f `
            $m.id,
            $a.name,
            $a.username,
            $a.'resource-type',
            $a.'resource-id',
            $UpdatedAt)
    }
}

# =========================
# Test API
# =========================
Invoke-ITGGet "$APIEndpoint/organizations?page[size]=1" | Out-Null

# =========================
# Generate one password for this device run
# =========================
Add-Type -AssemblyName System.Web
$Password = [System.Web.Security.Membership]::GeneratePassword(24,5)
$Secure   = $Password | ConvertTo-SecureString -AsPlainText -Force

# =========================
# Local Account Logic
# =========================
$User = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue

if (-not $User) {
    Write-Host "Creating local admin account: $Username"
    New-LocalUser -Name $Username -Password $Secure -PasswordNeverExpires
}
else {
    if ($User.Enabled -eq $false) {
        Write-Host "Enabling local admin account: $Username"
        Enable-LocalUser -Name $Username
    }

    Write-Host "Updating password for local admin account: $Username"
    Set-LocalUser -Name $Username -Password $Secure -PasswordNeverExpires $true
}

Ensure-AdminGroup $Username

$builtin = Get-LocalUser -Name "Administrator" -ErrorAction SilentlyContinue
if ($builtin) {
    Disable-LocalUser -Name "Administrator"
    Write-Host "Disabled built-in Administrator account."
}

# =========================
# Find active configs by serial
# =========================
$SerialNumber = $null
try {
    $SerialNumber = (Get-CimInstance Win32_BIOS).SerialNumber
}
catch {
    throw "Unable to read serial number from BIOS."
}

if ([string]::IsNullOrWhiteSpace($SerialNumber)) {
    throw "Serial number is blank."
}

Write-Host "Searching IT Glue configs for serial number: $SerialNumber"
$AllConfigMatches = Get-ITGConfigurationsBySerial -SerialNumber $SerialNumber -OrgID $OrgID

if (-not $AllConfigMatches -or $AllConfigMatches.Count -eq 0) {
    throw "No IT Glue configurations found with serial number $SerialNumber"
}

$ActiveConfigs = @($AllConfigMatches | Where-Object { -not (Test-ITGArchived $_) })

if (-not $ActiveConfigs -or $ActiveConfigs.Count -eq 0) {
    throw "No active IT Glue configurations found with serial number $SerialNumber"
}

Write-Host "Found $($AllConfigMatches.Count) total config(s) with this serial."
Write-Host "Using $($ActiveConfigs.Count) active config(s)."

# =========================
# Optional password category lookup
# =========================
$PasswordCategoryID = $null
if ($PasswordCategoryName) {
    try {
        $PasswordCategory = Get-ITGPasswordCategoryByName $PasswordCategoryName
        if ($PasswordCategory) {
            $PasswordCategoryID = [int]$PasswordCategory.id
            Write-Host "Matched password category '$PasswordCategoryName' with ID $PasswordCategoryID"
        }
        else {
            Write-Host "WARNING: '$PasswordCategoryName' was not found as a password category/type."
        }
    }
    catch {
        Write-Host "WARNING: Category lookup failed: $($_.Exception.Message)"
    }
}

# =========================
# Update one shared serial-based name
# Delete duplicates by same name + username
# =========================
$SuccessCount = 0
$DuplicateDeleteCount = 0

foreach ($Config in $ActiveConfigs) {
    $ConfigID = [int]$Config.id
    $ConfigName = [string]$Config.attributes.name

    if ([string]::IsNullOrWhiteSpace($ConfigName)) {
        $ConfigName = $env:COMPUTERNAME
    }

    $PasswordName = "$SerialNumber - Local Administrator Account"

    $Attributes = @{
        name            = $PasswordName
        username        = $Username
        password        = $Password
        notes           = "Local Admin Password for serial $SerialNumber"
        "resource-id"   = $ConfigID
        "resource-type" = "Configuration"
    }

    if ($PasswordCategoryID) {
        $Attributes["password-category-id"] = $PasswordCategoryID
    }

    $Body = @{
        data = @{
            type       = "passwords"
            attributes = $Attributes
        }
    }

    $Matches = Get-ExactPasswordMatches -Name $PasswordName -OrgID $OrgID -ExpectedUsername $Username
    Show-PasswordMatches -Title "Exact name + username matches before update for serial '$SerialNumber' and config '$ConfigName' (ID $ConfigID)" -Matches $Matches

    if ($Matches.Count -gt 0) {
        $Primary = Resolve-LatestUpdatedPasswordRecord -Matches $Matches
        $PasswordID = $Primary.id

        Write-Host "Updating latest existing password by serial name for $ConfigName (Config ID $ConfigID), Password ID $PasswordID"
        Invoke-ITGPatch "$APIEndpoint/passwords/$PasswordID" $Body | Out-Null

        if ($Matches.Count -gt 1) {
            $DeletedCount = Remove-DuplicatePasswordsByNameAndUsername `
                -Matches $Matches `
                -KeepID $PasswordID `
                -ExpectedName $PasswordName `
                -ExpectedUsername $Username

            $DuplicateDeleteCount += $DeletedCount
            Write-Host "Deleted $DeletedCount duplicate password record(s) for '$PasswordName' and username '$Username'"
        }
    }
    else {
        Write-Host "Creating password entry for active config: $ConfigName (ID $ConfigID)"
        $Result = Invoke-ITGPost "$APIEndpoint/organizations/$OrgID/relationships/passwords" $Body
        $PasswordID = $Result.data.id
    }

    $EmbedBody = @{
        data = @{
            type       = "passwords"
            attributes = @{
                "resource-id"   = $ConfigID
                "resource-type" = "Configuration"
            }
        }
    }

    if ($PasswordCategoryID) {
        $EmbedBody.data.attributes["password-category-id"] = $PasswordCategoryID
    }

    Invoke-ITGPatch "$APIEndpoint/passwords/$PasswordID" $EmbedBody | Out-Null
    Write-Host "Embedded password linked to active config: $ConfigName (ID $ConfigID)"

    $VerifyMatches = Get-ExactPasswordMatches -Name $PasswordName -OrgID $OrgID -ExpectedUsername $Username
    Show-PasswordMatches -Title "Verification exact name + username matches after update/delete for serial '$SerialNumber'" -Matches $VerifyMatches

    $SuccessCount++
}

Write-Host "SUCCESS: Rotated local admin password for $Username and processed $SuccessCount active config(s) for serial $SerialNumber. Deleted $DuplicateDeleteCount duplicate password record(s)."
exit 0