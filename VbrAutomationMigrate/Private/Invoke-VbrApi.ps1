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

    # Only build the body-summary string and time the call when a log target
    # is actually set. Skips per-call serialization when logging is disabled.
    $logActive = (-not [string]::IsNullOrWhiteSpace($script:VbrLogPath)) -and ($script:VbrLogPath -ne '/dev/null')

    if ($logActive) {
        # OAuth token endpoint posts the user's password in form-encoded text.
        # Never log that body. Cap other bodies at 500 chars so full job specs
        # don't bloat the log; Write-VbrLog still redacts password=, passphrase=,
        # privateKey=, and access_token from whatever survives.
        $bodyLogValue = '<none>'
        if ($null -ne $bodyToSend) {
            if ($pathStr -ieq '/api/oauth2/token') {
                $bodyLogValue = '<redacted oauth-credentials>'
            } else {
                $bs = [string]$bodyToSend
                if ($bs.Length -gt 500) { $bs = $bs.Substring(0, 500) + '...<truncated>' }
                $bodyLogValue = $bs
            }
        }
        Write-VbrLog -Level 'Debug' -Context @{
            http = "$Method $pathStr"
            body = $bodyLogValue
        } -Message ''
    }

    $startedUtc = if ($logActive) { [datetime]::UtcNow } else { $null }
    try {
        $result = Invoke-RestMethod @irmParams
        if ($logActive) {
            $elapsedMs = [int]([datetime]::UtcNow - $startedUtc).TotalMilliseconds
            # Re-serialize the response to estimate byte size cheaply -- avoids
            # hooking the response stream at the cost of one ConvertTo-VbrJson.
            $bytes = 0
            try {
                if ($null -ne $result) {
                    $bytes = ([string](ConvertTo-VbrJson -InputObject $result)).Length
                }
            } catch { $bytes = 0 }
            Write-VbrLog -Level 'Debug' -Context @{
                http     = "$Method $pathStr"
                status   = 200
                duration = "${elapsedMs}ms"
                bytes    = $bytes
            } -Message ''
        }
        return $result
    } catch {
        # Capture status code for log context (best-effort -- not all errors carry one).
        $statusCode = 0
        if ($_.Exception -and $_.Exception.Response) {
            try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { $statusCode = 0 }
        }

        # On 401 with a token in hand, attempt one refresh + retry.
        $isUnauthorized = ($statusCode -eq 401)
        if ($isUnauthorized -and $Token -and $Token.Credential -and -not $NoAuth) {
            Write-Verbose 'Invoke-VbrApi: 401 -- refreshing token and retrying once.'
            if ($logActive) {
                Write-VbrLog -Level 'Debug' -Context @{
                    http   = "$Method $pathStr"
                    status = 401
                    action = 'refresh-and-retry'
                } -Message ''
            }
            $fresh = Get-VbrToken -BaseUri $Token.BaseUri -Credential $Token.Credential -SkipCertificateCheck:$Token.SkipCertificateCheck
            $Token.AccessToken = $fresh.AccessToken
            $Token.ExpiresAt   = $fresh.ExpiresAt

            $authHeader = New-VbrAuthHeader -Token $Token
            foreach ($k in $authHeader.Keys) { $irmParams.Headers[$k] = $authHeader[$k] }
            return Invoke-RestMethod @irmParams
        }

        if ($logActive) {
            Write-VbrLog -Level 'Error' -Context @{
                http   = "$Method $pathStr"
                status = $statusCode
                error  = ([string]$_.Exception.Message)
            } -Message ''
        }
        throw
    }
}
