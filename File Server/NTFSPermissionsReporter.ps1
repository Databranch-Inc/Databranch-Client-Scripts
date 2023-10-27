<#
NTFS Permissions Reporter

This script is designed to review the permissions recursively of an NTFS Share. Currently, this is set to only look at directory itmes, not end files. DB standrd is to not set specifically end files

Variables needed
NTFS root folder

Josh Britton

9-6-23

1.0
#>

#Variable Set
$RootFolder = "D:\"

#AD Module Load
Import-Module ActiveDirectory

#Get ACL Info, save to CSV

$FolderPath = Get-ChildItem -Directory -Path $RootFolder -Recurse -Force -ErrorAction SilentlyContinue
$Output = @() 
ForEach ($Folder in $FolderPath) { 
    $Acl = Get-Acl -Path $Folder.FullName -ErrorAction SilentlyContinue
    ForEach ($Access in $Acl.Access) { 
$Properties = [ordered]@{'Folder Name'=$Folder.FullName;'Group/User'=$Access.IdentityReference;'Permissions'=$Access.FileSystemRights;'Inherited'=$Access.IsInherited} 
$Output += New-Object -TypeName PSObject -Property $Properties 
    } 
} 
$Output | Export-Csv -Path "C:\Databranch\NTFSPermissions Reporter.csv" -NoTypeInformation -Encoding UTF8 -Append

#Check CSV for unique Groups, save for AD Membership Check

$permissions = Import-Csv "C:\Databranch\NTFSPermissions Reporter.csv" | Select-Object "Group/User"
$AdGroups = $permissions."group/user" | Sort-Object | Get-Unique

#Get AD Group Membership
#Get Short Domain Name
$distinguisheddomain = Get-ADDomain | Select-Object -ExpandProperty DistinguishedName
$domain = (get-addomain -Identity $distinguisheddomain).netbiosname

#Trim list of $ADGroups to only have items that are AD Based.
foreach ($adgroup in $adgroups){

if ($adgroup.Contains("$domain")){

    #Trim Domain from from DOMAIN\GROUPNAME
   
    $TrimStep1 = ("$adgroup").Trim("$domain")
    $AdgroupTrimmed = ($TrimStep1).TrimStart("\")


    Write-Host "$AdgroupTrimmed is in the $Domain domain" -ForegroundColor Green
    <#
    Write-Host "Members of AD Group $AdgorupTrimmed" are:

    #Get Members of AD Group
    Get-ADGroupMember -Identity $AdgroupTrimmed | Select-Object -ExpandProperty Name
   #>

}
else{

    Write-Host "$adgroup is not a group in the $Domain domain. It is either a Domain user, or it is a Local Group/User" -ForegroundColor Yellow

}

}

#Create Report