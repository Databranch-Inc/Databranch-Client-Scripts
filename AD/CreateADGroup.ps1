<#
CreateADGroup.ps1
Source Script found at https://www.reddit.com/r/PowerShell/comments/57db78/checking_if_group_exists_before_creating/

Josh Britton
11/5/2019
1.0
#>

#Variable Set

$CurrentDomain = Get-ADDomain
$TargetOU = "OU=Test Groups,OU=Groups,OU=BMW OU"
$OrganizationalUnitDN = $TargetOU+","+$CurrentDomain

$GroupName = "test12312312"

$GroupExists = Get-ADGroup -Identity $GroupName
if ($GroupExists)
{
Write-Host "Group $($GroupName) has already been created." -foregroundcolor Green
}
else
{
Write-Host "Group $GroupName does not exit" -ForegroundColor Red
#New-ADGroup -GroupCategory: "Security" -GroupScope: "Global" -Name "$groupname" -Path: "$OrganizationalUnitDN" -SamAccountName:"$groupname" -Server:"BMWM3AD01.BMWM3.com"
#Write-Host "Group $($GroupName) did not exsist it has now been been created." -foregroundcolor Green
}