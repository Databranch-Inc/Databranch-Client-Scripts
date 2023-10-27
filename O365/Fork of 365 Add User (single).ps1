<# This form was created using POSHGUI.com  a free online gui designer for PowerShell
.NAME
    Fork of 365 Add User (single)
#>

Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

$365CC                           = New-Object system.Windows.Forms.Form
$365CC.ClientSize                = '600,650'
$365CC.text                      = "365 Control Center"
$365CC.BackColor                 = "#9b9b9b"
$365CC.TopMost                   = $false

$Groupbox1                       = New-Object system.Windows.Forms.Groupbox
$Groupbox1.height                = 300
$Groupbox1.width                 = 300
$Groupbox1.BackColor             = "#4a4a4a"
$Groupbox1.location              = New-Object System.Drawing.Point(0,50)

$inputFirstName                  = New-Object system.Windows.Forms.TextBox
$inputFirstName.multiline        = $false
$inputFirstName.width            = 100
$inputFirstName.height           = 20
$inputFirstName.location         = New-Object System.Drawing.Point(23,66)
$inputFirstName.Font             = 'Microsoft Sans Serif,10'

$firstNameLabel                  = New-Object system.Windows.Forms.Label
$firstNameLabel.text             = "First:"
$firstNameLabel.AutoSize         = $true
$firstNameLabel.width            = 25
$firstNameLabel.height           = 10
$firstNameLabel.location         = New-Object System.Drawing.Point(53,43)
$firstNameLabel.Font             = 'Microsoft Sans Serif,10'
$firstNameLabel.ForeColor        = "#ffffff"

$emailLabel                      = New-Object system.Windows.Forms.Label
$emailLabel.text                 = "Email:"
$emailLabel.AutoSize             = $true
$emailLabel.width                = 25
$emailLabel.height               = 10
$emailLabel.location             = New-Object System.Drawing.Point(121,97)
$emailLabel.Font                 = 'Microsoft Sans Serif,10'
$emailLabel.ForeColor            = "#ffffff"

$inputEmail                      = New-Object system.Windows.Forms.TextBox
$inputEmail.multiline            = $false
$inputEmail.width                = 100
$inputEmail.height               = 20
$inputEmail.location             = New-Object System.Drawing.Point(23,117)
$inputEmail.Font                 = 'Microsoft Sans Serif,10'

$Label1                          = New-Object system.Windows.Forms.Label
$Label1.text                     = "Password:"
$Label1.AutoSize                 = $true
$Label1.width                    = 25
$Label1.height                   = 10
$Label1.location                 = New-Object System.Drawing.Point(40,147)
$Label1.Font                     = 'Microsoft Sans Serif,10'
$Label1.ForeColor                = "#ffffff"

$inputPassword                   = New-Object system.Windows.Forms.TextBox
$inputPassword.multiline         = $false
$inputPassword.width             = 100
$inputPassword.height            = 20
$inputPassword.location          = New-Object System.Drawing.Point(24,169)
$inputPassword.Font              = 'Microsoft Sans Serif,10'

$createUserButton                = New-Object system.Windows.Forms.Button
$createUserButton.BackColor      = "#03772a"
$createUserButton.text           = "Create"
$createUserButton.width          = 300
$createUserButton.height         = 50
$createUserButton.location       = New-Object System.Drawing.Point(1,249)
$createUserButton.Font           = 'Arial,15'
$createUserButton.ForeColor      = "#ffffff"

$pwGen                           = New-Object system.Windows.Forms.Button
$pwGen.BackColor                 = "#000000"
$pwGen.text                      = "Generate"
$pwGen.width                     = 83
$pwGen.height                    = 25
$pwGen.location                  = New-Object System.Drawing.Point(33,196)
$pwGen.Font                      = 'Microsoft Sans Serif,10'
$pwGen.ForeColor                 = "#ffffff"

$createUserHeader                = New-Object system.Windows.Forms.Label
$createUserHeader.text           = "Create User"
$createUserHeader.AutoSize       = $true
$createUserHeader.width          = 25
$createUserHeader.height         = 10
$createUserHeader.location       = New-Object System.Drawing.Point(85,10)
$createUserHeader.Font           = 'Microsoft Sans Serif,15,style=Bold,Underline'
$createUserHeader.ForeColor      = "#ffffff"

$Groupbox2                       = New-Object system.Windows.Forms.Groupbox
$Groupbox2.height                = 300
$Groupbox2.width                 = 300
$Groupbox2.BackColor             = "#4a4a4a"
$Groupbox2.location              = New-Object System.Drawing.Point(300,350)

$Label3                          = New-Object system.Windows.Forms.Label
$Label3.text                     = "label"
$Label3.AutoSize                 = $true
$Label3.width                    = 25
$Label3.height                   = 10
$Label3.location                 = New-Object System.Drawing.Point(-38,30)
$Label3.Font                     = 'Microsoft Sans Serif,10'

