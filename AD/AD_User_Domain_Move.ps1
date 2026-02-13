<#
This script is designed to pull all users from a specific Organizational Unit (OU) in Active Directory and migrate them to another domain and OU. This script assumes that you have the necessary permissions to read from the source domain and write to the target domain.

Josh Britton
#>

function Move-ADUsersinOU {

<#
    .SYNOPSIS
        Gathers all users from a specified OU in a source domain and moves them to a target OU in a new target domain.
    .DESCRIPTION
        This function connects to the source Active Directory domain, retrieves all users from the specified OU, and moves them to the target OU in a target Active Directory domain. This is intended to be called from a Source Domain holding the user accounts to be moved. Run as an enterprise admin or an account with sufficient privileges in both domains.
    .PARAMETER SourceDC
        The source Domain Controller. Must be FQDN.
    .PARAMETER SourceOUUsers
        The source OU where the users are located. Must be in distinguished name format.
    .PARAMETER TargetOU
        The target OU where the users will be moved. Must be in distinguished name format.
    .PARAMETER TargetDC
        The target Domain Controller. Must be FQDN.

    .OUTPUTS
        
    .NOTES
        
    .EXAMPLE
        
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$sourceDC,

        [Parameter(Mandatory = $true)]
        [string]$SourceOUUsers,

        [Parameter(Mandatory = $true)]
        [string]$TargetOU,

        [Parameter(Mandatory = $true)]
        [string]$TargetDC
    )


#Test for Active Directory module, import if not loaded
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {

    Write-Host "The Active Directory module for Windows PowerShell is not installed. Attempting to install."
    Install-WindowsFeature -Name "RSAT-AD-PowerShell" -IncludeAllSubFeature -IncludeManagementTools
    }
    else {
      Import-Module ActiveDirectory
    } 

#Get all users from the specified OU in the source domain

$users = Get-ADUser -Filter * -SearchBase $SourceOUUsers -Server $sourceDC
foreach ($u in $users) {
    #move user to target OU in target domain
    Move-ADObject -Identity $u.DistinguishedName -TargetPath $TargetOU -TargetServer $TargetDC
}

}