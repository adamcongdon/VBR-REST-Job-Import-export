function Export-VbrCredentials {
    <#
    .SYNOPSIS
        Exports VBR Credentials configuration via the Automation REST API.

    .DESCRIPTION
        POSTs to /api/v1/automation/credentials/export with body {"names":[]}
        (or {"names":["a","b"]} when -Names is supplied) and returns the
        parsed export payload as a PSCustomObject.

    .PARAMETER Token
        VbrToken from Get-VbrToken.

    .PARAMETER Names
        Optional array of credential names to filter the export. Defaults to
        an empty array (export everything).

    .NOTES
        VBR Automation REST API only supports VMware vSphere primary backup
        jobs. Non-VMware credential entries may not round-trip cleanly.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Token,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $Names = @()
    )

    return Invoke-VbrExport -Token $Token -Resource 'credentials' -Names $Names
}
