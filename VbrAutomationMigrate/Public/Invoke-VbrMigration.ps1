function Invoke-VbrMigration {
    <#
    .SYNOPSIS
        Orchestrates an end-to-end VBR migration: exports all seven resource
        types from the source server, then imports them into the target
        server in dependency order.

    .DESCRIPTION
        Workflow:
            1. Get-VbrToken on source.
            2. Export all 7 resources from source (Credentials,
               CloudCredentials, EncryptionPasswords, ManagedServers,
               Repositories, Proxies, Jobs).
            3. Persist exports to -WorkingDirectory as UTF-8 (no BOM) JSON.
            4. Test-VbrCredentialPasswords on the credentials export and
               emit Write-Warning per affected name. Migration continues.
            5. Get-VbrToken on target.
            6. Import all 7 resources into target IN ORDER:
               Credentials -> CloudCredentials -> EncryptionPasswords ->
               ManagedServers -> Repositories -> Proxies -> Jobs.
               After each Import-Vbr* call, Wait-VbrAutomationSession on the
               returned session id. Halt on first failure.

    .PARAMETER SourceBaseUri
        Source VBR server, e.g. https://src.example.com:9419

    .PARAMETER TargetBaseUri
        Target VBR server.

    .PARAMETER SourceCredential
        PSCredential for source OAuth password grant.

    .PARAMETER TargetCredential
        PSCredential for target OAuth password grant.

    .PARAMETER WorkingDirectory
        Filesystem directory to drop the seven export JSON files in.

    .PARAMETER SkipCertificateCheck
        Disable TLS verification on both source and target.

    .PARAMETER ResumeFromImport
        If set, skip the export phase and read existing JSON files from
        -WorkingDirectory.

    .NOTES
        VBR Automation REST API only supports VMware vSphere primary backup
        jobs. Backup Copy, Hyper-V, Agent, NAS, Tape, Replication, SaaS,
        AHV, Proxmox, and oVirt jobs are silently dropped at export time and
        cannot be migrated by this orchestrator.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [uri] $SourceBaseUri,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [uri] $TargetBaseUri,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [pscredential] $SourceCredential,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [pscredential] $TargetCredential,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $WorkingDirectory,

        [Parameter()]
        [switch] $SkipCertificateCheck,

        [Parameter()]
        [switch] $ResumeFromImport
    )

    if (-not (Test-Path -LiteralPath $WorkingDirectory)) {
        New-Item -ItemType Directory -Path $WorkingDirectory -Force | Out-Null
    }

    $resources = @(
        [pscustomobject]@{ Key = 'credentials';         File = 'credentials.json';         Export = 'Export-VbrCredentials';        Import = 'Import-VbrCredentials'        }
        [pscustomobject]@{ Key = 'cloudCredentials';    File = 'cloudCredentials.json';    Export = 'Export-VbrCloudCredentials';   Import = 'Import-VbrCloudCredentials'   }
        [pscustomobject]@{ Key = 'encryptionPasswords'; File = 'encryptionPasswords.json'; Export = 'Export-VbrEncryptionPasswords';Import = 'Import-VbrEncryptionPasswords'}
        [pscustomobject]@{ Key = 'managedServers';      File = 'managedServers.json';      Export = 'Export-VbrManagedServers';     Import = 'Import-VbrManagedServers'     }
        [pscustomobject]@{ Key = 'repositories';        File = 'repositories.json';        Export = 'Export-VbrRepositories';       Import = 'Import-VbrRepositories'       }
        [pscustomobject]@{ Key = 'proxies';             File = 'proxies.json';             Export = 'Export-VbrProxies';            Import = 'Import-VbrProxies'            }
        [pscustomobject]@{ Key = 'jobs';                File = 'jobs.json';                Export = 'Export-VbrJobs';               Import = 'Import-VbrJobs'               }
    )

    $exports = @{}

    if (-not $ResumeFromImport) {
        Write-Verbose ('Invoke-VbrMigration: requesting source token from {0}' -f $SourceBaseUri.AbsoluteUri)
        $srcToken = Get-VbrToken -BaseUri $SourceBaseUri -Credential $SourceCredential -SkipCertificateCheck:$SkipCertificateCheck

        # IMPORTANT: ordering is constitutional -- credentials first, jobs last.
        # The $resources table above is the single source of truth: each row
        # carries Key + File + Export-command-name + Import-command-name. We
        # dispatch each Export-Vbr* via the call operator (&) so the dispatch
        # table never duplicates the function names.
        foreach ($res in $resources) {
            $exports[$res.Key] = & $res.Export -Token $srcToken
        }

        foreach ($res in $resources) {
            Write-VbrJsonFile -InputObject $exports[$res.Key] -Path (Join-Path $WorkingDirectory $res.File)
        }
    } else {
        foreach ($res in $resources) {
            $path = Join-Path $WorkingDirectory $res.File
            Write-Verbose ('Invoke-VbrMigration: resuming -- reading {0}' -f $path)
            $exports[$res.Key] = Read-VbrJsonFile -Path $path
        }
    }

    # Empty-password check -- warn but do NOT throw.
    if ($exports.ContainsKey('credentials') -and $exports['credentials']) {
        [void](Test-VbrCredentialPasswords -Spec $exports['credentials'])
    }

    Write-Verbose ('Invoke-VbrMigration: requesting target token from {0}' -f $TargetBaseUri.AbsoluteUri)
    $tgtToken = Get-VbrToken -BaseUri $TargetBaseUri -Credential $TargetCredential -SkipCertificateCheck:$SkipCertificateCheck

    $sessionResults = @{}

    # The $resources table already declares the import order and the
    # Import-Vbr* command name for each row. Dispatch via the call operator
    # so we never have to repeat the function names.
    foreach ($res in $resources) {
        $key  = $res.Key
        $spec = $exports[$key]
        Write-Verbose ('Invoke-VbrMigration: importing {0}' -f $key)

        $session = & $res.Import -Token $tgtToken -Spec $spec

        if (-not $session -or -not $session.id) {
            throw ('Invoke-VbrMigration: {0} did not return a session id.' -f $res.Import)
        }

        # Halt on first failure -- Wait-VbrAutomationSession throws on Failed/Stopped/Canceled.
        $finalSession = Wait-VbrAutomationSession -Token $tgtToken -SessionId $session.id
        $sessionResults[$key] = $finalSession
    }

    return [pscustomobject]@{
        SourceBaseUri    = $SourceBaseUri
        TargetBaseUri    = $TargetBaseUri
        WorkingDirectory = $WorkingDirectory
        Sessions         = $sessionResults
    }
}
