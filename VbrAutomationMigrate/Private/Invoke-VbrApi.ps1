function Invoke-VbrApi {
    <#
    .SYNOPSIS
        Single HTTP egress point for the VbrAutomationMigrate module.

    .DESCRIPTION
        Wraps Invoke-RestMethod with the VBR Automation REST API conventions:
        - x-api-version: 1.3-rev1 (Constitutional Principle C6)
        - Authorization: Bearer <token>
        - accept: application/json
        - Content-Type: application/json (when a body is supplied)
        - Honors -SkipCertificateCheck from the supplied VbrToken
        - Refreshes the token once on a 401 response and retries.

    .PARAMETER Token
        Strongly-typed VbrToken obtained from Get-VbrToken.

    .PARAMETER Method
        HTTP verb (GET, POST, etc).

    .PARAMETER Path
        URI path component, e.g. '/api/v1/automation/credentials/export'.
        Joined to $Token.BaseUri.

    .PARAMETER Body
        Optional request body. If a non-null PSObject/Hashtable, it is
        serialized via ConvertTo-VbrJson (depth 50). If a string, it is
        sent verbatim with the supplied content-type.

    .PARAMETER ContentType
        Defaults to application/json. Set differently only by the OAuth
        token endpoint (application/x-www-form-urlencoded).

    .PARAMETER AdditionalHeaders
        Extra request headers merged in last.

    .PARAMETER SkipApiVersion
        Internal switch used by Get-VbrToken so the OAuth path doesn't get
        the x-api-version header (it's not auth-relevant for token issue).

    .PARAMETER NoAuth
        Internal switch used by Get-VbrToken to suppress the bearer header
        (we don't have a token yet at issue time).

    .NOTES
        VBR Automation REST API only supports VMware vSphere primary backup
        jobs. See module README and about_VbrAutomationMigrate for full list
        of unsupported job categories.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        $Token,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Method,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter()]
        $Body,

        [Parameter()]
        [string] $ContentType = 'application/json',

        [Parameter()]
        [hashtable] $AdditionalHeaders = @{},

        [Parameter()]
        [switch] $SkipApiVersion,

        [Parameter()]
        [switch] $NoAuth,

        [Parameter()]
        [uri] $BaseUriOverride,

        [Parameter()]
        [switch] $SkipCertificateCheckOverride
    )

    # Resolve BaseUri / cert behavior.
    $baseUri = $null
    $skipCert = $false
    if ($PSBoundParameters.ContainsKey('BaseUriOverride') -and $BaseUriOverride) {
        $baseUri  = $BaseUriOverride
        $skipCert = [bool]$SkipCertificateCheckOverride
    } elseif ($Token) {
        $baseUri  = $Token.BaseUri
        $skipCert = [bool]$Token.SkipCertificateCheck
    } else {
        throw 'Invoke-VbrApi requires either -Token or -BaseUriOverride.'
    }

    if (-not $baseUri) {
        throw 'Invoke-VbrApi: no BaseUri available (Token.BaseUri and BaseUriOverride both empty).'
    }

    # Compose the full URL.
    $baseStr = $baseUri.AbsoluteUri.TrimEnd('/')
    $pathStr = $Path
    if (-not $pathStr.StartsWith('/')) { $pathStr = '/' + $pathStr }
    $fullUri = [uri]"$baseStr$pathStr"

    # Build headers.
    $headers = @{
        'accept' = $script:VbrAcceptHeader
    }
    if (-not $SkipApiVersion) {
        $headers['x-api-version'] = $script:VbrApiVersion
    }
    if (-not $NoAuth -and $Token) {
        # Materialize bearer just before sending.
        $authHeader = New-VbrAuthHeader -Token $Token
        foreach ($k in $authHeader.Keys) { $headers[$k] = $authHeader[$k] }
    }
    foreach ($k in $AdditionalHeaders.Keys) { $headers[$k] = $AdditionalHeaders[$k] }

    # Serialize body if needed.
    $bodyToSend = $null
    if ($null -ne $Body) {
        if ($Body -is [string]) {
            $bodyToSend = $Body
        } else {
            $bodyToSend = ConvertTo-VbrJson -InputObject $Body
        }
    }

    # Build the splat. Avoid logging the headers (Authorization is in there).
    $irmParams = @{
        Uri         = $fullUri
        Method      = $Method
        Headers     = $headers
        ContentType = $ContentType
        ErrorAction = 'Stop'
        TimeoutSec  = 300
    }
    if ($null -ne $bodyToSend) { $irmParams['Body'] = $bodyToSend }
    if ($skipCert)             { $irmParams['SkipCertificateCheck'] = $true }

    Write-Verbose ("Invoke-VbrApi {0} {1}" -f $Method, $fullUri)

    try {
        return Invoke-RestMethod @irmParams
    } catch {
        # On 401 with a token in hand, attempt one refresh + retry.
        $isUnauthorized = $false
        if ($_.Exception -and $_.Exception.Response) {
            try {
                if ([int]$_.Exception.Response.StatusCode -eq 401) { $isUnauthorized = $true }
            } catch { $isUnauthorized = $false }
        }
        if ($isUnauthorized -and $Token -and $Token.Credential -and -not $NoAuth) {
            Write-Verbose 'Invoke-VbrApi: 401 -- refreshing token and retrying once.'
            $fresh = Get-VbrToken -BaseUri $Token.BaseUri -Credential $Token.Credential -SkipCertificateCheck:$Token.SkipCertificateCheck
            $Token.AccessToken = $fresh.AccessToken
            $Token.ExpiresAt   = $fresh.ExpiresAt

            $authHeader = New-VbrAuthHeader -Token $Token
            foreach ($k in $authHeader.Keys) { $irmParams.Headers[$k] = $authHeader[$k] }
            return Invoke-RestMethod @irmParams
        }
        throw
    }
}
