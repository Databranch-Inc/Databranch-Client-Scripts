<#
Databranch inventory report
This script will gather the current Servers, Desktops, and Users from Active Directory, and will give general infomration about them. Then, the data will be combined to create .CSV files for Databranch inventory.
Josh Britton
Current Version 1.5
Last Update - 9-5-23
Original Created Date - 9/23/19
=======================================================================================================
1.5 Update - Cleaning process for end file creation. Adding check and notes to review PC Last Logon Dates and disable/move disabled items to Disabled OU at root of Directory - JB 9-5-23
========================================================================================================
1.4 Update - adding logic to test for previous inventory files before attempting to delete. This should reduce false error messages. -JB 9/23/19

========================================================================================================
1.3.2 Update - Re-located if/else to test for C:\Databranch Folder to have it created before running AD Exports

========================================================================================================
1.3.1 Update - Added if/else to test for C:\Databranch Folder.
#>

#Import AD Module into shell
Import-Module ActiveDirectory


#Inital Variable Set
#Dates
$Date = Get-Date -Format "MM/dd/yyyy hh:mm:ss tt"
$90DaysAgo =(Get-Date).AddDays(-90)
$DisableDate = Get-Date -Date $90DaysAgo -Format "MM/dd/yyyy hh:mm:ss tt"
 

#Test for folder C:\Databranch
If (Test-Path C:\Databranch)
    {
    Write-Host "C:\Databranch exists" -ForegroundColor Green
    }
Else
    {
    New-Item -ItemType Directory -Path C:\ -Name Databranch
    }
     
#Clear old files from C:\Databranch to avoid duplicate entries
Write-Host "Performing cleanup on old Desktop info files" -ForegroundColor Green

#Create Array of files to check
$FileNames = @("FINAL","MODELADDED","MODELS","SERIAL")

foreach ($FileName in $FileNames)
{
if  (Test-Path "C:\Databranch\desktops$FileName.csv")
    { 
    Write-Host "C:\Databranch\desktops$FileName.csv exists. Removing file." -ForegroundColor Green
    Remove-Item -path "C:\Databranch\desktops$FileName.csv"
    }
    
Else
    {
    Write-Host "C:\Databranch\desktops$FileName.csv does not exist. Moving to next file." -ForegroundColor Green
    }
}


#Get AD information for desktops and laptops
Write-Host "Gathering AD Information" -ForegroundColor Green
GET-ADCOMPUTER -filter {OperatingSystem -NotLike "*server*"} -properties * |select-object name,OperatingSystem,lastlogondate,enabled,ipv4address,description,DistinguishedName| Export-csv C:\Databranch\desktopsAD.csv -notypeinformation -encoding utf8

#Get AD information for users
GET-ADUSER -filter * -properties * |select-object name,lastlogondate,enabled,description,DistinguishedName | Export-csv C:\Databranch\usersAD.csv -notypeinformation -encoding utf8

#Get AD information for servers
GET-ADCOMPUTER -filter {OperatingSystem -Like "Windows* *server*"} -properties * |select-object name,OperatingSystem,lastlogondate,enabled,ipv4address,description,DistinguishedName| Export-csv C:\Databranch\serverAD.csv -notypeinformation -encoding utf8

#AD Cleanups - Check for Disabled Items OU
if (Get-ADOrganizationalUnit -Filter 'Name -eq "Disabled Items"' ){

    Write-Host "Disabled Items OU found." -ForegroundColor Green
    
    }
    
    else{
    #Create Disabled Items OU
    New-ADOrganizationalUnit -Name "Disabled Items"
    }
    
#Move Disabled items to OU

#Upload Items to review for last login, and move legacy items to Disabled Items 
$DisabledOU = Get-ADOrganizationalUnit -Filter 'Name -eq "Disabled Items"' | Select-Object * -ExpandProperty DistinguishedName

