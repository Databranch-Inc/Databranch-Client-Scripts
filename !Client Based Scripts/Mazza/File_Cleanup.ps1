<#
File-Cleanup.ps1

This script reads file name patterns from a specified text file and deletes matching files from specified root directories, while excluding certain system paths. It is designed to help clean up unwanted files based on defined patterns.

File Created By - Dan Brown
Originally Created - 3-17-2026
Version 1.0 - Initial script creation

============================================================================================================
1.0 - Initial script creation

============================================================================================================
#>

#Variables
$ListPath = ".\file-removal-patterns.txt"
$Roots = @('C:\')
$ExcludePaths = @(
    'C:\Windows',
    'C:\Program Files',
    'C:\Program Files (x86)',
    'C:\ProgramData\Microsoft\Windows\Start Menu',
    'C:\Recovery',
    'C:\$Recycle.Bin',
    'C:\System Volume Information'
)

$Patterns = Get-Content -Path $ListPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() }
$ExcludePrefixes = $ExcludePaths | ForEach-Object { ($_).TrimEnd('\') + '\' }

function Test-IsExcludedPath {
    param([string]$FullPath)
    foreach ($prefix in $ExcludePrefixes) {
    if ($FullPath.StartsWith($prefix, $true, $null)) { return $true }
    }
    return $false
}

foreach ($root in $Roots) {
    if (-not (Test-Path $root)) { Write-Warning "Root not found: $root"; continue }
    Get-ChildItem -Path $root -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object { -not (Test-IsExcludedPath $_.FullName) } |
    ForEach-Object {
$match = $false
foreach ($pat in $Patterns) {
    if ($_.Name -like $pat) { $match = $true; break }
    }
    if ($match) { $_ }
    } |
    Remove-Item -Force -ErrorAction SilentlyContinue -Verbose # <- removed -WhatIf
}