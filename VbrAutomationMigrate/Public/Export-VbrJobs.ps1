function Export-VbrJobs {
    <#
    .SYNOPSIS
        Exports VBR backup-job specs via the Automation REST API.
    .DESCRIPTION
        POSTs to /api/v1/automation/jobs/export with body {"names":[]}
        (or {"names":["a","b"]} when -Names is supplied).

        IMPORTANT: the body field is "names" -- NOT "jobIds". The legacy
        scripts sent {"jobIds":[]} which the v13 API silently ignores
        and returns an empty export.
    .PARAMETER Token
        VbrToken from Get-VbrToken.
    .PARAMETER Names
        Optional job-name filter. Default empty (export all VMware jobs).
    .NOTES
        VBR Automation REST API only supports VMware vSphere primary backup
        jobs. Backup Copy, Hyper-V, Agent, NAS, Tape, Replication, SaaS,
        AHV, Proxmox, and oVirt jobs will not appear in the export.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [ValidateNotNull()] $Token,
        [Parameter()] [AllowEmptyCollection()] [string[]] $Names = @()
    )
    return Invoke-VbrExport -Token $Token -Resource 'jobs' -Names $Names
}