#Desktop Check
$DesktopExpChecks = Search-ADAccount -ComputersOnly -AccountInactive -TimeSpan (New-TimeSpan -Days 90) | Where-Object -Property enabled -EQ True | Select-Object name,lastlogondate,enabled
    
foreach ($DesktopExpCheck in $DesktopExpChecks){
    $group = "Do not Disable"
    $Authorization = Get-ADGroupMember -Identity $group | Where-Object {$_.name -eq $DesktopExpCheck.Name}
    if ($Authorization){ 
        Write-Host ""$DesktopExpCheck.Name" is a member of the AD Group Do Not Disable. This object will not be disabled or moved in AD" -ForegroundColor Cyan
        
    }
    else{       
        Get-ADComputer -Identity $DesktopExpCheck.Name | Disable-ADAccount -PassThru 
        $DesktopDescription = Get-ADComputer -Identity $DesktopExpCheck.Name | Select-Object -ExpandProperty Description
        Move-ADObject  -Identity $DesktopExpCheck.Name -TargetPath $DisabledOU
        Set-ADComputer -Identity $DesktopExpCheck.Name -Description "$Desktopdescription | Disabled on $date by Databranch AD Inventory Script"
        Write-Host ""$DesktopExpCheck.Name" has been moved to Disabled Items" -ForegroundColor Yellow
    }
}            

#User Check
$UserExpChecks = Search-ADAccount -UsersOnly -AccountInactive -TimeSpan (New-TimeSpan -Days 90) | Where-Object -Property enabled -EQ True | Select-Object name,SamAccountName,ObjectGUID,lastlogondate,Description,enabled

foreach ($UserExpCheck in $UserExpChecks){
    $group = "Do not Disable"    
    $Authorization = Get-ADGroupMember -Identity $group | Where-Object {$_.name -eq $UserExpCheck.Name}
    if ($Authorization){ 
        Write-Host ""$UserExpCheck.Name" is a member of the AD Group Do Not Disable. This object will not be disabled or moved in AD" -ForegroundColor Cyan
        
    }
    else{       
        Get-ADUser -Identity $UserExpCheck.SamAccountName | Disable-ADAccount -PassThru
        $UserDescription =  Get-ADUser -Identity $UserExpCheck.SamAccountName -Properties Description | Select-Object -ExpandProperty Description
        Move-ADObject -Identity $UserExpCheck.ObjectGUID -TargetPath $DisabledOU
        Set-ADUser -Identity $UserExpCheck.SamAccountName -Description "$UserDescription | Disabled on $date by Databranch AD Inventory Script"
        Write-Host ""$UserExpCheck.SamAccountName" has been moved to Disabled Items" -ForegroundColor Yellow
    }
}    

#Move disabled users and computers from other OUs to Disabled Items OU
$DisabledObjectCleanups = Search-ADAccount -AccountDisabled | Where-Object {$_.DistinguishedName -NotLike "*OU=Disabled Items,DC=databranch,DC=com*"} | Select-Object SamAccountName,ObjectGUID,objectclass

foreach ($DisabledObjectCleanup in $DisabledObjectCleanups){
if ($DisabledObjectCleanup.objectclass -eq "user")
{
    $UserDescription =  Get-ADUser -Identity $DisabledObjectCleanup.SamAccountName -Properties Description | Select-Object -ExpandProperty Description
    Move-ADObject -Identity $DisabledObjectCleanup.ObjectGUID -TargetPath $DisabledOU
    Set-ADUser -Identity $DisabledObjectCleanup.SamAccountName -Description "$UserDescription | Moved to Disabled Items on $date by Databranch AD Inventory Script"
    Write-Host ""$DisabledObjectCleanup.SamAccountName" was already disabled but not in the Disabled Items OU. "$DisabledObjectCleanup.SamAccountName" has been moved to Disabled Items" -ForegroundColor Yellow
}
elseif($DisabledObjectCleanup.objectclass -eq "user")
{
 Write-Host ""$DisabledObjectCleanup.SamAccountName" is not a user object" -ForegroundColor Cyan
}
}

