<#
NetSmart Service Start Script

This script is designed to start any of the non-running NetSmart services for Homecare and Hospice.

The script will first check for "Netsmart Homecare Services Service" to be in a running state, then will loop though all the other Netsmart services and attempt to start them if they are not already running.

Version 1.0

Original Author - Josh Britton
Original Date - 7-24-25

=====================================================================================
Version 1.0

Original creation - JB
=====================================================================================
#>  

#Monitor for the NetSmart Homecare Services Service