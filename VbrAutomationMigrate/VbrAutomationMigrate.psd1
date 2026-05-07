@{
    RootModule        = 'VbrAutomationMigrate.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a1b2c3d4-e5f6-7890-1234-567890abcdef'
    Author            = 'Veeam Backup REST migration tooling'
    CompanyName       = 'Community'
    Copyright         = '(c) Community contributors. Licensed under MIT.'
    Description       = 'Cross-platform PowerShell module that migrates VMware backup jobs between Veeam Backup & Replication v13 servers via the Automation REST API (1.3-rev1).'
    PowerShellVersion = '7.4'
    FunctionsToExport = @(
        'Get-VbrToken',
        'Export-VbrCredentials',
        'Export-VbrCloudCredentials',
        'Export-VbrEncryptionPasswords',
        'Export-VbrManagedServers',
        'Export-VbrRepositories',
        'Export-VbrProxies',
        'Export-VbrJobs',
        'Import-VbrCredentials',
        'Import-VbrCloudCredentials',
        'Import-VbrEncryptionPasswords',
        'Import-VbrManagedServers',
        'Import-VbrRepositories',
        'Import-VbrProxies',
        'Import-VbrJobs',
        'Wait-VbrAutomationSession',
        'Test-VbrCredentialPasswords',
        'Invoke-VbrMigration'
    )
    CmdletsToExport   = @()
    AliasesToExport   = @()
    VariablesToExport = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('Veeam', 'VBR', 'Backup', 'REST', 'Migration', 'VMware')
            ProjectUri   = 'https://github.com/example/VBR-REST-Job-Import-export'
            ReleaseNotes = 'Initial v13.0.1 / 1.3-rev1 release. Replaces legacy curl-based scripts.'
        }
    }
}
