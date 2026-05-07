function Import-VbrManagedServers {
    <#
    .SYNOPSIS
        Imports VBR managed-server registrations from a previously-exported spec.
    .DESCRIPTION
        POSTs the supplied -Spec object as JSON (depth 50) to
        /api/v1/automation/managedServers/import.
    .PARAMETER Token
        VbrToken from Get-VbrToken.
    .PARAMETER Spec
        Parsed export payload from Export-VbrManagedServers.
    .NOTES
        VMware vSphere primary backup jobs only.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [ValidateNotNull()] $Token,
        [Parameter(Mandatory)] [ValidateNotNull()] [pscustomobject] $Spec
    )
    return Invoke-VbrImport -Token $Token -Resource 'managedServers' -Spec $Spec
}
