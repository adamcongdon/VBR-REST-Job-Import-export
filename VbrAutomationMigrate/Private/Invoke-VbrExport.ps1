function Invoke-VbrExport {
    <#
    .SYNOPSIS
        Shared POST helper for the seven /api/v1/automation/{resource}/export
        endpoints.
    .DESCRIPTION
        Builds the standard {"names":[...]} body and POSTs it to
        /api/v1/automation/$Resource/export via Invoke-VbrApi. Used by
        Export-VbrCredentials, Export-VbrCloudCredentials,
        Export-VbrEncryptionPasswords, Export-VbrManagedServers,
        Export-VbrRepositories, Export-VbrProxies, Export-VbrJobs.
    .PARAMETER Token
        VbrToken from Get-VbrToken.
    .PARAMETER Resource
        Resource path segment (e.g. 'credentials', 'cloudCredentials',
        'encryptionPasswords', 'managedServers', 'repositories', 'proxies',
        'jobs'). Inserted verbatim into the URL.
    .PARAMETER Names
        Optional name filter. Defaults to empty (export everything).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [ValidateNotNull()] $Token,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Resource,
        [Parameter()] [AllowEmptyCollection()] [string[]] $Names = @()
    )
    $body = [pscustomobject]@{ names = @($Names) }
    return Invoke-VbrApi -Token $Token -Method 'POST' -Path "/api/v1/automation/$Resource/export" -Body $body
}
