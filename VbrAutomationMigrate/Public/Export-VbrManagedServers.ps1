function Export-VbrManagedServers {
    <#
    .SYNOPSIS
        Exports VBR managed-server registrations via the Automation REST API.
    .DESCRIPTION
        POSTs to /api/v1/automation/managedServers/export with body
        {"names":[]} (or {"names":["a","b"]} when -Names is supplied).
    .PARAMETER Token
        VbrToken from Get-VbrToken.
    .PARAMETER Names
        Optional name filter. Default empty (export all).
    .NOTES
        VMware vSphere primary backup jobs only. Other categories are not
        in scope of the Automation REST API.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [ValidateNotNull()] $Token,
        [Parameter()] [AllowEmptyCollection()] [string[]] $Names = @()
    )
    return Invoke-VbrExport -Token $Token -Resource 'managedServers' -Names $Names
}