#Check Disabled Items OU for items to delete

#Desktop Check






#User Check
$DisabledUsers = Get-ADuser -Filter * -SearchBase $DisabledOU | Where-Object {$_.Enabled -eq $False} | Select-Object -ExpandProperty samaccountname

foreach ($DisabledUser in $DisabledUsers){
    $ObjectDisabledDateAttribute = Get-ADUser -Identity $DisabledUser -Properties whenChanged | select-object -ExpandProperty whenChanged
    $ObjectDisabledDateConverted = ($ObjectDisabledDateAttribute).tostring("MM/dd/yyyy hh:mm:ss tt")

    if($ObjectDisabledDateConverted -lt $DisableDate){

    }
    else{

    }


}










































#These commands generate files called desktopsAD.csv, usersAD.csv and serverAD.csv at the root of drive C. Updated 6/28/18 - Added aditional filter to the server pull to include the wildcard for the registerd symbol (®) in Windows® Small Business Server 2011 Standard - Josh Britton


#Upload Desktop names from AD to gather Model information
$Desktops = Import-Csv C:\Databranch\desktopsAD.csv | Select-Object -ExpandProperty name

#Gather CIM information about desktop Models
Write-Host "Gathering Desktop Model and Serial information" -ForegroundColor Green
foreach ($desktop in $Desktops)
    {Get-CimInstance -ClassName Win32_computersystem -ComputerName $Desktop -Property * -ErrorAction SilentlyContinue | Select-Object Name,UserName,Manufacturer,Model,SystemType | Export-csv C:\Databranch\desktopsMODELS.csv -notypeinformation -encoding utf8 -Append
     Get-wmiobject Win32_Bios -ComputerName $Desktop -Property * -ErrorAction SilentlyContinue | Select-Object __SERVER, SerialNumber | Export-csv C:\Databranch\desktopsSERIAL.csv -notypeinformation -encoding utf8 -Append
    }

