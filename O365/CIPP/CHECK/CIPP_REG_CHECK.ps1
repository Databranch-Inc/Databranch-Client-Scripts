# CIPP_REG_CHECK.ps1
# Monitor a specific registry value and exit with success only when the value matches the expected date.

# Manually set these variables for the registry key and expected date value.

$chromeExtensionId = "benimdeioplgkhanklclahllklceahbe"
$edgeExtensionId = "knepjpocdagponkonnbggpcnhnaikajg"
$chromeManagedStorageKey = "HKLM:\SOFTWARE\Policies\Google\Chrome\3rdparty\extensions\$chromeExtensionId\policy"
$edgeManagedStorageKey = "HKLM:\SOFTWARE\Policies\Microsoft\Edge\3rdparty\extensions\$edgeExtensionId\policy"

$ValueName = 'CHECKDeploymentVersionDate'
$ExpectedValue = '2026-06-09'


Foreach ($RegistryPath in @($chromeManagedStorageKey, $edgeManagedStorageKey)) {

try {
    if (-not (Test-Path -Path $RegistryPath)) {
        write-host '<-Start Result->'
        "RESULT=Registry path not found: $RegistryPath"
        write-host '<-End Result->'
        
        exit 1
    }

    $property = Get-ItemProperty -Path $RegistryPath -Name $ValueName -ErrorAction Stop
    $actualValue = $property.$ValueName

    if ($null -eq $actualValue) {
        write-host '<-Start Result->'
        "RESULT=Registry value '$ValueName' does not exist under '$RegistryPath'."
        write-host '<-End Result->'       
        
        exit 1
    }

    if ($actualValue -eq $ExpectedValue) {
        write-host '<-Start Result->'
        "RESULT=Registry value matches '$ExpectedValue' No Action Needed."
        write-host '<-End Result->'       
        
        exit 0
    }
    else {
        write-host '<-Start Result->'
        "RESULT=Registry value mismatch. Expected '$ExpectedValue', found '$actualValue'."
        write-host '<-End Result->'       
        
        exit 1
    }
}
catch {
    write-host '<-Start Result->'
    "RESULT=$_.Exception.Message"
    write-host '<-End Result->'       
        
    exit 1
}

}