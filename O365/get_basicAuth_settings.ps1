Param
(

[cmdletbinding()]
    [Parameter(Mandatory= $true, HelpMessage="Enter your ApplicationId from the Secure Application Model https://github.com/KelvinTegelaar/SecureAppModel/blob/master/Create-SecureAppModel.ps1")]
    [string]$ApplicationId,
    [Parameter(Mandatory= $true, HelpMessage="Enter your ApplicationSecret from the Secure Application Model")]
    [string]$ApplicationSecret,
    [Parameter(Mandatory= $true, HelpMessage="Enter your Partner Tenantid")]
    [string]$tenantID,
    [Parameter(Mandatory= $true, HelpMessage="Enter your refreshToken from the Secure Application Model")]
    [string]$refreshToken,
    [Parameter(Mandatory= $true, HelpMessage="Enter your Exchange refreshToken from the Secure Application Model")]
    [string]$ExchangeRefreshToken,
    [Parameter(Mandatory= $true, HelpMessage="Enter the UPN of a global admin in partner center")]
    [string]$upn

)

# Check if the MSOnline PowerShell module has already been loaded.
if ( ! ( Get-Module MSOnline) ) {
    # Check if the MSOnline PowerShell module is installed.
    if ( Get-Module -ListAvailable -Name MSOnline ) {
        Write-Host -ForegroundColor Green "Loading the Azure AD PowerShell module..."
        Import-Module MsOnline
    } else {
        Install-Module MsOnline
    }
}


###MICROSOFT SECRETS#####

