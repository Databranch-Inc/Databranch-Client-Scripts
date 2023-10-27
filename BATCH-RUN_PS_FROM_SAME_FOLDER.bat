REM Josh Britton 10/29/19
REM Use this .bat file to call Powershell from a GPO. Place this .bat file and the powershell .ps1 file in the same folder when creatig the GPO startup script
REM NOTE - UPDATE SCRIPT_NAME with the name of the script being started.

Powershell -noprofile -executionpolicy bypass -file "%~dp0SCRIPT_NAME.ps1"