#Add function to join and compare Desktop .CSV Files
function Join-Object
{
    <#
    .SYNOPSIS
        Join data from two sets of objects based on a common value

    .DESCRIPTION
        Join data from two sets of objects based on a common value

        For more details, see the accompanying blog post:
            http://ramblingcookiemonster.github.io/Join-Object/

        For even more details,  see the original code and discussions that this borrows from:
            Dave Wyatt's Join-Object - http://powershell.org/wp/forums/topic/merging-very-large-collections
            Lucio Silveira's Join-Object - http://blogs.msdn.com/b/powershell/archive/2012/07/13/join-object.aspx

    .PARAMETER Left
        'Left' collection of objects to join.  You can use the pipeline for Left.

        The objects in this collection should be consistent.
        We look at the properties on the first object for a baseline.
    
    .PARAMETER Right
        'Right' collection of objects to join.

        The objects in this collection should be consistent.
        We look at the properties on the first object for a baseline.

    .PARAMETER LeftJoinProperty
        Property on Left collection objects that we match up with RightJoinProperty on the Right collection

    .PARAMETER RightJoinProperty
        Property on Right collection objects that we match up with LeftJoinProperty on the Left collection

    .PARAMETER LeftProperties
        One or more properties to keep from Left.  Default is to keep all Left properties (*).

        Each property can:
            - Be a plain property name like "Name"
            - Contain wildcards like "*"
            - Be a hashtable like @{Name="Product Name";Expression={$_.Name}}.
                 Name is the output property name
                 Expression is the property value ($_ as the current object)
                
                 Alternatively, use the Suffix or Prefix parameter to avoid collisions
                 Each property using this hashtable syntax will be excluded from suffixes and prefixes

    .PARAMETER RightProperties
        One or more properties to keep from Right.  Default is to keep all Right properties (*).

        Each property can:
            - Be a plain property name like "Name"
            - Contain wildcards like "*"
            - Be a hashtable like @{Name="Product Name";Expression={$_.Name}}.
                 Name is the output property name
                 Expression is the property value ($_ as the current object)
                
                 Alternatively, use the Suffix or Prefix parameter to avoid collisions
                 Each property using this hashtable syntax will be excluded from suffixes and prefixes

    .PARAMETER Prefix
        If specified, prepend Right object property names with this prefix to avoid collisions

        Example:
            Property Name                   = 'Name'
            Suffix                          = 'j_'
            Resulting Joined Property Name  = 'j_Name'

    .PARAMETER Suffix
        If specified, append Right object property names with this suffix to avoid collisions

        Example:
            Property Name                   = 'Name'
            Suffix                          = '_j'
            Resulting Joined Property Name  = 'Name_j'

    .PARAMETER Type
        Type of join.  Default is AllInLeft.

        AllInLeft will have all elements from Left at least once in the output, and might appear more than once
          if the where clause is true for more than one element in right, Left elements with matches in Right are
          preceded by elements with no matches.
          SQL equivalent: outer left join (or simply left join)

        AllInRight is similar to AllInLeft.
        
        OnlyIfInBoth will cause all elements from Left to be placed in the output, only if there is at least one
          match in Right.
          SQL equivalent: inner join (or simply join)
         
        AllInBoth will have all entries in right and left in the output. Specifically, it will have all entries
          in right with at least one match in left, followed by all entries in Right with no matches in left, 
          followed by all entries in Left with no matches in Right.
          SQL equivalent: full join

    .EXAMPLE
        #
        #Define some input data.

        $l = 1..5 | Foreach-Object {
            [pscustomobject]@{
                Name = "jsmith$_"
                Birthday = (Get-Date).adddays(-1)
            }
        }

        $r = 4..7 | Foreach-Object{
            [pscustomobject]@{
                Department = "Department $_"
                Name = "Department $_"
                Manager = "jsmith$_"
            }
        }

        #We have a name and Birthday for each manager, how do we find their department, using an inner join?
        Join-Object -Left $l -Right $r -LeftJoinProperty Name -RightJoinProperty Manager -Type OnlyIfInBoth -RightProperties Department


            # Name    Birthday             Department  
            # ----    --------             ----------  
            # jsmith4 4/14/2015 3:27:22 PM Department 4
            # jsmith5 4/14/2015 3:27:22 PM Department 5

    .EXAMPLE  
        #
        #Define some input data.

        $l = 1..5 | Foreach-Object {
            [pscustomobject]@{
                Name = "jsmith$_"
                Birthday = (Get-Date).adddays(-1)
            }
        }

        $r = 4..7 | Foreach-Object{
            [pscustomobject]@{
                Department = "Department $_"
                Name = "Department $_"
                Manager = "jsmith$_"
            }
        }

        #We have a name and Birthday for each manager, how do we find all related department data, even if there are conflicting properties?
        $l | Join-Object -Right $r -LeftJoinProperty Name -RightJoinProperty Manager -Type AllInLeft -Prefix j_

            # Name    Birthday             j_Department j_Name       j_Manager
            # ----    --------             ------------ ------       ---------
            # jsmith1 4/14/2015 3:27:22 PM                                    
            # jsmith2 4/14/2015 3:27:22 PM                                    
            # jsmith3 4/14/2015 3:27:22 PM                                    
            # jsmith4 4/14/2015 3:27:22 PM Department 4 Department 4 jsmith4  
            # jsmith5 4/14/2015 3:27:22 PM Department 5 Department 5 jsmith5  

    .EXAMPLE
        #
        #Hey!  You know how to script right?  Can you merge these two CSVs, where Path1's IP is equal to Path2's IP_ADDRESS?
        
        #Get CSV data
        $s1 = Import-CSV $Path1
        $s2 = Import-CSV $Path2

        #Merge the data, using a full outer join to avoid omitting anything, and export it
        Join-Object -Left $s1 -Right $s2 -LeftJoinProperty IP_ADDRESS -RightJoinProperty IP -Prefix 'j_' -Type AllInBoth |
            Export-CSV $MergePath -NoTypeInformation

    .EXAMPLE
        #
        # "Hey Warren, we need to match up SSNs to Active Directory users, and check if they are enabled or not.
        #  I'll e-mail you an unencrypted CSV with all the SSNs from gmail, what could go wrong?"
        
        # Import some SSNs. 
        $SSNs = Import-CSV -Path D:\SSNs.csv

        #Get AD users, and match up by a common value, samaccountname in this case:
        Get-ADUser -Filter "samaccountname -like 'wframe*'" |
            Join-Object -LeftJoinProperty samaccountname -Right $SSNs `
                        -RightJoinProperty samaccountname -RightProperties ssn `
                        -LeftProperties samaccountname, enabled, objectclass

    .NOTES
        This borrows from:
            Dave Wyatt's Join-Object - http://powershell.org/wp/forums/topic/merging-very-large-collections/
            Lucio Silveira's Join-Object - http://blogs.msdn.com/b/powershell/archive/2012/07/13/join-object.aspx

        Changes:
            Always display full set of properties
            Display properties in order (left first, right second)
            If specified, add suffix or prefix to right object property names to avoid collisions
            Use a hashtable rather than ordereddictionary (avoid case sensitivity)

    .LINK
        http://ramblingcookiemonster.github.io/Join-Object/

    .FUNCTIONALITY
        PowerShell Language

    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,
                   ValueFromPipeLine = $true)]
        [object[]] $Left,

        # List to join with $Left
        [Parameter(Mandatory=$true)]
        [object[]] $Right,

        [Parameter(Mandatory = $true)]
        [string] $LeftJoinProperty,

        [Parameter(Mandatory = $true)]
        [string] $RightJoinProperty,

        [object[]]$LeftProperties = '*',

        # Properties from $Right we want in the output.
        # Like LeftProperties, each can be a plain name, wildcard or hashtable. See the LeftProperties comments.
        [object[]]$RightProperties = '*',

        [validateset( 'AllInLeft', 'OnlyIfInBoth', 'AllInBoth', 'AllInRight')]
        [Parameter(Mandatory=$false)]
        [string]$Type = 'AllInLeft',

        [string]$Prefix,
        [string]$Suffix
    )
    Begin
    {
        function AddItemProperties($item, $properties, $hash)
        {
            if ($null -eq $item)
            {
                return
            }

            foreach($property in $properties)
            {
                $propertyHash = $property -as [hashtable]
                if($null -ne $propertyHash)
                {
                    $hashName = $propertyHash["name"] -as [string]         
                    $expression = $propertyHash["expression"] -as [scriptblock]

                    $expressionValue = $expression.Invoke($item)[0]
            
                    $hash[$hashName] = $expressionValue
                }
                else
                {
                    foreach($itemProperty in $item.psobject.Properties)
                    {
                        if ($itemProperty.Name -like $property)
                        {
                            $hash[$itemProperty.Name] = $itemProperty.Value
                        }
                    }
                }
            }
        }

        function TranslateProperties
        {
            [cmdletbinding()]
            param(
                [object[]]$Properties,
                [psobject]$RealObject,
                [string]$Side)

            foreach($Prop in $Properties)
            {
                $propertyHash = $Prop -as [hashtable]
                if($null -ne $propertyHash)
                {
                    $hashName = $propertyHash["name"] -as [string]         
                    $expression = $propertyHash["expression"] -as [scriptblock]

                    $ScriptString = $expression.tostring()
                    if($ScriptString -notmatch 'param\(')
                    {
                        Write-Verbose "Property '$HashName'`: Adding param(`$_) to scriptblock '$ScriptString'"
                        $Expression = [ScriptBlock]::Create("param(`$_)`n $ScriptString")
                    }
                
                    $Output = @{Name =$HashName; Expression = $Expression }
                    Write-Verbose "Found $Side property hash with name $($Output.Name), expression:`n$($Output.Expression | out-string)"
                    $Output
                }
                else
                {
                    foreach($ThisProp in $RealObject.psobject.Properties)
                    {
                        if ($ThisProp.Name -like $Prop)
                        {
                            Write-Verbose "Found $Side property '$($ThisProp.Name)'"
                            $ThisProp.Name
                        }
                    }
                }
            }
        }

        function WriteJoinObjectOutput($leftItem, $rightItem, $leftProperties, $rightProperties)
        {
            $properties = @{}

            AddItemProperties $leftItem $leftProperties $properties
            AddItemProperties $rightItem $rightProperties $properties

            New-Object psobject -Property $properties
        }

        #Translate variations on calculated properties.  Doing this once shouldn't affect perf too much.
        foreach($Prop in @($LeftProperties + $RightProperties))
        {
            if($Prop -as [hashtable])
            {
                foreach($variation in ('n','label','l'))
                {
                    if(-not $Prop.ContainsKey('Name') )
                    {
                        if($Prop.ContainsKey($variation) )
                        {
                            $Prop.Add('Name',$Prop[$Variation])
                        }
                    }
                }
                if(-not $Prop.ContainsKey('Name') -or $Prop['Name'] -like $null )
                {
                    Throw "Property is missing a name`n. This should be in calculated property format, with a Name and an Expression:`n@{Name='Something';Expression={`$_.Something}}`nAffected property:`n$($Prop | out-string)"
                }


                if(-not $Prop.ContainsKey('Expression') )
                {
                    if($Prop.ContainsKey('E') )
                    {
                        $Prop.Add('Expression',$Prop['E'])
                    }
                }
            
                if(-not $Prop.ContainsKey('Expression') -or $Prop['Expression'] -like $null )
                {
                    Throw "Property is missing an expression`n. This should be in calculated property format, with a Name and an Expression:`n@{Name='Something';Expression={`$_.Something}}`nAffected property:`n$($Prop | out-string)"
                }
            }        
        }

        $leftHash = @{}
        $rightHash = @{}

        # Hashtable keys can't be null; we'll use any old object reference as a placeholder if needed.
        $nullKey = New-Object psobject
        
        $bound = $PSBoundParameters.keys -contains "InputObject"
        if(-not $bound)
        {
            [System.Collections.ArrayList]$LeftData = @()
        }
    }
    Process
    {
        #We pull all the data for comparison later, no streaming
        if($bound)
        {
            $LeftData = $Left
        }
        Else
        {
            foreach($Object in $Left)
            {
                [void]$LeftData.add($Object)
            }
        }
    }
    End
    {
        foreach ($item in $Right)
        {
            $key = $item.$RightJoinProperty

            if ($null -eq $key)
            {
                $key = $nullKey
            }

            $bucket = $rightHash[$key]

            if ($null -eq $bucket)
            {
                $bucket = New-Object System.Collections.ArrayList
                $rightHash.Add($key, $bucket)
            }

            $null = $bucket.Add($item)
        }

        foreach ($item in $LeftData)
        {
            $key = $item.$LeftJoinProperty

            if ($null -eq $key)
            {
                $key = $nullKey
            }

            $bucket = $leftHash[$key]

            if ($null -eq $bucket)
            {
                $bucket = New-Object System.Collections.ArrayList
                $leftHash.Add($key, $bucket)
            }

            $null = $bucket.Add($item)
        }

        $LeftProperties = TranslateProperties -Properties $LeftProperties -Side 'Left' -RealObject $LeftData[0]
        $RightProperties = TranslateProperties -Properties $RightProperties -Side 'Right' -RealObject $Right[0]

        #I prefer ordered output. Left properties first.
        [string[]]$AllProps = $LeftProperties

        #Handle prefixes, suffixes, and building AllProps with Name only
        $RightProperties = foreach($RightProp in $RightProperties)
        {
            if(-not ($RightProp -as [Hashtable]))
            {
                Write-Verbose "Transforming property $RightProp to $Prefix$RightProp$Suffix"
                @{
                    Name="$Prefix$RightProp$Suffix"
                    Expression=[scriptblock]::create("param(`$_) `$_.'$RightProp'")
                }
                $AllProps += "$Prefix$RightProp$Suffix"
            }
            else
            {
                Write-Verbose "Skipping transformation of calculated property with name $($RightProp.Name), expression:`n$($RightProp.Expression | out-string)"
                $AllProps += [string]$RightProp["Name"]
                $RightProp
            }
        }

        $AllProps = $AllProps | Select -Unique

        Write-Verbose "Combined set of properties: $($AllProps -join ', ')"

        foreach ( $entry in $leftHash.GetEnumerator() )
        {
            $key = $entry.Key
            $leftBucket = $entry.Value

            $rightBucket = $rightHash[$key]

            if ($null -eq $rightBucket)
            {
                if ($Type -eq 'AllInLeft' -or $Type -eq 'AllInBoth')
                {
                    foreach ($leftItem in $leftBucket)
                    {
                        WriteJoinObjectOutput $leftItem $null $LeftProperties $RightProperties | Select $AllProps
                    }
                }
            }
            else
            {
                foreach ($leftItem in $leftBucket)
                {
                    foreach ($rightItem in $rightBucket)
                    {
                        WriteJoinObjectOutput $leftItem $rightItem $LeftProperties $RightProperties | Select $AllProps
                    }
                }
            }
        }

        if ($Type -eq 'AllInRight' -or $Type -eq 'AllInBoth')
        {
            foreach ($entry in $rightHash.GetEnumerator())
            {
                $key = $entry.Key
                $rightBucket = $entry.Value

                $leftBucket = $leftHash[$key]

                if ($null -eq $leftBucket)
                {
                    foreach ($rightItem in $rightBucket)
                    {
                        WriteJoinObjectOutput $null $rightItem $LeftProperties $RightProperties | Select $AllProps
                    }
                }
            }
        }
    }
}

