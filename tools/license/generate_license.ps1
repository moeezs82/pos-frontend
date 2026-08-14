[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Customer,
    [Parameter(Mandatory = $true)][string]$MachineCode,
    [ValidateSet('local', 'server')][string]$Edition = 'local',
    [string]$PrivateKeyPath = (Join-Path $env:USERPROFILE 'Documents\CounterIQ-License-Authority\counteriq-license-private.pfx'),
    [Nullable[datetime]]$ExpiresOn,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $PrivateKeyPath)) {
    throw "CounterIQ private licensing PFX was not found: $PrivateKeyPath"
}

$customerName = $Customer.Trim()
if ([string]::IsNullOrWhiteSpace($customerName)) {
    throw 'Customer cannot be empty.'
}

$device = ($MachineCode -replace '[^A-Fa-f0-9]', '').ToUpperInvariant()
if ($device.Length -ne 64) {
    throw 'MachineCode must be the complete CounterIQ machine code (64 hexadecimal characters, separators are allowed).'
}

Write-Host ''
Write-Host 'CounterIQ License Generator' -ForegroundColor Cyan
$securePassword = Read-Host 'Private PFX password' -AsSecureString

$ptr = [IntPtr]::Zero
$plainPassword = $null
$cert = $null
$rsa = $null
try {
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)

    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
        $PrivateKeyPath,
        $plainPassword,
        [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet
    )

    if (-not $cert.HasPrivateKey) {
        throw 'The selected CounterIQ PFX does not contain its private signing key.'
    }

    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
    if ($null -eq $rsa) {
        throw 'The CounterIQ private certificate does not contain an RSA signing key.'
    }

    $issuedAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $expiryText = ''
    $expiryJson = $null
    if ($null -ne $ExpiresOn) {
        $expiryUtc = $ExpiresOn.Value.ToUniversalTime()
        $expiryText = $expiryUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $expiryJson = $expiryText
    }

    $customerBytes = [Text.Encoding]::UTF8.GetBytes($customerName)
    $customerB64 = [Convert]::ToBase64String($customerBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')

    $canonical = @(
        'version=1',
        'product=CounterIQ',
        "customer=$customerB64",
        "edition=$Edition",
        "device=$device",
        "issued_at=$issuedAt",
        "expires_at=$expiryText"
    ) -join "`n"

    $payload = [Text.Encoding]::UTF8.GetBytes($canonical)
    $signatureBytes = $rsa.SignData(
        $payload,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
    )

    $license = [ordered]@{
        version = 1
        product = 'CounterIQ'
        customer = $customerName
        edition = $Edition
        device_fingerprint = $device
        issued_at = $issuedAt
        expires_at = $expiryJson
        signature = [Convert]::ToBase64String($signatureBytes)
        signer_thumbprint = $cert.Thumbprint.ToUpperInvariant()
    }

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $safeCustomer = ($customerName -replace '[^A-Za-z0-9_-]+', '-').Trim('-')
        if ([string]::IsNullOrWhiteSpace($safeCustomer)) { $safeCustomer = 'customer' }
        $shortDevice = $device.Substring(0, 8)
        $OutputPath = Join-Path (Get-Location) "CounterIQ-$safeCustomer-$Edition-$shortDevice.ciqlic"
    }

    $json = $license | ConvertTo-Json -Depth 4
    [IO.File]::WriteAllText(
        $OutputPath,
        $json,
        (New-Object Text.UTF8Encoding($false))
    )
}
finally {
    if ($null -ne $rsa) { $rsa.Dispose() }
    if ($null -ne $cert) { $cert.Dispose() }
    $plainPassword = $null
    if ($ptr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

Write-Host ''
Write-Host 'License created successfully.' -ForegroundColor Green
Write-Host "Customer : $customerName"
Write-Host "Edition  : $Edition"
Write-Host "Device   : $device"
Write-Host "File     : $OutputPath"
