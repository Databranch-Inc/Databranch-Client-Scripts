Get-DhcpServerv4Scope -ScopeId 10.10.1.0 | Get-DhcpServerv4Lease -BadLeases | Remove-DhcpServerv4Lease
