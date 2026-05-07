function Write-VbrLog {
    <#
    .SYNOPSIS
        Append a single structured log line to a file with secret redaction.

    .DESCRIPTION
        Writes one timestamped, level-prefixed log line per invocation to the
        target file. Used by Invoke-VbrApi, Wait-VbrAutomationSession,
        Test-VbrCredentialPasswords, and Invoke-VbrMigration so the operator
        gets a single timestamped trail to hand to support after a failed run.

        Format:
            2026-05-07T22:14:33.812Z [INFO]  [phase=auth-source] message
            2026-05-07T22:14:33.901Z [DEBUG] [http=POST /api/v1/automation/credentials/export status=200 duration=87ms bytes=2410]

        Constitutional Principle 4 (no bearer tokens / no secrets to verbose,
        debug, or host streams) is extended to the file log: this function
        scrubs the formatted line for Bearer values, password=, passphrase=,
        privateKey=, and access_token before writing.

        No-op behavior:
        - If neither -Path nor $script:VbrLogPath is set, the call is a no-op.
        - If $script:VbrLogPath is the literal string '/dev/null', the call is
          a no-op (operator opted out of file logging).

    .PARAMETER Path
        Optional explicit log file path. Overrides $script:VbrLogPath.

    .PARAMETER Level
        Log severity. One of Info, Warn, Error, Debug.

    .PARAMETER Message
        Free-form message body. Redaction runs on the final formatted line so
        any secret-bearing tokens passed through here are scrubbed.

    .PARAMETER Phase
        Optional orchestrator phase tag (auth-source, export-source, persist,
        auth-target, import-target, verify, complete).

    .PARAMETER Context
        Optional hashtable serialized to inline key=value pairs in the
        bracket. Useful for HTTP call detail (method, path, status, duration)
        or session detail (id, state, attempt, elapsed).

    .NOTES
        Append-only. Single Add-Content call per invocation -> atomic single-
        line write on POSIX (open(O_APPEND) for sub-PIPE_BUF lines).
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Path,

        [Parameter(Mandatory)]
        [ValidateSet('Info','Warn','Error','Debug')]
        [string] $Level,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Message,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Phase,

        [Parameter()]
        [hashtable] $Context
    )

    # Resolve effective path: explicit -Path wins; fall back to module state.
    $effectivePath = $Path
    if ([string]::IsNullOrWhiteSpace($effectivePath)) {
        $effectivePath = $script:VbrLogPath
    }

    # No-op when no target path is set anywhere.
    if ([string]::IsNullOrWhiteSpace($effectivePath)) {
        return
    }

    # Operator opt-out sentinel: '/dev/null' means "logging disabled".
    if ($effectivePath -eq '/dev/null') {
        return
    }

    # Format the level token with fixed width so columns align in the log.
    $levelToken = switch ($Level) {
        'Info'  { '[INFO] ' }
        'Warn'  { '[WARN] ' }
        'Error' { '[ERROR]' }
        'Debug' { '[DEBUG]' }
    }

    $timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')

    # Build the bracketed context segment. Phase + Context merge into one block.
    $bracketParts = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($Phase)) {
        [void]$bracketParts.Add("phase=$Phase")
    }
    if ($Context -and $Context.Count -gt 0) {
        foreach ($key in ($Context.Keys | Sort-Object)) {
            $val = $Context[$key]
            if ($null -eq $val) { $val = '' }
            [void]$bracketParts.Add("$key=$val")
        }
    }

    $bracketSegment = ''
    if ($bracketParts.Count -gt 0) {
        $bracketSegment = ' [' + ($bracketParts -join ' ') + ']'
    }

    $line = "$timestamp $levelToken$bracketSegment $Message"

    # SECRET REDACTION (Constitutional C4 -- extend to file log).
    # Run on the assembled line so anything that snuck in via -Message or
    # -Context gets scrubbed before reaching disk.
    $line = Sanitize-VbrLogLine -Line $line

    try {
        Add-Content -LiteralPath $effectivePath -Value $line -Encoding utf8NoBOM -ErrorAction Stop
    } catch {
        # Logging must NEVER break the caller. Swallow IO errors silently.
        # The operator already has the underlying error in the call site.
    }
}

function Sanitize-VbrLogLine {
    <#
    .SYNOPSIS
        Scrub a formatted log line for bearer tokens, OAuth secrets, and the
        three credential-secret field names (password, passphrase, privateKey).

    .NOTES
        Internal helper for Write-VbrLog. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Line
    )

    if ([string]::IsNullOrEmpty($Line)) { return $Line }

    $out = $Line

    # Bearer <anything-non-whitespace> -- scrub the token value.
    $out = [regex]::Replace($out, '(?i)Bearer\s+[^\s,;]+', 'Bearer <redacted>')

    # Apply the same two-shape (JSON, then form/k=v) sweep to every secret-
    # bearing field name. JSON-shape MUST run first so the looser form rule
    # doesn't stop at the closing quote and leave the value intact.
    foreach ($field in @('access_token','password','passphrase','privateKey')) {
        $out = [regex]::Replace($out, '(?i)"' + $field + '"\s*:\s*"[^"]*"', '"' + $field + '":"<redacted>"')
        $out = [regex]::Replace($out, '(?i)' + $field + '\s*[:=]\s*[^"\s,;}&]+', $field + '=<redacted>')
    }

    return $out
}
