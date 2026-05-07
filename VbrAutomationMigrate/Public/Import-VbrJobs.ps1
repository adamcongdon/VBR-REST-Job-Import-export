function Import-VbrJobs {
    <#
    .SYNOPSIS
        Imports VBR backup jobs from a previously-exported spec.
    .DESCRIPTION
        POSTs the supplied -Spec object as JSON (depth 50) to
        /api/v1/automation/jobs/import.
    .PARAMETER Token
        VbrToken from Get-VbrToken.
    .PARAMETER Spec
        Parsed export payload from Export-VbrJobs.
    .NOTES
        VBR Automation REST API only supports VMware vSphere primary backup
        jobs. Backup Copy, Hyper-V, Agent, NAS, Tape, Replication, SaaS,
        AHV, Proxmox, and oVirt jobs cannot be represented in the spec.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [ValidateNotNull()] $Token,
        [Parameter(Mandatory)] [ValidateNotNull()] [pscustomobject] $Spec
    )
    return Invoke-VbrImport -Token $Token -Resource 'jobs' -Spec $Spec
}