#Set .CSV file Variables
Write-Host "Creating new Desktop CSV File" -ForegroundColor Green

$CSV1 = Import-CSV C:\Databranch\desktopsAD.csv
$CSV2 = Import-CSV C:\Databranch\desktopsMODELS.csv

#Merge .CSV files
#Join-Object -Left $CSV1 -LeftJoinProperty Name -Right $CSV2 -RightJoinProperty Name -Type OnlyIfInBoth -ErrorAction SilentlyContinue  | Export-Csv C:\Databranch\desktopsFINAL.csv -notypeinformation -encoding utf8

Join-Object -Left $CSV1 -LeftJoinProperty Name -Right $CSV2 -RightJoinProperty Name -Type AllInBoth -ErrorAction SilentlyContinue  | Export-Csv C:\Databranch\desktopsMODELADDED.csv -notypeinformation -Append -encoding utf8

$CSV3 = Import-CSV C:\Databranch\desktopsMODELADDED.csv
$CSV4 = Import-CSV C:\Databranch\desktopsSERIAL.csv

Join-Object -Left $CSV3 -LeftJoinProperty Name -Right $CSV4 -RightJoinProperty __SERVER -Type AllInBoth -ErrorAction SilentlyContinue  | Export-Csv C:\Databranch\desktopsFINAL.csv -notypeinformation -Append -encoding utf8


<#
$CSV5 = Import-CSV C:\Databranch\desktopsFINAL.csv
$CSV6 = Import-CSV C:\Databranch\server.csv

Join-Object -Left $CSV3 -LeftJoinProperty Name -Right $CSV4 -RightJoinProperty __SERVER -Type AllInBoth -ErrorAction SilentlyContinue  | Export-Csv C:\Databranch\desktopsFINAL.csv -notypeinformation -Append -encoding utf8
#>