$ApplicationId = "d800ccf8-991c-485e-9dd8-9df4e32320ba"
$ApplicationSecret = "Dylcxpd621Mowk9iiHMMkKIWmsl3r+FwPDqjoK6n7TE="
$TenantID = "18cf09cf-f4d8-4e97-baaa-c5be8eb40a3d"
$RefreshToken = "0.ATgAzwnPGNj0l066qsW-jrQKPfjMANgcmV5Indid9OMjILo4AHM.AgABAAEAAAD--DLA3VO7QrddgJg7WevrAgDs_wQA9P_MdY4xhyBLXjNWmayhwnCNH6n0h0JIfifIqAwR4R1JwxHSsklbzWg2sjWB93YKaey8lURK1T6E4CmUfDe0dfj2ytc809Rj7HT-wSRvj4c5t1yX5XsG6wNpUaBat4meQXEOZ7PhfOOhQd8CfzmQYnIBRzubKKuwKPhUTZ_piCUgFCw8ra3K81haPBjZqpYxaI7ND5BNJGJQmFAzjPOjuNET3haigD3qphScW5fA-nzBBIWwW33XjQJDldcEpZCEIEUVf0h7FUU3agl9e5RYrdTzSzfJhD4csUKPGx8LXGUNkhAt7mOA64jl-EyIQZ-roiaocI_s7zqkjsSXdKlWlx9FUSj_wdAcgW3qtWwzQbuImqfNl62qEI07UsKl5qVe-M24czneD46YhsIGy37mF8FNIDOe7KF7YdntPkrGaiH5i2wqX7qpU-9y6Dr5hUWGqo_iixBWEOKepJ9--sB30HeoDoGn0hjKJtwyp4ArbadwJUwk1kHUd4XlnWqQwdNPsIvNnGHG6mWHG31pTi70uQTuI6Z_wg-Q4hXYQHtrQEz5Vs8YPl-AQvWcLykhY8G6mh-PNZofDiUS4dWiqss8-l8v3mQfeEbC0F8sk9SO453TQLK1v1gbthajWzTQCUZELHYQeVXOU88eRyOQpU-rBFMcP3hj1-7fqQQptc46wBHPKcDs2SEw-yKZRC2atGOF7RDTXQCkucvyhQSUNNUhEdG-QDzr9tQOwUf-_I-LclKaYimLEwwEgPhPUJJdygwBK6_GpOYRLXJxS9DvnaFcfinSAUy4D17DiuVGPu6kyFMqS_dWDMKLN7pZZrG0sg8MmersqbeKFKqS46jbHYi8u2Tavc4EIDAbtPW1vzFVQdyhfA3W0tXM5rfoXw8M_zKseQJAHg"
$ExchangeRefreshToken = "0.ATgAzwnPGNj0l066qsW-jrQKPRY8x6Djp2RFmpUr30c4NxY4AHM.AgABAAEAAAD--DLA3VO7QrddgJg7WevrAgDs_wQA9P_9B67Fl2zawlRyRyYLys4rc7AzKiZvEATxKl_PN-EKqLce8oS1S7jUZLZvZDRxkw--m8spypXuFIIoJoClrcclfJJcokwHx_1_Wu85k1bjL6Zit25eTwoY1red48g7fZvF8w5IxO0zf_-al7KPZRK-ajsi7fhoIRQaurviqLxWaPvNa0pLmIx_Z_jE04RMfHIcEhrck-14DYRVPFNTx6Ccs5YrWhcyHq_dLCgcYl5dZfmw8EAYO_sm-r8BrYVVyIKYWsoB4bJ49_ilrPhCD7EaOHToGureH72ONV2QjhArMwVidxw-hLgxpBe7NIYrOasMoFU0zAy48mqwCd8dpODSktGCiYpX-lB5uWj0vH2LShF3xe1sdhFdk6Zb9yglBRQGAyfVApn3jiW7HWBalbB0IGP-BlQBWbiUCDxl1Fhg8jnCpswzNauSCyyc6vbiReOTGBOPAQDCVw1P4uVO_M-UrXej6JHNv58DSNtrvXFsliel_LUUcJFnJcdY9Ho6KrekM-SUFN9OvMKPqKXIXAIOqn3I5WURGWaEB266B1HOsgFSlsFxnAhEXFnFyeHbzHkiDJbnjydOQGb9bNrz1s4IaKRmuCBsMUeTpxuJEtkl0-0-8au19Xae_vT0XZEDEpcrtNaWOW-CBB7AVGI2X6y-AqusuyR5mtQII-wQCVjA1-5exxDCDO79axwz6BlQJrJO3Xy6_jmOkf6909H2WDIbHSkczScPQRC6rDnUoyC2_awFcXEZcj1Py-GMbVGMzupQjhu8V9ajVl5gxRzE0sCkZLOFZufUPd0EyRXhoLb2FZ4LU78bJo3ARA"
$AzureRefreshToken = "0.ATgAzwnPGNj0l066qsW-jrQKPfjMANgcmV5Indid9OMjILo4AHM.AgABAAEAAAD--DLA3VO7QrddgJg7WevrAgDs_wQA9P_cvYs7rcpSWLg-zWVy4Wnv4TNNo1bWgeNlvNGBWAwUMQ4dBBGCvGiDJJINvGla1D4mbxg7sKRY8iOWa00OT1fKMJvSVWW7_PZkr8gUHTllS737v2yjIi_y9JuPuzQygTz6DZ0wWMR3MCZ0d29w8tWFGSKEqyQtRf3-mkEa72D0BG8u2WHsX4kwhPX70Z2giITT9iXUmDsnkCAvYKdQv9pFZAplfwVGsm4LMdIKv6ixHelLCVCIlqPvGcl9GDWXpNSW9qlVHUzAoNd0MrLJxEQKUM5oEjrYSxe1o5O8FTal1WJxKE1NYfZy5PIFWnbZ8zRM52QNo7C2egXlRzbjP1gC2IoPlMLlJWcxS-7VrMwD2j7JvE_cYTQIbt2WOKbiD6jd93ctEVH7yVzuxgpVtvIQcyFaX-fI13ODPq0P9RfikqXPoCPfIPG1fCGKsLu-7P9dmpAdFTg5pyixfnvTvtfOwMrjUL6zaqaA89E7ODQI5EgOvWsazxjDaxAggqhr6mDuGoIIsaunNGh11vMUMPJ9gCK9r7kiMfA3SXOegXZWtyQZafTPnQpse1VdQuQr4Niufg3WST5Exv-XiGI6sW7xYGlLentwqvdIelVAgB_xJnTJCp_gV6vxC6nUUIoPNtyal9_jMlsCqcMDPBimLY01tOH9jP7hXVMKdcxr0RxDtq2MTGsrSbsL6Tpm02c-5fLuuPk19ujPDV75Svo2cBpxqQtWPWEdBrflDwrubz05p7tlgz9P89sulVFkWNIOgf5CE1V_bUpAV9_k-Tj50lGgPJ-CdHXuxDKW8837cCBXPbu4UhMYgS60W2JMdan2hdCYGI2a3tP4pcOCvbmkuY9T1_ZU8Imka952mRsCq4JDuI2Y83f2piw"
$upn = $upn
$secPas = $ApplicationSecret | ConvertTo-SecureString -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($ApplicationId, $secPas)
 
