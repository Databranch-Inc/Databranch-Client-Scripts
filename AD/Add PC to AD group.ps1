<#
Add PC to AD group
This Script will add a PC to an AD group based on the properties listed 
Josh Britton
7/30/20
1.0#>

#Add AD Module 
Import-Module ActiveDirectory

#Variable Set
$SecurityGroup = 
$Credential = 
$Continue = "Y"

#Start a while loop here to allow for multiple re-tries or multiple PC entries.
do{
    $PCName = Read-Host "What is the name of the PC?"

    if (Get-ADComputer -Identity $PCName | Select-Object Name){
        Write-Host "$PCName found. Adding to $SecurityGroup" -ForegroundColor Green
        Add-ADGroupMember -Identity $SecurityGroup -Members $PCName -Credential $Credential
        Write-Host "$PCName added to $SecurityGroup." -ForegroundColor Green
    }
       
    else {
        Write-Host "$PCName not found. Please check the spelling of the Computer name and try again. If you continue to have issues, please contact Databrach at 716-373-4467." -ForegroundColor Yellow
    }
    $Continue = Read-Host "Do you want to add another Computer to the $SecurityGroup? (Y/N)"



} while ($Continue -eq "Y")