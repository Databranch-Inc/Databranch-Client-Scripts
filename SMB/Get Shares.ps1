<#Get-Shares
Josh Britton
1/4/19
1.0#>

Get-SmbShare | Select-Object -ExpandProperty Name | Out-File C:\Databranch\Shares.txt

$Shares = Get-Content C:\Databranch\Shares.txt

foreach ($Share in $Shares)
{
Write-Host "Permissons for $Share" | Out-File C:\Databranch\SharePerms.txt -Append
Get-SmbShareAccess -Name $Share | Out-File C:\Databranch\SharePerms.txt -Append
}