$aadGraphToken = New-PartnerAccessToken -ApplicationId $ApplicationId -Credential $credential -RefreshToken $refreshToken -Scopes 'https://graph.windows.net/.default' -ServicePrincipal -Tenant $tenantID
$graphToken = New-PartnerAccessToken -ApplicationId $ApplicationId -Credential $credential -RefreshToken $refreshToken -Scopes 'https://graph.microsoft.com/.default' -ServicePrincipal -Tenant $tenantID
 
Connect-MsolService -AdGraphAccessToken $aadGraphToken.AccessToken -MsGraphAccessToken $graphToken.AccessToken
 
$customers = Get-MsolPartnerContract -All
 
Write-Host "Found $($customers.Count) customers for $((Get-MsolCompanyInformation).displayname)." -ForegroundColor DarkGreen

#Define CSV Path 
$path = echo ([Environment]::GetFolderPath("Desktop")+"\BasicAuthSettings")
New-Item -ItemType Directory -Force -Path $path
$BasicAuthReport = echo ([Environment]::GetFolderPath("Desktop")+"\BasicAuthSettings\BasicAuthCustomerList.csv")
 
foreach ($customer in $customers) {
    #Dispaly customer name#
    Write-Host "Checking Authentication settings for $($Customer.Name)" -ForegroundColor Green
    #Establish Token for Exchange Online
    $token = New-PartnerAccessToken -ApplicationId 'a0c73c16-a7e3-4564-9a95-2bdf47383716'-RefreshToken $ExchangeRefreshToken -Scopes 'https://outlook.office365.com/.default' -Tenant $customer.TenantId
    $tokenValue = ConvertTo-SecureString "Bearer $($token.AccessToken)" -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($upn, $tokenValue)
    $InitialDomain = Get-MsolDomain -TenantId $customer.TenantId | Where-Object {$_.IsInitial -eq $true}
    $session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri "https://ps.outlook.com/powershell-liveid?DelegatedOrg=$($InitialDomain)&BasicAuthToOAuthConversion=true" -Credential $credential -Authentication Basic -AllowRedirection 
    try{
    Import-PSSession $session -DisableNameChecking -ErrorAction Ignore
    } catch{}
    #Check Authsettings
    $Settings = ""
    $Settings = Get-AuthenticationPolicy
    if($Settings){

    $properties = @{'Company Name' = $customer.Name
		            'AllowBasicAuthActiveSync' = $Settings.AllowBasicAuthActiveSync
	                'AllowBasicAuthAutodiscover' = $Settings.AllowBasicAuthAutodiscover
                    'AllowBasicAuthImap' = $Settings.AllowBasicAuthImap
                    'AllowBasicAuthMapi' = $Settings.AllowBasicAuthMapi
                    'AllowBasicAuthPop' = $Settings.AllowBasicAuthPop
                    'AllowBasicAuthSmtp' = $Settings.AllowBasicAuthSmtp
                    'AllowBasicAuthPowershell' = $Settings.AllowBasicAuthPowershell    
	        }
     } else{
     write-Host "The settings are unavailable for this customer"
     $properties = @{
                    'Company Name' = $customer.Name
                    'AllowBasicAuthActiveSync' = "blank"
	                'AllowBasicAuthAutodiscover' = "blank"
                    'AllowBasicAuthImap' = "blank"
                    'AllowBasicAuthMapi' = "blank"
                    'AllowBasicAuthPop' = "blank"
                    'AllowBasicAuthSmtp' = "blank"
                    'AllowBasicAuthPowershell' = "blank"  
                    }  
     }
    
    $PropsObject = New-Object -TypeName PSObject -Property $Properties
    $PropsObject | Select-Object  "Company Name", "AllowBasicAuthActiveSync", "AllowBasicAuthAutodiscover","AllowBasicAuthImap","AllowBasicAuthMapi", "AllowBasicAuthPop","AllowBasicAuthSmtp", "AllowBasicAuthPowershell"  | Export-CSV -Path $BasicAuthReport -NoTypeInformation -Append     
    Remove-PSSession $session
    Write-Host "Removed PS Session"
    
}