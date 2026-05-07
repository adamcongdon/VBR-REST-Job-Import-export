function Wait-VbrAutomationSession {
    <#
    .SYNOPSIS
        Polls a VBR Automation REST API import session until it reaches a
        terminal state.

    .DESCRIPTION
        Repeatedly GETs /api/v1/automation/sessions/{id} and inspects the
        'state' property:
            Working                       -- continue polling
            Succeeded                     -- return the session payload
            Failed | Stopped | Canceled   -- throw with payload attached

        If -TimeoutSeconds elapses before a terminal state is observed, a
        [System.TimeoutException] is thrown.

    .PARAMETER Token
        VbrToken from Get-VbrToken.

    .PARAMETER SessionId
        Session id returned by an Import-Vbr* function.

    .PARAMETER PollSeconds
        Seconds to sleep between polls. 1..60. Default 5.

    .PARAMETER TimeoutSeconds
        Maximum total time to wait. 10..86400. Default 1800 (30 min).

    .NOTES
        VMware vSphere primary backup jobs only. Other categories are not
        in scope of the Automation REST API.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Token,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SessionId,

        [Parameter()]
        [ValidateRange(1, 60)]
        [int] $PollSeconds = 5,

        # Plan recommended (10..86400); we widen to (1..86400) so callers and
        # tests can exercise short-deadline behavior. Production callers
        # should still pass >= 10s; values < 10s are intended for unit tests.
        [Parameter()]
        [ValidateRange(1, 86400)]
        [int] $TimeoutSeconds = 1800
    )

    $startUtc = [datetime]::UtcNow
    $deadline = $startUtc.AddSeconds($TimeoutSeconds)
    $path = "/api/v1/automation/sessions/$SessionId"
    $attempt = 0

    while ($true) {
        $session = Invoke-VbrApi -Token $Token -Method 'GET' -Path $path
        $attempt++

        # Validate the session payload has a 'state' property before reading
        # it. Without this, a malformed response would fall through to the
        # default branch and we would poll forever until -TimeoutSeconds.
        if (-not $session) {
            $err = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Wait-VbrAutomationSession: empty/null response from /api/v1/automation/sessions/$SessionId."),
                'VbrSessionInvalidPayload',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $session
            )
            $PSCmdlet.ThrowTerminatingError($err)
        }
        $hasState = $false
        if ($session.PSObject -and $session.PSObject.Properties) {
            $hasState = [bool]($session.PSObject.Properties.Name -contains 'state')
        }
        if (-not $hasState) {
            $err = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Wait-VbrAutomationSession: response for session $SessionId is missing the 'state' property."),
                'VbrSessionInvalidPayload',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $session
            )
            $PSCmdlet.ThrowTerminatingError($err)
        }

        $state = [string]$session.state

        $elapsedSec = [int]([datetime]::UtcNow - $startUtc).TotalSeconds
        Write-VbrLog -Level 'Debug' -Context @{
            session = $SessionId
            state   = $state
            attempt = $attempt
            elapsed = "${elapsedSec}s"
        } -Message ''

        switch ($state) {
            'Succeeded' { return $session }
            { $_ -in 'Failed','Stopped','Canceled' } {
                # Single branch handling all three terminal failure states.
                # Error id is suffixed with the state so callers can still
                # discriminate (VbrSessionTerminated.Failed / .Stopped / .Canceled).
                $details = ''
                if ($session.PSObject.Properties.Match('result').Count -and $session.result) {
                    if ($session.result.PSObject.Properties.Match('message').Count) {
                        $details = [string]$session.result.message
                    }
                }
                Write-VbrLog -Level 'Error' -Context @{
                    session = $SessionId
                    state   = $state
                    details = if ($details) { $details } else { '<none>' }
                } -Message ''
                $err = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("VBR session $SessionId terminated with state $state."),
                    "VbrSessionTerminated.$state",
                    [System.Management.Automation.ErrorCategory]::OperationStopped,
                    $session
                )
                $PSCmdlet.ThrowTerminatingError($err)
            }
            default {
                # Working / unknown -- keep polling.
                if ([datetime]::UtcNow -ge $deadline) {
                    Write-VbrLog -Level 'Error' -Context @{
                        session       = $SessionId
                        'timeout-after' = "${TimeoutSeconds}s"
                        last_state    = $state
                    } -Message ''
                    $msg = "Wait-VbrAutomationSession: timed out after ${TimeoutSeconds}s waiting for session $SessionId (last state: $state)."
                    $err = [System.Management.Automation.ErrorRecord]::new(
                        [System.TimeoutException]::new($msg),
                        'VbrSessionTimeout',
                        [System.Management.Automation.ErrorCategory]::OperationTimeout,
                        $session
                    )
                    $PSCmdlet.ThrowTerminatingError($err)
                }
                Start-Sleep -Seconds $PollSeconds
            }
        }
    }
}
