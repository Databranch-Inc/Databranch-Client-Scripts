<#
Connect to Github

This is the code snippet that is used to connect to Databranch Github and pull a script for Automations. This snippet is currently set to acceept variables set by CW Automate (note the sections wrapped in @ symbols.)

This script is desiged to be used as a reference point, and not called outside of CW Automate. 

Please see the following references for this and use cases.

https://databranch.itboost.com/app/documentation/knowledgebase/view/181583c7-bf96-4fea-89da-5cadcbc58318

https://www.gavsto.com/why-i-think-now-is-a-good-time-to-start-phasing-out-rmm-specific-scripts/


Josh Britton - Saved to Github 5-28-24
#>

#Set Variables. Note that the Auth token and Script URL are set by CW Automate Script Variables.
$wc = New-Object System.Net.WebClient
$wc.Headers.Add('Authorization','token @Github Token@')
$wc.Headers.Add('Accept','application/vnd.github.v3.raw')
$wc.DownloadString('@scriptURL@') | iex

#SCRIPT/FUNCTION INFO HERE - UPDATE TO THE CREATED FUNCTION IN THE POWERSHELL SCRIPT ON GITHUB

CALL-FUNCTION