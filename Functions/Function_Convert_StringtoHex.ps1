function Convert-StringToHex {
    param (
        [Parameter(Mandatory)]
        [string]$InputString
    )

    # Convert each character to its hex value
    $hex = ($InputString.ToCharArray() | ForEach-Object {
        [System.Text.Encoding]::UTF8.GetBytes($_) | ForEach-Object {
            '{0:X2}' -f $_
        }
    }) -join ''

    return $hex
}

# Example usage
Convert-StringToHex -InputString "Hello"
