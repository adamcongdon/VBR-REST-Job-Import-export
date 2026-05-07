function Invoke-VbrImport {
    <#
    .SYNOPSIS
        Shared POST helper for the seven /api/v1/automation/{resource}/import
        endpoints.
    .DESCRIPTION
        POSTs $Spec as JSON (depth 50) to /api/v1/automation/$Resource/import
        via Invoke-VbrApi. Used by Import-VbrCredentials,
        Import-VbrCloudCredentials, Import-VbrEncryptionPasswords,
        Import-VbrManagedServers, Import-VbrRepositories, Import-VbrProxies,
        Import-VbrJobs.
    .PARAMETER Token
        VbrToken from Get-VbrToken.
    .PARAMETER Resource
        Resource path segment (e.g. 'credentials', 'cloudCredentials',
        'encryptionPasswords', 'managedServers', 'repositories', 'proxies',
        'jobs'). Inserted verbatim into the URL.
    .PARAMETER Spec
        Parsed export payload (typically the result of an Export-Vbr*
        function, possibly round-tripped through Read-VbrJsonFile).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [ValidateNotNull()] $Token,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Resource,
        [Parameter(Mandatory)] [ValidateNotNull()] [pscustomobject] $Spec
    )
    return Invoke-VbrApi -Token $Token -Method 'POST' -Path "/api/v1/automation/$Resource/import" -Body $Spec
}
