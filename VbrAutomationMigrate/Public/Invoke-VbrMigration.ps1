function Invoke-VbrMigration {
    <#
    .SYNOPSIS
        Orchestrates a VBR migration end-to-end OR runs only one of the two
        stages (export-only / resume-from-import) so an operator can manually
        verify and edit the exported JSON between stages.

    .DESCRIPTION
        The recommended workflow for production migrations is two-stage:

            Stage 1 (on a host that can reach the SOURCE VBR):
                Invoke-VbrMigration -ExportOnly ...
            -- exports the seven resources to JSON files in -WorkingDirectory,
               runs the empty-password check, and stops. No target token is
               requested. No imports run.

            -- The operator inspects the JSON files, populates every empty
               password / passphrase / privateKey field, and otherwise edits
               the files (e.g. retargeting mountServer.mountServerName in
               repositories.json).

            Stage 2 (on a host that can reach the TARGET VBR):
                Invoke-VbrMigration -ResumeFromImport ...
            -- reads the JSON files from -WorkingDirectory, re-runs the
               empty-password check (so any still-empty passwords are flagged
               again), then imports all seven resources in dependency order.

        The combined single-pass mode (no -ExportOnly, no -ResumeFromImport)
        is still supported for callers who already trust the export contents
        and want to skip the manual verification step. It is NOT the
        recommended path for production migrations.

        Single-pass workflow:
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

        -ExportOnly and -ResumeFromImport are mutually exclusive. They live
        in distinct PowerShell parameter sets, so the parser will reject any
        invocation that supplies both.

    .PARAMETER SourceBaseUri
        Source VBR server, e.g. https://src.example.com:9419
        Required for Full and ExportOnly. Not used by ResumeFromImport.

    .PARAMETER TargetBaseUri
        Target VBR server.
        Required for Full and ResumeFromImport. Not used by ExportOnly.

    .PARAMETER SourceCredential
        PSCredential for source OAuth password grant.
        Required for Full and ExportOnly. Not used by ResumeFromImport.

    .PARAMETER TargetCredential
        PSCredential for target OAuth password grant.
        Required for Full and ResumeFromImport. Not used by ExportOnly.

    .PARAMETER WorkingDirectory
        Filesystem directory to drop the seven export JSON files in (Stage 1)
        or read them from (Stage 2). Required in every parameter set.

    .PARAMETER SkipCertificateCheck
        Disable TLS verification on both source and target.

    .PARAMETER ExportOnly
        Stage-1 switch. When set, the function authenticates only to the
        source, exports the seven resources, persists JSON, runs the
        empty-password check, and returns. No target token is requested and
        no Import-Vbr* / Wait-VbrAutomationSession calls are made. Mutually
        exclusive with -ResumeFromImport (enforced by parameter sets).

    .PARAMETER ResumeFromImport
        Stage-2 switch. When set, the function reads the seven JSON files
        from -WorkingDirectory, runs the empty-password check, then imports
        all seven resources into the target VBR. No source authentication or
        export is performed. Mutually exclusive with -ExportOnly.

    .EXAMPLE
        # Recommended two-stage workflow:

        # Stage 1 -- run on a host that can reach the SOURCE VBR.
        $srcCred = Get-Credential -Message 'Source VBR admin'
        Invoke-VbrMigration -ExportOnly `
            -SourceBaseUri    'https://src-vbr.example.com:9419' `
            -SourceCredential $srcCred `
            -WorkingDirectory ./migration `
            -SkipCertificateCheck

        # Inspect ./migration/*.json. Populate every empty password /
        # passphrase / privateKey field. Retarget mountServer names if
        # needed. Verify the spec is what you expect on the target.

        # Stage 2 -- run on a host that can reach the TARGET VBR.
        $tgtCred = Get-Credential -Message 'Target VBR admin'
        Invoke-VbrMigration -ResumeFromImport `
            -TargetBaseUri    'https://tgt-vbr.example.com:9419' `
            -TargetCredential $tgtCred `
            -WorkingDirectory ./migration `
            -SkipCertificateCheck

    .EXAMPLE
        # Single-pass mode (NOT recommended for production migrations):
        Invoke-VbrMigration `
            -SourceBaseUri    'https://src:9419' `
            -TargetBaseUri    'https://tgt:9419' `
            -SourceCredential $srcCred `
            -TargetCredential $tgtCred `
            -WorkingDirectory ./migration `
            -SkipCertificateCheck

    .NOTES
        VBR Automation REST API only supports VMware vSphere primary backup
        jobs. Backup Copy, Hyper-V, Agent, NAS, Tape, Replication, SaaS,
        AHV, Proxmox, and oVirt jobs are silently dropped at export time and
        cannot be migrated by this orchestrator.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Full')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Full')]
        [Parameter(Mandatory, ParameterSetName = 'ExportOnly')]
        [ValidateNotNullOrEmpty()]
        [uri] $SourceBaseUri,

        [Parameter(Mandatory, ParameterSetName = 'Full')]
        [Parameter(Mandatory, ParameterSetName = 'ResumeFromImport')]
        [ValidateNotNullOrEmpty()]
        [uri] $TargetBaseUri,

        [Parameter(Mandatory, ParameterSetName = 'Full')]
        [Parameter(Mandatory, ParameterSetName = 'ExportOnly')]
        [ValidateNotNull()]
        [pscredential] $SourceCredential,

        [Parameter(Mandatory, ParameterSetName = 'Full')]
        [Parameter(Mandatory, ParameterSetName = 'ResumeFromImport')]
        [ValidateNotNull()]
        [pscredential] $TargetCredential,

        [Parameter(Mandatory, ParameterSetName = 'Full')]
        [Parameter(Mandatory, ParameterSetName = 'ExportOnly')]
        [Parameter(Mandatory, ParameterSetName = 'ResumeFromImport')]
        [ValidateNotNullOrEmpty()]
        [string] $WorkingDirectory,

        [Parameter(ParameterSetName = 'Full')]
        [Parameter(ParameterSetName = 'ExportOnly')]
        [Parameter(ParameterSetName = 'ResumeFromImport')]
        [switch] $SkipCertificateCheck,

        [Parameter(Mandatory, ParameterSetName = 'ExportOnly')]
        [switch] $ExportOnly,

        [Parameter(Mandatory, ParameterSetName = 'ResumeFromImport')]
        [switch] $ResumeFromImport,

        [Parameter(ParameterSetName = 'Full')]
        [Parameter(ParameterSetName = 'ExportOnly')]
        [Parameter(ParameterSetName = 'ResumeFromImport')]
        [string] $LogPath
    )

    if (-not (Test-Path -LiteralPath $WorkingDirectory)) {
        New-Item -ItemType Directory -Path $WorkingDirectory -Force | Out-Null
    }

    # ------------------------------------------------------------------
    # Resolve effective log path. Default: timestamped file under
    # WorkingDirectory. Sentinel: '/dev/null' disables file logging.
    # The path is wired to module-level state so all helper functions
    # (Invoke-VbrApi, Wait-VbrAutomationSession, Test-VbrCredentialPasswords)
    # write into the same file without each having to know the path.
    # ------------------------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        $LogPath = Join-Path $WorkingDirectory ('vbr-migration-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
    }
    $script:VbrLogPath = $LogPath
    $orchStartUtc = [datetime]::UtcNow

    $resources = @(
        [pscustomobject]@{ Key = 'credentials';         File = 'credentials.json';         Export = 'Export-VbrCredentials';        Import = 'Import-VbrCredentials'        }
        [pscustomobject]@{ Key = 'cloudCredentials';    File = 'cloudCredentials.json';    Export = 'Export-VbrCloudCredentials';   Import = 'Import-VbrCloudCredentials'   }
        [pscustomobject]@{ Key = 'encryptionPasswords'; File = 'encryptionPasswords.json'; Export = 'Export-VbrEncryptionPasswords';Import = 'Import-VbrEncryptionPasswords'}
        [pscustomobject]@{ Key = 'managedServers';      File = 'managedServers.json';      Export = 'Export-VbrManagedServers';     Import = 'Import-VbrManagedServers'     }
        [pscustomobject]@{ Key = 'repositories';        File = 'repositories.json';        Export = 'Export-VbrRepositories';       Import = 'Import-VbrRepositories'       }
        [pscustomobject]@{ Key = 'proxies';             File = 'proxies.json';             Export = 'Export-VbrProxies';            Import = 'Import-VbrProxies'            }
        [pscustomobject]@{ Key = 'jobs';                File = 'jobs.json';                Export = 'Export-VbrJobs';               Import = 'Import-VbrJobs'               }
    )

    $exports      = @{}
    $writtenFiles = [System.Collections.Generic.List[string]]::new()
    $setName      = $PSCmdlet.ParameterSetName

    try {
        if ($setName -ne 'ResumeFromImport') {
            Write-Verbose ('Invoke-VbrMigration: requesting source token from {0}' -f $SourceBaseUri.AbsoluteUri)
            Write-VbrLog -Level 'Info' -Phase 'auth-source' -Context @{ uri = $SourceBaseUri.AbsoluteUri } -Message 'Requesting source token'
            try {
                $srcToken = Get-VbrToken -BaseUri $SourceBaseUri -Credential $SourceCredential -SkipCertificateCheck:$SkipCertificateCheck
            } catch {
                Write-VbrLog -Level 'Error' -Phase 'auth-source' -Context @{
                    uri   = $SourceBaseUri.AbsoluteUri
                    error = ([string]$_.Exception.Message)
                } -Message 'Get-VbrToken failed'
                throw
            }
            if (-not $srcToken) {
                $msg = "Invoke-VbrMigration: Get-VbrToken returned null for source $($SourceBaseUri.AbsoluteUri)."
                Write-VbrLog -Level 'Error' -Phase 'auth-source' -Context @{ uri = $SourceBaseUri.AbsoluteUri } -Message $msg
                throw $msg
            }

            # IMPORTANT: ordering is constitutional -- credentials first, jobs last.
            # The $resources table above is the single source of truth: each row
            # carries Key + File + Export-command-name + Import-command-name. We
            # dispatch each Export-Vbr* via the call operator (&) so the dispatch
            # table never duplicates the function names.
            foreach ($res in $resources) {
                Write-VbrLog -Level 'Info' -Phase 'export-source' -Context @{ resource = $res.Key } -Message 'Exporting resource'
                $exports[$res.Key] = & $res.Export -Token $srcToken
            }

            foreach ($res in $resources) {
                $path = Join-Path $WorkingDirectory $res.File
                Write-VbrJsonFile -InputObject $exports[$res.Key] -Path $path
                [void]$writtenFiles.Add($path)
                $sz = 0
                try { $sz = (Get-Item -LiteralPath $path -ErrorAction Stop).Length } catch { $sz = 0 }
                Write-VbrLog -Level 'Info' -Phase 'persist' -Context @{ file = $path; bytes = $sz } -Message 'Persisted export'
            }
        } else {
            foreach ($res in $resources) {
                $path = Join-Path $WorkingDirectory $res.File
                Write-Verbose ('Invoke-VbrMigration: resuming -- reading {0}' -f $path)
                Write-VbrLog -Level 'Info' -Phase 'resume-read' -Context @{ file = $path } -Message 'Reading export from disk'
                $exports[$res.Key] = Read-VbrJsonFile -Path $path
            }
        }

        # Empty-password check -- warn but do NOT throw. Runs in every mode so
        # operators see the warning whether they're staging an export, resuming
        # an import, or single-passing.
        if ($exports.ContainsKey('credentials') -and $exports['credentials']) {
            [void](Test-VbrCredentialPasswords -Spec $exports['credentials'])
        }

        if ($setName -eq 'ExportOnly') {
            # Stage-1 stop: contract is "no target auth, no imports". Return the
            # export manifest so the caller can drive verification tooling.
            $elapsed = [int]([datetime]::UtcNow - $orchStartUtc).TotalSeconds
            Write-VbrLog -Level 'Info' -Phase 'complete' -Context @{ duration = "${elapsed}s"; mode = 'ExportOnly' } -Message 'Migration export-only complete'
            return [pscustomobject]@{
                SourceBaseUri    = $SourceBaseUri
                WorkingDirectory = $WorkingDirectory
                Files            = $writtenFiles.ToArray()
                Sessions         = $null
                LogPath          = $LogPath
            }
        }

        Write-Verbose ('Invoke-VbrMigration: requesting target token from {0}' -f $TargetBaseUri.AbsoluteUri)
        Write-VbrLog -Level 'Info' -Phase 'auth-target' -Context @{ uri = $TargetBaseUri.AbsoluteUri } -Message 'Requesting target token'
        try {
            $tgtToken = Get-VbrToken -BaseUri $TargetBaseUri -Credential $TargetCredential -SkipCertificateCheck:$SkipCertificateCheck
        } catch {
            Write-VbrLog -Level 'Error' -Phase 'auth-target' -Context @{
                uri   = $TargetBaseUri.AbsoluteUri
                error = ([string]$_.Exception.Message)
            } -Message 'Get-VbrToken failed'
            throw
        }
        # If $tgtToken is $null (rather than thrown), the foreach below would
        # produce 7 cascading "Token is null" errors that bury the real cause.
        # Validate up front and throw a single message naming the target URI.
        if (-not $tgtToken) {
            $msg = "Invoke-VbrMigration: Get-VbrToken returned null for target $($TargetBaseUri.AbsoluteUri)."
            Write-VbrLog -Level 'Error' -Phase 'auth-target' -Context @{ uri = $TargetBaseUri.AbsoluteUri } -Message $msg
            throw $msg
        }

        $sessionResults = @{}

        # The $resources table already declares the import order and the
        # Import-Vbr* command name for each row. Dispatch via the call operator
        # so we never have to repeat the function names.
        foreach ($res in $resources) {
            $key  = $res.Key
            $spec = $exports[$key]
            Write-Verbose ('Invoke-VbrMigration: importing {0}' -f $key)
            Write-VbrLog -Level 'Info' -Phase 'import-target' -Context @{ resource = $key } -Message 'Importing resource'

            $session = & $res.Import -Token $tgtToken -Spec $spec

            if (-not $session -or -not $session.id) {
                throw ('Invoke-VbrMigration: {0} did not return a session id.' -f $res.Import)
            }

            # Halt on first failure -- Wait-VbrAutomationSession throws on Failed/Stopped/Canceled.
            $finalSession = Wait-VbrAutomationSession -Token $tgtToken -SessionId $session.id
            $sessionResults[$key] = $finalSession
        }

        $elapsed = [int]([datetime]::UtcNow - $orchStartUtc).TotalSeconds
        Write-VbrLog -Level 'Info' -Phase 'complete' -Context @{ duration = "${elapsed}s" } -Message 'Migration complete'

        return [pscustomobject]@{
            SourceBaseUri    = $SourceBaseUri
            TargetBaseUri    = $TargetBaseUri
            WorkingDirectory = $WorkingDirectory
            Sessions         = $sessionResults
            LogPath          = $LogPath
        }
    }
    finally {
        # Always clear module-level log state so subsequent direct calls to
        # Export-Vbr* / Import-Vbr* don't accidentally write to a stale path.
        $script:VbrLogPath = $null
    }
}
