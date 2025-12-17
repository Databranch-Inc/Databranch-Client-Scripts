
<#
.SYNOPSIS
  Single-DC health verifier for secure channel, DNS SRV, Netlogon/SYSVOL, DFSR.

.PARAMETER Domain
  The AD DNS name of your domain (e.g., MDAengineers.local). Defaults to the domain the DC is joined to.

.PARAMETER ForceReRegister
  When provided, will issue nltest /dsregdns and restart Netlogon to re-register SRV records.

.NOTES
  Run on the Domain Controller as Domain Admin. No external modules required.
#>

[CmdletBinding()]
param(
  [string]$Domain = (Get-ADDomain).DNSRoot,
  [switch]$ForceReRegister
)

# --------------------------
# Helpers
# --------------------------
function Write-OK    { param($msg) Write-Host "[ OK ] $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err   { param($msg) Write-Host "[FAIL] $msg" -ForegroundColor Red }
function Add-Result  { param([string]$Check, [string]$Status, [string]$Detail)
  $script:Results += [pscustomobject]@{ Check = $Check; Status = $Status; Detail = $Detail }
}

$Results = @()
$Computer = $env:COMPUTERNAME
$Fqdn     = ([System.Net.Dns]::GetHostByName($Computer)).HostName
$DomainUC = $Domain.ToUpper()

Write-Host "=== Single-DC Health Verifier ===" -ForegroundColor Cyan
Write-Host ("Domain         : {0}" -f $Domain)
Write-Host ("DC (Computer)  : {0}" -f $Computer)
Write-Host ("DC (FQDN)      : {0}" -f $Fqdn)
Write-Host ""

# --------------------------
# 1) DNS Client Sanity
# --------------------------
Write-Host "1) DNS client configuration..." -ForegroundColor Cyan
try {
  $dnsCfg = Get-DnsClientServerAddress -ErrorAction Stop | Where-Object {$_.InterfaceAlias -ne "Loopback Pseudo-Interface 1"}
  $dcIPs  = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias ($dnsCfg.InterfaceAlias | Select-Object -First 1) | Where-Object {$_.IPAddress -notlike "169.*"}).IPAddress
  $myIPv4 = $dcIPs | Select-Object -First 1

  $primaryDns = ($dnsCfg | Sort-Object -Property InterfaceIndex | Select-Object -First 1).ServerAddresses
  $usesSelf   = $primaryDns -contains $myIPv4
  $usesPublic = ($primaryDns | Where-Object { $_ -match '(^8\.8\.8\.8)|(^1\.1\.1\.1)|(^9\.9\.9\.9)' }) -ne $null

  if ($usesSelf -and -not $usesPublic) {
    Write-OK "NIC DNS points to the DC ($myIPv4) and no public DNS present."
    Add-Result "DNS Client" "PASS" "Primary DNS=$($primaryDns -join ', ')"
  } else {
    Write-Err "NIC DNS not ideal. Primary DNS=$($primaryDns -join ', ') (Expect DC IP only; no public)."
    Add-Result "DNS Client" "FAIL" "Primary DNS=$($primaryDns -join ', ')"
  }
} catch {
  Write-Err "Unable to read DNS client configuration: $($_.Exception.Message)"
  Add-Result "DNS Client" "FAIL" $_.Exception.Message
}

# --------------------------
# 2) Optional: Re-register SRVs
# --------------------------
if ($ForceReRegister) {
  Write-Host "`n2) Re-register SRV records (Netlogon)..." -ForegroundColor Cyan
  cmd /c "nltest /dsregdns" | Out-Null
  Restart-Service Netlogon -Force
  Write-OK "SRVs re-registered and Netlogon restarted."
}

# --------------------------
# 3) SRV Record Validation
# --------------------------
Write-Host "`n3) DNS SRV record validation..." -ForegroundColor Cyan
$SrvToCheck = @(
  "_ldap._tcp.dc._msdcs.$Domain",
  "_kerberos._tcp.$Domain",
  "_kerberos._udp.$Domain"
)

