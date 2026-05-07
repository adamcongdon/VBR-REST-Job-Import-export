#requires -Version 7.4

# Hard PS7 gate. Defense in depth on top of the .psd1 PowerShellVersion field.
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "VbrAutomationMigrate requires PowerShell 7.4 or later. Current version: $($PSVersionTable.PSVersion). VBR v13 mandates PS7."
}

# ----------------------------------------------------------------------------
# Strongly-typed token class (defined here so [VbrToken] is visible to public
# functions that declare it as a parameter type).
# ----------------------------------------------------------------------------
class VbrToken {
    [securestring] $AccessToken
    [datetime]     $ExpiresAt
    [uri]          $BaseUri
    [pscredential] $Credential
    [bool]         $SkipCertificateCheck

    VbrToken() { }

    VbrToken(
        [securestring] $accessToken,
        [datetime]     $expiresAt,
        [uri]          $baseUri,
        [pscredential] $credential,
        [bool]         $skipCertificateCheck
    ) {
        $this.AccessToken          = $accessToken
        $this.ExpiresAt            = $expiresAt
        $this.BaseUri              = $baseUri
        $this.Credential           = $credential
        $this.SkipCertificateCheck = $skipCertificateCheck
    }
}

# ----------------------------------------------------------------------------
# Module-level constants. Single source of truth for protocol values that
# appear in every API request.
#   - VbrApiVersion: x-api-version header value (Constitutional Principle C6).
#   - VbrAcceptHeader: HTTP Accept header value for JSON responses.
# ----------------------------------------------------------------------------
$script:VbrApiVersion   = '1.3-rev1'
$script:VbrAcceptHeader = 'application/json'

# ----------------------------------------------------------------------------
# Module-level log target. Set by Invoke-VbrMigration at run start; cleared in
# its finally block. When $null, Write-VbrLog is a no-op (so callers running
# Export-Vbr* / Import-Vbr* directly don't error if no log is configured).
# Tests can drive Write-VbrLog by passing -Path explicitly without relying on
# this state.
# ----------------------------------------------------------------------------
$script:VbrLogPath = $null

# ----------------------------------------------------------------------------
# Dot-source Private/ then Public/ in deterministic order.
# ----------------------------------------------------------------------------
$privateRoot = Join-Path $PSScriptRoot 'Private'
$publicRoot  = Join-Path $PSScriptRoot 'Public'

if (Test-Path $privateRoot) {
    Get-ChildItem -Path $privateRoot -Filter '*.ps1' -File | Sort-Object Name | ForEach-Object {
        . $_.FullName
    }
}

$publicFunctions = @()
if (Test-Path $publicRoot) {
    Get-ChildItem -Path $publicRoot -Filter '*.ps1' -File | Sort-Object Name | ForEach-Object {
        . $_.FullName
        $publicFunctions += [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
    }
}

if ($publicFunctions.Count -gt 0) {
    Export-ModuleMember -Function $publicFunctions
}