$atsign                          = New-Object system.Windows.Forms.Label
$atsign.text                     = "@"
$atsign.AutoSize                 = $false
$atsign.width                    = 10
$atsign.height                   = 7
$atsign.location                 = New-Object System.Drawing.Point(134,120)
$atsign.Font                     = 'Microsoft Sans Serif,10,style=Bold'
$atsign.ForeColor                = "#ffffff"

$domainDropdown                  = New-Object system.Windows.Forms.ComboBox
$domainDropdown.text             = "Domain"
$domainDropdown.width            = 100
$domainDropdown.height           = 20
@('techvera.com','geekonwheels.com','dipduo.com') | ForEach-Object {[void] $domainDropdown.Items.Add($_)}
$domainDropdown.location         = New-Object System.Drawing.Point(156,117)
$domainDropdown.Font             = 'Microsoft Sans Serif,10'

$inputLastName                   = New-Object system.Windows.Forms.TextBox
$inputLastName.multiline         = $false
$inputLastName.width             = 100
$inputLastName.height            = 20
$inputLastName.location          = New-Object System.Drawing.Point(157,65)
$inputLastName.Font              = 'Microsoft Sans Serif,10'

$lastNameLabel                   = New-Object system.Windows.Forms.Label
$lastNameLabel.text              = "Last:"
$lastNameLabel.AutoSize          = $true
$lastNameLabel.width             = 25
$lastNameLabel.height            = 10
$lastNameLabel.location          = New-Object System.Drawing.Point(191,43)
$lastNameLabel.Font              = 'Microsoft Sans Serif,10'
$lastNameLabel.ForeColor         = "#ffffff"

$Label2                          = New-Object system.Windows.Forms.Label
$Label2.text                     = "License:"
$Label2.AutoSize                 = $true
$Label2.width                    = 25
$Label2.height                   = 10
$Label2.location                 = New-Object System.Drawing.Point(174,147)
$Label2.Font                     = 'Microsoft Sans Serif,10'
$Label2.ForeColor                = "#ffffff"

$licenseDropdown                 = New-Object system.Windows.Forms.ComboBox
$licenseDropdown.text            = "None"
$licenseDropdown.width           = 100
$licenseDropdown.height          = 20
@('techvera.com','geekonwheels.com','dipduo.com') | ForEach-Object {[void] $licenseDropdown.Items.Add($_)}
$licenseDropdown.location        = New-Object System.Drawing.Point(156,169)
$licenseDropdown.Font            = 'Microsoft Sans Serif,6'

$bulkImportHeader                = New-Object system.Windows.Forms.Label
$bulkImportHeader.text           = "Bulk User Import"
$bulkImportHeader.AutoSize       = $true
$bulkImportHeader.width          = 25
$bulkImportHeader.height         = 10
$bulkImportHeader.location       = New-Object System.Drawing.Point(77,7)
$bulkImportHeader.Font           = 'Microsoft Sans Serif,15,style=Bold,Underline'
$bulkImportHeader.ForeColor      = "#ffffff"

$groupMigrateLabel               = New-Object system.Windows.Forms.Label
$groupMigrateLabel.text          = "Group Manager"
$groupMigrateLabel.AutoSize      = $true
$groupMigrateLabel.width         = 25
$groupMigrateLabel.height        = 10
$groupMigrateLabel.location      = New-Object System.Drawing.Point(70,358)
$groupMigrateLabel.Font          = 'Microsoft Sans Serif,15,style=Bold,Underline'
$groupMigrateLabel.ForeColor     = "#ffffff"

$Label4                          = New-Object system.Windows.Forms.Label
$Label4.text                     = "Disable User"
$Label4.AutoSize                 = $true
$Label4.width                    = 25
$Label4.height                   = 10
$Label4.location                 = New-Object System.Drawing.Point(391,56)
$Label4.Font                     = 'Microsoft Sans Serif,15,style=Bold,Underline'
$Label4.ForeColor                = "#ffffff"

$header                          = New-Object system.Windows.Forms.Groupbox
$header.height                   = 50
$header.width                    = 600
$header.BackColor                = "#202624"
$header.location                 = New-Object System.Drawing.Point(0,0)

$companyName                     = New-Object system.Windows.Forms.Label
$companyName.text                = "Company Name"
$companyName.AutoSize            = $true
$companyName.width               = 25
$companyName.height              = 10
$companyName.location            = New-Object System.Drawing.Point(8,9)
$companyName.Font                = 'Tw Cen MT,15,style=Bold'
$companyName.ForeColor           = "#ffffff"

$companySearch                   = New-Object system.Windows.Forms.Button
$companySearch.text              = "Switch Client"
$companySearch.width             = 109
$companySearch.height            = 30
$companySearch.location          = New-Object System.Drawing.Point(488,4)
$companySearch.Font              = 'Microsoft Sans Serif,10'
$companySearch.ForeColor         = "#ffffff"