$SrvPass = $true
foreach ($srv in $SrvToCheck) {
  try {
    $r = Resolve-DnsName -Type SRV $srv -ErrorAction Stop
    $targets = ($r | Where-Object {$_.Type -eq "SRV"}).NameTarget
    if ($targets -and ($targets -match $Fqdn)) {
      Write-OK ("{0,-40} -> {1}" -f $srv, ($targets -join ", "))
    } else {
      Write-Warn ("{0,-40} present but does not list {1}" -f $srv, $Fqdn)
      $SrvPass = $false
    }
  } catch {
    Write-Err ("{0,-40} MISSING ({1})" -f $srv, $_.Exception.Message)
    $SrvPass = $false
  }
}
Add-Result "DNS SRV (_msdcs/domain)" ($SrvPass ? "PASS" : "FAIL") ($SrvPass ? "SRV records include DC FQDN" : "Missing/incorrect SRVs")

# --------------------------
# 4) Netlogon & SYSVOL shares
# --------------------------
Write-Host "`n4) NETLOGON/SYSVOL shares..." -ForegroundColor Cyan
$shares = (net share) 2>&1
$hasNetlogon = $shares | Select-String -SimpleMatch "NETLOGON"
$hasSysvol   = $shares | Select-String -SimpleMatch "SYSVOL"
if ($hasNetlogon -and $hasSysvol) {
  Write-OK "NETLOGON & SYSVOL shares are present."
  Add-Result "Shares (NETLOGON/SYSVOL)" "PASS" "Shares present"
} else {
  Write-Err "Missing NETLOGON/SYSVOL shares."
  Add-Result "Shares (NETLOGON/SYSVOL)" "FAIL" "One or both missing"
}

# --------------------------
# 5) dcdiag Advertising
# --------------------------
Write-Host "`n5) DCDIAG Advertising..." -ForegroundColor Cyan
$di = (cmd /c "dcdiag /test:advertising /v") 2>&1
if ($di -match "passed test Advertising") {
  Write-OK "DCDIAG Advertising passed."
  Add-Result "dcdiag Advertising" "PASS" "Advertising as DC/KDC/GC"
} else {
  Write-Err "DCDIAG Advertising failed or inconclusive."
  Add-Result "dcdiag Advertising" "FAIL" "See dcdiag output"
}

# --------------------------
# 6) NLTEST dsgetdc & sc_verify
# --------------------------
Write-Host "`n6) NLTEST queries..." -ForegroundColor Cyan
$dsgetdc = (cmd /c "nltest /dsgetdc:$Domain") 2>&1
$scverify = (cmd /c "nltest /sc_verify:$Domain") 2>&1

$dsgetdcPass = ($dsgetdc -match "DC:")
$scPass = ($scverify -match "NERR_Success")

if ($dsgetdcPass) { Write-OK "nltest /dsgetdc succeeded."; Add-Result "nltest dsgetdc" "PASS" "Resolved DC: $($dsgetdc -replace '\r|\n',' ')" }
else { Write-Err "nltest /dsgetdc failed."; Add-Result "nltest dsgetdc" "FAIL" ($dsgetdc -replace '\r|\n',' ') }

if ($scPass) { Write-OK "nltest /sc_verify succeeded."; Add-Result "nltest sc_verify" "PASS" ($scverify -replace '\r|\n',' ') }
else { Write-Warn "nltest /sc_verify failed."; Add-Result "nltest sc_verify" "FAIL" ($scverify -replace '\r|\n',' ') }

# --------------------------
# 7) Time & Kerberos
# --------------------------
Write-Host "`n7) Time & Kerberos..." -ForegroundColor Cyan
$w32 = (cmd /c "w32tm /query /status") 2>&1
$klist = (cmd /c "klist") 2>&1

if ($w32 -match "Stratum" -and $w32 -match "Source") {
  Write-OK "W32TM status available."
  Add-Result "Time Service" "PASS" ($w32 -replace '\r|\n',' ')
} else {
  Write-Warn "W32TM status not clear."
  Add-Result "Time Service" "WARN" ($w32 -replace '\r|\n',' ')
}

if ($klist -match "Kerberos") {
  Write-OK "Kerberos tickets present (or tool responding)."
  Add-Result "Kerberos Tickets" "PASS" "klist responded"
} else {
  Add-Result "Kerberos Tickets" "WARN" "No output from klist"
}

