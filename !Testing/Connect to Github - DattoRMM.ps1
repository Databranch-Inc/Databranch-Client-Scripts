<#
Connect to Github - DattoRMM.ps1

This scirpt is designed to be used as a Datto RMM component to connect to Github and execute a function defined in a script stored in a Github repository. The script will download the specified script from Github, import the function, and execute it with the provided arguments.

Databranch IT Glue Documentation
#>








$ErrorActionPreference = 'Stop'

function Get-EnvTrim([string]$name) {
  $v = [System.Environment]::GetEnvironmentVariable($name)
  if ($null -eq $v) { return '' }
  return $v.Trim()
}

# --- Datto component variables ---
$RawUrl = Get-EnvTrim 'usrRawUrl'
$Token = Get-EnvTrim 'usrGhToken'
$FunctionName     = Get-EnvTrim 'usrFunctionName'
$FunctionArgsJson = Get-EnvTrim 'usrFunctionArgsJson'

if (-not $RawUrl)  { throw "Missing usrRawUrl" }
if (-not $Token) { throw "Missing usrGhToken (PAT required for private repos)" }
if (-not $FunctionName) { throw "Missing usrFunctionName" }


$Headers = @{
  'Authorization' = "token $Token"
  'User-Agent'    = 'DattoRMM-Component'
  'Accept'        = 'application/octet-stream'
}

# Download to temp file (avoid IEX)
$TempFile = Join-Path $env:TEMP ("gh_" + [IO.Path]::GetRandomFileName() + ".ps1")

try {
  Invoke-WebRequest -Uri $RawUrl -Headers $Headers -UseBasicParsing -OutFile $TempFile

  if (-not (Test-Path $TempFile)) { throw "Download failed (no file created)" }
  if ((Get-Item $TempFile).Length -lt 1) { throw "Downloaded file is empty" }

  # Dot-source to load the function into current scope
  . $TempFile

  # Verify function exists
  if (-not (Get-Command -Name $FunctionName -CommandType Function -ErrorAction SilentlyContinue)) {
    throw "Function '$FunctionName' not found after importing $Owner/$Repo/$Path"
  }

  # Call the function with args (JSON -> Hashtable -> splat)
  if ($FunctionArgsJson) {
    $ArgHash = ConvertFrom-Json -InputObject $FunctionArgsJson
    # ConvertFrom-Json returns PSCustomObject in PS5.1; convert to hashtable for splatting:
    $ht = @{}
    $ArgHash.psobject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
    & $FunctionName @ht
  } else {
    & $FunctionName
  }
}
finally {
  if (Test-Path $TempFile) { Remove-Item $TempFile -Force -ErrorAction SilentlyContinue }
}