$companyDetail                   = New-Object system.Windows.Forms.Label
$companyDetail.text              = "X User(s) || Y Group(s) || Z License(s)"
$companyDetail.AutoSize          = $true
$companyDetail.width             = 25
$companyDetail.height            = 10
$companyDetail.location          = New-Object System.Drawing.Point(11,32)
$companyDetail.Font              = 'Modern No. 20,10'
$companyDetail.ForeColor         = "#a7a7a7"

$disableUserAcctOpt              = New-Object system.Windows.Forms.ListBox
$disableUserAcctOpt.text         = "listBox"
$disableUserAcctOpt.width        = 290
$disableUserAcctOpt.height       = 103
$disableUserAcctOpt.location     = New-Object System.Drawing.Point(304,118)

$disableUserSearch               = New-Object system.Windows.Forms.TextBox
$disableUserSearch.multiline     = $false
$disableUserSearch.width         = 290
$disableUserSearch.height        = 20
$disableUserSearch.location      = New-Object System.Drawing.Point(305,92)
$disableUserSearch.Font          = 'Microsoft Sans Serif,10'

$disableUserButton               = New-Object system.Windows.Forms.Button
$disableUserButton.BackColor     = "#770303"
$disableUserButton.text          = "Disable"
$disableUserButton.width         = 300
$disableUserButton.height        = 50
$disableUserButton.location      = New-Object System.Drawing.Point(300,299)
$disableUserButton.Font          = 'Arial,15'
$disableUserButton.ForeColor     = "#ffffff"

$changePWOpt                     = New-Object system.Windows.Forms.CheckBox
$changePWOpt.text                = "Change Password"
$changePWOpt.AutoSize            = $true
$changePWOpt.width               = 118
$changePWOpt.height              = 18
$changePWOpt.location            = New-Object System.Drawing.Point(309,225)
$changePWOpt.Font                = 'Microsoft Sans Serif,10'

$disableActiveSyncOpt            = New-Object system.Windows.Forms.CheckBox
$disableActiveSyncOpt.text       = "Disable ActiveSync"
$disableActiveSyncOpt.AutoSize   = $true
$disableActiveSyncOpt.width      = 95
$disableActiveSyncOpt.height     = 20
$disableActiveSyncOpt.location   = New-Object System.Drawing.Point(309,245)
$disableActiveSyncOpt.Font       = 'Microsoft Sans Serif,10'

$shareConvertOpt                 = New-Object system.Windows.Forms.CheckBox
$shareConvertOpt.text            = "Add to Share"
$shareConvertOpt.AutoSize        = $true
$shareConvertOpt.width           = 95
$shareConvertOpt.height          = 20
$shareConvertOpt.location        = New-Object System.Drawing.Point(309,265)
$shareConvertOpt.Font            = 'Microsoft Sans Serif,10'

$setAccessPerms                  = New-Object system.Windows.Forms.CheckBox
$setAccessPerms.text             = "Give Access Perms"
$setAccessPerms.AutoSize         = $true
$setAccessPerms.width            = 95
$setAccessPerms.height           = 20
$setAccessPerms.location         = New-Object System.Drawing.Point(309,285)
$setAccessPerms.Font             = 'Microsoft Sans Serif,10'

$disablePWDetails                = New-Object system.Windows.Forms.Button
$disablePWDetails.text           = "Details"
$disablePWDetails.width          = 60
$disablePWDetails.height         = 13
$disablePWDetails.location       = New-Object System.Drawing.Point(444,225)
$disablePWDetails.Font           = 'Microsoft Sans Serif,8'

$manageAccessPerms               = New-Object system.Windows.Forms.Button
$manageAccessPerms.text          = "Manage"
$manageAccessPerms.width         = 60
$manageAccessPerms.height        = 13
$manageAccessPerms.location      = New-Object System.Drawing.Point(444,282)
$manageAccessPerms.Font          = 'Microsoft Sans Serif,8'

$365CC.controls.AddRange(@($Groupbox1,$Groupbox2,$groupMigrateLabel,$Label4,$header,$disableUserAcctOpt,$disableUserSearch,$disableUserButton,$changePWOpt,$disableActiveSyncOpt,$shareConvertOpt,$setAccessPerms,$disablePWDetails,$manageAccessPerms))
$Groupbox1.controls.AddRange(@($inputFirstName,$firstNameLabel,$emailLabel,$inputEmail,$Label1,$inputPassword,$createUserButton,$pwGen,$createUserHeader,$Label3,$atsign,$domainDropdown,$inputLastName,$lastNameLabel,$Label2,$licenseDropdown))
$Groupbox2.controls.AddRange(@($bulkImportHeader))
$header.controls.AddRange(@($companyName,$companySearch,$companyDetail))

$createUserButton.Add_Click({ createUser })
$pwGen.Add_Click({ genPW })