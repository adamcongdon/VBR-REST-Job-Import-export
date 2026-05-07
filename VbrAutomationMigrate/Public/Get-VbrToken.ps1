function Get-VbrToken {
    <#
    .SYNOPSIS
        Obtains an OAuth2 bearer token from a Veeam Backup & Replication v13
        Automation REST API endpoint via the password grant.

    .DESCRIPTION
        POSTs to /api/oauth2/token on the supplied BaseUri using
        application/x-www-form-urlencoded with grant_type=password,
        username, and password populated from the supplied PSCredential.

        Returns a strongly-typed [VbrToken] containing:
            AccessToken          : [SecureString]  (never logged)
            ExpiresAt            : [DateTime]      (UTC)
            BaseUri              : [Uri]
            Credential           : [PSCredential]  (cached for refresh)
            SkipCertificateCheck : [bool]

        The plaintext bearer token is materialized only inside
        New-VbrAuthHeader at request time. Verbose/Debug streams are
        scrubbed of any sensitive material.

    .PARAMETER BaseUri
        Root URI of the VBR REST API, e.g. https://vbr.example.com:9419

    .PARAMETER Credential
        PSCredential whose UserName / Password are used as OAuth password-
        grant inputs.

    .PARAMETER SkipCertificateCheck
        Disable TLS verification for self-signed certs. Off by default.

    .EXAMPLE
        $cred  = Get-Credential
        $token = Get-VbrToken -BaseUri 'https://vbr.example.com:9419' -Credential $cred -SkipCertificateCheck

    .NOTES
        VBR Automation REST API only supports VMware vSphere primary backup
        jobs. Hyper-V, Agent, NAS, Tape, Replication, Backup Copy, SaaS,
        AHV, Proxmox, and oVirt jobs are NOT in scope of this module.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [uri] $BaseUri,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [pscredential] $Credential,

        [Parameter()]
        [switch] $SkipCertificateCheck
    )

    # Materialize plaintext only inside this function's stack; never log it.
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
    try {
        $plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }

    $body = (
        'grant_type=password',
        ('username=' + [uri]::EscapeDataString($Credential.UserName)),
        ('password=' + [uri]::EscapeDataString($plainPass))
    ) -join '&'

    Write-Verbose ('Get-VbrToken: requesting OAuth2 token from {0}' -f $BaseUri.AbsoluteUri)

    try {
        $resp = Invoke-VbrApi `
            -Method 'POST' `
            -Path '/api/oauth2/token' `
            -Body $body `
            -ContentType 'application/x-www-form-urlencoded' `
            -SkipApiVersion `
            -NoAuth `
            -BaseUriOverride $BaseUri `
            -SkipCertificateCheckOverride:$SkipCertificateCheck
    } catch {
        $inner = $_.Exception
        $msg   = "Get-VbrToken: token request failed: $($inner.Message)"
        # PS7 ErrorRecord(message, errorId, category, targetObject, innerException)
        $errRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new($msg, $inner),
            'VbrTokenRequestFailed',
            [System.Management.Automation.ErrorCategory]::ConnectionError,
            $BaseUri
        )
        $PSCmdlet.ThrowTerminatingError($errRecord)
    } finally {
        # Scrub plaintext.
        $plainPass = $null
    }

    if (-not $resp -or -not $resp.PSObject.Properties.Match('access_token').Count -or -not $resp.access_token) {
        throw "Get-VbrToken: response did not contain an access_token field."
    }

    $expiresIn = 3600
    if ($resp.PSObject.Properties.Match('expires_in').Count -and $resp.expires_in) {
        try { $expiresIn = [int]$resp.expires_in } catch { $expiresIn = 3600 }
    }
    $expiresAt = [datetime]::UtcNow.AddSeconds($expiresIn)

    $sec = ConvertTo-SecureString -String ([string]$resp.access_token) -AsPlainText -Force
    $resp = $null  # drop the raw response object

    return [VbrToken]::new(
        $sec,
        $expiresAt,
        $BaseUri,
        $Credential,
        [bool]$SkipCertificateCheck
    )
}
