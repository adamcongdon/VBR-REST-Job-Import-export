function Import-VbrCredentials {
    <#
    .SYNOPSIS
        Imports VBR credentials from a previously-exported spec.
    .DESCRIPTION
        POSTs the supplied -Spec object as JSON (depth 50) to
        /api/v1/automation/credentials/import. Returns the session object
        whose .id can be passed to Wait-VbrAutomationSession.
    .PARAMETER Token
        VbrToken from Get-VbrToken.
    .PARAMETER Spec
        Parsed export payload (typically the result of Export-VbrCredentials,
        possibly round-tripped through Read-VbrJsonFile).
    .NOTES
        VMware vSphere primary backup jobs only. Other categories are not
        in scope of the Automation REST API.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [ValidateNotNull()] $Token,
        [Parameter(Mandatory)] [ValidateNotNull()] [pscustomobject] $Spec
    )
    return Invoke-VbrImport -Token $Token -Resource 'credentials' -Spec $Spec
}