# --------------------------
# 8) SPN sanity (key ones)
# --------------------------
Write-Host "`n8) SPN sanity..." -ForegroundColor Cyan
$spn = (cmd /c "setspn -L $Computer") 2>&1
$spnOk = ($spn -match "HOST/" -and $spn -match "LDAP/" -and $spn -match "GC/")
if ($spnOk) {
  Write-OK "Key SPNs present (HOST/LDAP/GC)."
  Add-Result "SPNs (HOST/LDAP/GC)" "PASS" "Key SPNs found"
} else {
  Write-Warn "One or more key SPNs missing."
  Add-Result "SPNs (HOST/LDAP/GC)" "WARN" "Review setspn -L output"
}

# --------------------------
# 9) NIC network profile
# --------------------------
Write-Host "`n9) NIC network profile..." -ForegroundColor Cyan
try {
  $profiles = Get-NetConnectionProfile -ErrorAction Stop
  $domainProfile = $profiles | Where-Object { $_.NetworkCategory -eq "DomainAuthenticated" }
  if ($domainProfile) {
    Write-OK "NIC profile shows DomainAuthenticated."
    Add-Result "NIC Profile" "PASS" "DomainAuthenticated"
  } else {
    Write-Warn "NIC profile is not DomainAuthenticated (Public/Private)."
    Add-Result "NIC Profile" "WARN" ($profiles | Select-Object Name, NetworkCategory | Out-String)
  }
} catch {
  Write-Warn "Unable to read NIC profile: $($_.Exception.Message)"
  Add-Result "NIC Profile" "WARN" $_.Exception.Message
}

# --------------------------
# 10) DFSR signals (brief)
# --------------------------
Write-Host "`n10) DFSR recent events..." -ForegroundColor Cyan
try {
  $dfsr = Get-WinEvent -LogName "DFS Replication" -MaxEvents 30 -ErrorAction Stop |
          Select-Object TimeCreated, Id, Message
  $dfsrErr = $dfsr | Where-Object { $_.Id -in  (2213, 4612, 4614, 4008, 5002, 9032, 9061, 1753) }
  if ($dfsrErr) {
    Write-Warn "DFSR shows errors/warnings. Review below:"
    $dfsrErr | Format-Table -AutoSize
    Add-Result "DFSR Health" "WARN" ("IDs: " + (($dfsrErr.Id | Sort-Object -Unique) -join ", "))
  } else {
    Write-OK "No recent DFSR error events detected."
    Add-Result "DFSR Health" "PASS" "No recent DFSR errors"
  }
} catch {
  Write-Warn "Unable to read DFSR log: $($_.Exception.Message)"
  Add-Result "DFSR Health" "WARN" $_.Exception.Message
}

# --------------------------
# 11) Netlogon diagnostics tail
# --------------------------
Write-Host "`n11) Netlogon.log (tail 50)..." -ForegroundColor Cyan
$nlLogPath = "$env:SystemRoot\debug\netlogon.log"
if (Test-Path $nlLogPath) {
  Get-Content $nlLogPath -Tail 50 | ForEach-Object { $_ }
} else {
  Write-Warn "netlogon.log not found (it populates when Netlogon logging is enabled)."
}

# --------------------------
# Summary
# --------------------------
Write-Host "`n=== Summary (PASS/FAIL) ===" -ForegroundColor Cyan
$Results | Format-Table -AutoSize

$failCount = ($Results | Where-Object {$_.Status -eq "FAIL"}).Count
$warnCount = ($Results | Where-Object {$_.Status -eq "WARN"}).Count
if ($failCount -gt 0) {
  Write-Err ("Overall: FAIL ({0} failures, {1} warnings)" -f $failCount, $warnCount)
} elseif ($warnCount -gt 0) {
  Write-Warn ("Overall: WARN ({0} warnings)" -f $warnCount)
} else {
  Write-OK "Overall: PASS"
}

Write-Host "`nTip: If SRVs and Advertising pass but 'nltest /sc_verify' fails on a single DC, it can be a false-negative. Trust Advertising, shares, SRVs, and Kerberos/time signals."
