<#
Connect to Github

This is the code snippet that is used to connect to Databranch Github and pull a script for Automations. This snippet is currently set to acceept variables set by CW Automate (note the sections wrapped in @ symbols.)

This script is desiged to be used as a reference point, and not called outside of CW Automate. 

Please see the following references for this and use cases.

https://databranch.itboost.com/app/documentation/knowledgebase/view/181583c7-bf96-4fea-89da-5cadcbc58318

https://www.gavsto.com/why-i-think-now-is-a-good-time-to-start-phasing-out-rmm-specific-scripts/


Josh Britton - Saved to Github 5-28-24
1.1 Upate - 2-13-26

=================================================================================
Version 1.1 Update - 

Updating this script to be compatible with Datto RMM Script logic, Going to leave the Legacy Code in as a comment at the bottom for historical reference until we fully offboard from CW Automate

=================================================================================
#>

#Gather customizeable variables from Datto RMM Component (Update these as the component tempalte is copied)
$githubtoken = $ENV:GitHubToken
$scripturl = $ENV:GitHubURL
$Function = {$ENV:Function}


<#

#Set job variables and input from Datto RMM component/system variables. Note that the Auth token and Script URL are set by CW Automate Script Variables.
$wc = New-Object System.Net.WebClient
$wc.Headers.Add('Authorization','token "$githubtoken"')
$wc.Headers.Add('Accept','application/vnd.github.v3.raw')
$wc.DownloadString("$scripturl") | iex

#>

# Ensure these are clean
$githubtoken = $githubtoken.Trim()
$scripturl   = $scripturl.Trim()

# Validate/force as Uri to catch bad characters early
$uri = [Uri]$scripturl

$wc = New-Object System.Net.WebClient
$wc.Headers['Authorization'] = "token $githubtoken"
$wc.Headers['Accept']        = 'application/vnd.github.v3.raw'

$wc.DownloadString($uri) | iex


#SCRIPT/FUNCTION INFO HERE - UPDATE TO THE CREATED FUNCTION IN THE POWERSHELL SCRIPT ON GITHUB

& $Function

<#

NOTE - THIS COMMENT IS THE LEGACY METHOD TO CONNECT TO GITHUB WITH CW AUTOMATE'S SCRIPTING ENGINE CALLING POWERSHELL - MOVED TO THIS COMMENT WHILE WE MIGRATE FROM CW AUTOMATE TO DATTO RM - JB 2-13-26

#Set Variables. Note that the Auth token and Script URL are set by CW Automate Script Variables.
$wc = New-Object System.Net.WebClient
$wc.Headers.Add('Authorization','token @Github Token@')
$wc.Headers.Add('Accept','application/vnd.github.v3.raw')
$wc.DownloadString('@scriptURL@') | iex

#SCRIPT/FUNCTION INFO HERE - UPDATE TO THE CREATED FUNCTION IN THE POWERSHELL SCRIPT ON GITHUB

CALL-FUNCTION

#>