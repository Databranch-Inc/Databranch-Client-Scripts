<#
DHCP Fix

This Script is desiged to review a DHCP Scope and remove any bad leases that are causing issues.

Script originally writeen by: Sam Kirsch for GFS. Moving into Github for better tracking and version control. - JB 3-24-25
#>

function Remove-DhcpServerv4BadLease {
    param (
        
    )
    
    Get-DhcpServerv4Scope -ScopeId 10.10.1.0 | Get-DhcpServerv4Lease -BadLeases | Remove-DhcpServerv4Lease

}



