<#
Looping ACL Copy
This Script will ask for an Item to reference permissions for a group of end locations
Josh Britton
11/13/19
1.0
#>

#Set variable
#$ACLSOURCE = Read-Host "What is the path to the origional ACL?"
$ACLDEST = Read-Host "Where is the parent folder that you are Setting permissions? NOTE - ALL SUB OBJECTS IN THIS FOLDER WILL GET THE SOURCE PERMISSIONS"
$ACLOBJS = Get-ChildItem -Path $ACLDEST -Name

#Get Source ACL
#$GETACL = Get-Acl -Path $ACLSOURCE

#Set ACL for each item in destination using source ACL as template
foreach ($ACLOBJ in $ACLOBJS){
    
    $NewAcl = Get-Acl -Path "$ACLDEST\$ACLOBJ"
    # Set properties1
    $identity = New-Object System.Security.Principal.NTAccount('potter\Domain Admins')
    $fileSystemRights = "FullControl"
    $type = "Allow"
    # Create new rule1
    $fileSystemAccessRuleArgumentList = $identity, $fileSystemRights, $type
    $fileSystemAccessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $fileSystemAccessRuleArgumentList
    # Apply new rule1
    $NewAcl.SetAccessRule($fileSystemAccessRule)
    Set-Acl -Path $ACLOBJ -AclObject $NewAcl
   
}