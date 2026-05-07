function Import-VbrRepositories {
    <#
    .SYNOPSIS
        Imports VBR repositories from a previously-exported spec.
    .DESCRIPTION
        POSTs the supplied -Spec object as JSON (depth 50) to
        /api/v1/automation/repositories/import.
    .PARAMETER Token
        VbrToken from Get-VbrToken.
    .PARAMETER Spec
        Parsed export payload from Export-VbrRepositories.
    .NOTES
        VMware vSphere primary backup jobs only.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [ValidateNotNull()] $Token,
        [Parameter(Mandatory)] [ValidateNotNull()] [pscustomobject] $Spec
    )
    return Invoke-VbrImport -Token $Token -Resource 'repositories' -Spec $Spec
}
