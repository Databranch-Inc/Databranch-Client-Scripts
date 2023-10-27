function Search-RegistryKeyValues {
 param(
 [string]$path,
 [string]$valueName
 )
 Get-ChildItem $path -recurse -ea SilentlyContinue |
 % {
  if ((Get-ItemProperty -Path $_.PsPath -ea SilentlyContinue) -match $valueName)
  {
   $_.PsPath
  }
 }
}

# find registry key that has value "digitalproductid"
# 32-bit versions
$key = Search-RegistryKeyValues "hklm:\software\microsoft\office" "digitalproductid"
if ($key -eq $null) {
    # 64-bit versions
 $key = Search-RegistryKeyValues "hklm:\software\Wow6432Node\microsoft\office" "digitalproductid"
 if ($key -eq $null) {Write-Host "MS Office is not installed.";break}
}

$valueData = (Get-ItemProperty $key).digitalproductid[52..66]

# decrypt base24 encoded binary data
$productKey = ""
$chars = "BCDFGHJKMPQRTVWXY2346789"
for ($i = 24; $i -ge 0; $i--) {
 $r = 0
 for ($j = 14; $j -ge 0; $j--) {
  $r = ($r * 256) -bxor $valueData[$j]
  $valueData[$j] = [math]::Truncate($r / 24)
  $r = $r % 24
 }
 $productKey = $chars[$r] + $productKey
 if (($i % 5) -eq 0 -and $i -ne 0) {
  $productKey = "-" + $productKey
 }
}

Write-Host "MS Office Product Key:" $productKey