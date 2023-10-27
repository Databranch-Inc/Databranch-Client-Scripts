<#
Looping ACL Copy
This Script will ask for an Item to reference permissions for a group of end locations
Josh Britton
11/13/19
1.0
#>

#Set variable
$ACLSOURCE = Read-Host "What is the path to the origional ACL?"
$ACLDEST = Read-Host "Where is the parent folder that you are copying permissions? NOTE - ALL SUB OBJECTS IN THIS FOLDER WILL GET THE SOURCE PERMISSIONS"
$ACLOBJS = Get-ChildItem -Path $ACLDEST -Name

#Get Source ACL
$GETACL = Get-Acl -Path $ACLSOURCE

#Set ACL for each item in destination using source ACL as template
foreach ($ACLOBJ in $ACLOBJS){
    Set-Acl -Path $ACLDEST\$ACLOBJ -AclObject $GETACL
    Write-Host "Permissions to $ACLOBJ have been copied from $ACLSOURCE"
}