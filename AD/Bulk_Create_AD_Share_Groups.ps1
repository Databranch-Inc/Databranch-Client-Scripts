<#
Bulk_Create_AD_Share_Groups.ps1

Source Script found at https://www.reddit.com/r/PowerShell/comments/57db78/checking_if_group_exists_before_creating/

Gathers a list of groups from a .csv file, checks if they exist, and creates them in Active Directory.

Josh Britton
06/25/2025
1.0
========================================================================
1.0 - Initial Script Creation

========================================================================
#>

Function Create-ADShareGroups {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$GroupName,
        [Parameter(Mandatory = $true)]
        [string]$OrganizationalUnitDN,
        [Parameter(Mandatory = $true)]
        [string]$CompanyOU
    )

    #Variable Set

    $CurrentDomain = Get-ADDomain
    $TargetOU = "OU=Share Groups,OU=Security Groups,OU=$CompanyOU"
    $OrganizationalUnitDN = $TargetOU+","+$CurrentDomain

    $GroupNames = Import-Csv -Path C:\Databranch\ShareGroups.csv -Header GroupName

    # Loop through each group name in the CSV
    foreach ($Groupname in $GroupNames) {

        #Set Read Only Group Name
        $ROGroupName = "SHARE-"+$GroupName+"-RO"

        # Check if the Read Only group already exists
        $GroupExists = Get-ADGroup -Identity $ROGroupName -ErrorAction SilentlyContinue
        if ($GroupExists) {
            Write-Host "Group '$ROGroupName' already exists." -ForegroundColor Green
        } 
        else {
        # Create the group if it does not exist
            New-ADGroup -Name $ROGroupName -Path $OrganizationalUnitDN -GroupScope Global -GroupCategory Security -SamAccountName $ROGroupName
            Write-Host "Group '$ROGroupName' has been created." -ForegroundColor Green
        }

        #Set Read Write Group Name
        $RWGroupName = "SHARE-"+$GroupName+"-RW"

        # Check if the Read Only group already exists
        $GroupExists = Get-ADGroup -Identity $RWGroupName -ErrorAction SilentlyContinue
        if ($GroupExists) {
            Write-Host "Group '$RWGroupName' already exists." -ForegroundColor Green
        } 
        else {
        # Create the group if it does not exist
            New-ADGroup -Name $RWGroupName -Path $OrganizationalUnitDN -GroupScope Global -GroupCategory Security -SamAccountName $RWGroupName
            Write-Host "Group '$RWGroupName' has been created." -ForegroundColor Green
        }
    }
}