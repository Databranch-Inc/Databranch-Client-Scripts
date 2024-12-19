@echo off
set USERNAME=YourUsername
set PASSWORD=YourPassword
set NODE=Node.IP.Address.Used

REM Get filename of current script
for %%I in (%0) do set FILENAME=%%~nxI

REM Combine username:password and base64 encode
for /f "delims=" %%i in ('powershell -command "$auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('%USERNAME%:%PASSWORD%')); Write-Host $auth"') do set AUTH=%%i

REM Create the curl script
(
echo @echo off
echo curl.exe -k -X GET "https://%NODE%/rest/v1/Cluster/shutdown" -H "accept: application/json" -H "Authorization: Basic %AUTH%"
) > cluster_shutdown.bat

echo Created cluster_shutdown.bat with your curl command. For best security, you can now delete %FILENAME%