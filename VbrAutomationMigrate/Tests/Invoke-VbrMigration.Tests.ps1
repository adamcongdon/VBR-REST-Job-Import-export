BeforeAll {
    . (Join-Path $PSScriptRoot '_Setup.ps1')
    . (Join-Path $PSScriptRoot '_TestHelpers.ps1')
}

Describe 'Invoke-VbrMigration' {

    BeforeEach {
        $script:callOrder = New-Object System.Collections.Generic.List[string]

        # Mock Get-VbrToken to skip real network round-trips.
        Mock -ModuleName VbrAutomationMigrate -CommandName Get-VbrToken -MockWith {
            param([uri]$BaseUri, [pscredential]$Credential, [switch]$SkipCertificateCheck)
            return New-FakeVbrToken -BaseUri $BaseUri
        }

        # Each Export-Vbr* returns a non-empty spec with deeply-nested data.
        $sampleExport = New-DeepFakeExportResponse
        Mock -ModuleName VbrAutomationMigrate -CommandName Export-VbrCredentials       -MockWith { $script:callOrder.Add('Export-Credentials')      | Out-Null; $sampleExport }
        Mock -ModuleName VbrAutomationMigrate -CommandName Export-VbrCloudCredentials  -MockWith { $script:callOrder.Add('Export-CloudCredentials') | Out-Null; $sampleExport }
        Mock -ModuleName VbrAutomationMigrate -CommandName Export-VbrEncryptionPasswords -MockWith { $script:callOrder.Add('Export-EncryptionPasswords') | Out-Null; $sampleExport }
        Mock -ModuleName VbrAutomationMigrate -CommandName Export-VbrManagedServers    -MockWith { $script:callOrder.Add('Export-ManagedServers')   | Out-Null; $sampleExport }
        Mock -ModuleName VbrAutomationMigrate -CommandName Export-VbrRepositories      -MockWith { $script:callOrder.Add('Export-Repositories')    | Out-Null; $sampleExport }
        Mock -ModuleName VbrAutomationMigrate -CommandName Export-VbrProxies           -MockWith { $script:callOrder.Add('Export-Proxies')         | Out-Null; $sampleExport }
        Mock -ModuleName VbrAutomationMigrate -CommandName Export-VbrJobs              -MockWith { $script:callOrder.Add('Export-Jobs')            | Out-Null; $sampleExport }

        # Each Import-Vbr* returns a session id; orchestrator should call Wait-VbrAutomationSession on it.
        Mock -ModuleName VbrAutomationMigrate -CommandName Import-VbrCredentials       -MockWith { $script:callOrder.Add('Import-Credentials')      | Out-Null; [pscustomobject]@{ id = 'sess-cred' } }
        Mock -ModuleName VbrAutomationMigrate -CommandName Import-VbrCloudCredentials  -MockWith { $script:callOrder.Add('Import-CloudCredentials') | Out-Null; [pscustomobject]@{ id = 'sess-cc' } }
        Mock -ModuleName VbrAutomationMigrate -CommandName Import-VbrEncryptionPasswords -MockWith { $script:callOrder.Add('Import-EncryptionPasswords') | Out-Null; [pscustomobject]@{ id = 'sess-ep' } }
        Mock -ModuleName VbrAutomationMigrate -CommandName Import-VbrManagedServers    -MockWith { $script:callOrder.Add('Import-ManagedServers')   | Out-Null; [pscustomobject]@{ id = 'sess-ms' } }
        Mock -ModuleName VbrAutomationMigrate -CommandName Import-VbrRepositories      -MockWith { $script:callOrder.Add('Import-Repositories')    | Out-Null; [pscustomobject]@{ id = 'sess-repo' } }
        Mock -ModuleName VbrAutomationMigrate -CommandName Import-VbrProxies           -MockWith { $script:callOrder.Add('Import-Proxies')         | Out-Null; [pscustomobject]@{ id = 'sess-prx' } }
        Mock -ModuleName VbrAutomationMigrate -CommandName Import-VbrJobs              -MockWith { $script:callOrder.Add('Import-Jobs')            | Out-Null; [pscustomobject]@{ id = 'sess-job' } }

        Mock -ModuleName VbrAutomationMigrate -CommandName Wait-VbrAutomationSession   -MockWith {
            param($Token, [string]$SessionId, [int]$PollSeconds, [int]$TimeoutSeconds)
            $script:callOrder.Add("Wait-$SessionId") | Out-Null
            return [pscustomobject]@{ id = $SessionId; state = 'Succeeded' }
        }

        $script:tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("vbrmig-" + [guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $script:tmpDir | Out-Null

        $sec = ConvertTo-SecureString 'pw' -AsPlainText -Force
        $script:srcCred = [pscredential]::new('lab\src', $sec)
        $script:tgtCred = [pscredential]::new('lab\tgt', $sec)
    }

    AfterEach {
        if (Test-Path $script:tmpDir) {
            Remove-Item -LiteralPath $script:tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'orchestration order' {

        BeforeEach {
            $null = Invoke-VbrMigration `
                -SourceBaseUri 'https://src.test:9419' `
                -TargetBaseUri 'https://tgt.test:9419' `
                -SourceCredential $script:srcCred `
                -TargetCredential $script:tgtCred `
                -WorkingDirectory $script:tmpDir `
                -SkipCertificateCheck
        }

        It 'imports credentials before cloud credentials' {
            $idx1 = $script:callOrder.IndexOf('Import-Credentials')
            $idx2 = $script:callOrder.IndexOf('Import-CloudCredentials')
            $idx1 | Should -BeGreaterOrEqual 0
            $idx2 | Should -BeGreaterOrEqual 0
            $idx1 | Should -BeLessThan $idx2
        }
        It 'imports cloud credentials before encryption passwords' {
            $idx1 = $script:callOrder.IndexOf('Import-CloudCredentials')
            $idx2 = $script:callOrder.IndexOf('Import-EncryptionPasswords')
            $idx1 | Should -BeLessThan $idx2
        }
        It 'imports encryption passwords before managed servers' {
            $idx1 = $script:callOrder.IndexOf('Import-EncryptionPasswords')
            $idx2 = $script:callOrder.IndexOf('Import-ManagedServers')
            $idx1 | Should -BeLessThan $idx2
        }
        It 'imports managed servers before repositories' {
            $idx1 = $script:callOrder.IndexOf('Import-ManagedServers')
            $idx2 = $script:callOrder.IndexOf('Import-Repositories')
            $idx1 | Should -BeLessThan $idx2
        }
        It 'imports repositories before proxies' {
            $idx1 = $script:callOrder.IndexOf('Import-Repositories')
            $idx2 = $script:callOrder.IndexOf('Import-Proxies')
            $idx1 | Should -BeLessThan $idx2
        }
        It 'imports proxies before jobs' {
            $idx1 = $script:callOrder.IndexOf('Import-Proxies')
            $idx2 = $script:callOrder.IndexOf('Import-Jobs')
            $idx1 | Should -BeLessThan $idx2
        }
    }

    Context 'failure handling' {

        It 'halts after a failed credentials import (does not attempt managed servers)' {
            Mock -ModuleName VbrAutomationMigrate -CommandName Wait-VbrAutomationSession -MockWith {
                param($Token, [string]$SessionId)
                $script:callOrder.Add("Wait-$SessionId") | Out-Null
                if ($SessionId -eq 'sess-cred') {
                    $rec = [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("VBR session $SessionId terminated with state Failed."),
                        'VbrSessionFailed',
                        [System.Management.Automation.ErrorCategory]::OperationStopped,
                        [pscustomobject]@{ id = $SessionId; state = 'Failed' }
                    )
                    throw $rec
                }
                return [pscustomobject]@{ id = $SessionId; state = 'Succeeded' }
            }

            { Invoke-VbrMigration `
                -SourceBaseUri 'https://src.test:9419' `
                -TargetBaseUri 'https://tgt.test:9419' `
                -SourceCredential $script:srcCred `
                -TargetCredential $script:tgtCred `
                -WorkingDirectory $script:tmpDir `
                -SkipCertificateCheck } | Should -Throw

            Should -Invoke -ModuleName VbrAutomationMigrate -CommandName Import-VbrManagedServers -Times 0 -Exactly
        }

        It 'halts after a failed managed-servers import (does not attempt repositories)' {
            Mock -ModuleName VbrAutomationMigrate -CommandName Wait-VbrAutomationSession -MockWith {
                param($Token, [string]$SessionId)
                $script:callOrder.Add("Wait-$SessionId") | Out-Null
                if ($SessionId -eq 'sess-ms') {
                    $rec = [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("VBR session $SessionId terminated with state Failed."),
                        'VbrSessionFailed',
                        [System.Management.Automation.ErrorCategory]::OperationStopped,
                        [pscustomobject]@{ id = $SessionId; state = 'Failed' }
                    )
                    throw $rec
                }
                return [pscustomobject]@{ id = $SessionId; state = 'Succeeded' }
            }

            { Invoke-VbrMigration `
                -SourceBaseUri 'https://src.test:9419' `
                -TargetBaseUri 'https://tgt.test:9419' `
                -SourceCredential $script:srcCred `
                -TargetCredential $script:tgtCred `
                -WorkingDirectory $script:tmpDir `
                -SkipCertificateCheck } | Should -Throw

            Should -Invoke -ModuleName VbrAutomationMigrate -CommandName Import-VbrRepositories -Times 0 -Exactly
        }

        It 'surfaces the underlying session error in the thrown exception' {
            Mock -ModuleName VbrAutomationMigrate -CommandName Wait-VbrAutomationSession -MockWith {
                param($Token, [string]$SessionId)
                if ($SessionId -eq 'sess-cred') {
                    $rec = [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("VBR session $SessionId terminated with state Failed."),
                        'VbrSessionFailed',
                        [System.Management.Automation.ErrorCategory]::OperationStopped,
                        [pscustomobject]@{ id = $SessionId; state = 'Failed' }
                    )
                    throw $rec
                }
                return [pscustomobject]@{ id = $SessionId; state = 'Succeeded' }
            }

            $err = $null
            try {
                Invoke-VbrMigration `
                    -SourceBaseUri 'https://src.test:9419' `
                    -TargetBaseUri 'https://tgt.test:9419' `
                    -SourceCredential $script:srcCred `
                    -TargetCredential $script:tgtCred `
                    -WorkingDirectory $script:tmpDir `
                    -SkipCertificateCheck
            } catch { $err = $_ }
            $err | Should -Not -BeNullOrEmpty
            $err.Exception.Message | Should -Match 'Failed'
        }
    }

    Context 'empty-password warning' {

        BeforeEach {
            # Override Export-VbrCredentials so it returns a spec whose first
            # credential has a populated password and the second has empty.
            Mock -ModuleName VbrAutomationMigrate -CommandName Export-VbrCredentials -MockWith {
                $script:callOrder.Add('Export-Credentials') | Out-Null
                return [pscustomobject]@{
                    items = @(
                        [pscustomobject]@{ name = 'cred-with-pw'; password = 'set' }
                        [pscustomobject]@{ name = 'cred-empty1'; password = '' }
                        [pscustomobject]@{ name = 'cred-empty2'; password = ''; passphrase = ''; privateKey = '' }
                    )
                }
            }
        }

        It 'emits Write-Warning when credential export contains an empty password field' {
            $warnings = & {
                Invoke-VbrMigration `
                    -SourceBaseUri 'https://src.test:9419' `
                    -TargetBaseUri 'https://tgt.test:9419' `
                    -SourceCredential $script:srcCred `
                    -TargetCredential $script:tgtCred `
                    -WorkingDirectory $script:tmpDir `
                    -SkipCertificateCheck 3>&1
            } | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
            $warnings.Count | Should -BeGreaterOrEqual 1
        }

        It 'lists the affected credential names in the warning' {
            $warnings = & {
                Invoke-VbrMigration `
                    -SourceBaseUri 'https://src.test:9419' `
                    -TargetBaseUri 'https://tgt.test:9419' `
                    -SourceCredential $script:srcCred `
                    -TargetCredential $script:tgtCred `
                    -WorkingDirectory $script:tmpDir `
                    -SkipCertificateCheck 3>&1
            } | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
            $combined = ($warnings | ForEach-Object { $_.Message }) -join "`n"
            $combined | Should -Match 'cred-empty1'
            $combined | Should -Match 'cred-empty2'
        }

        It 'does not auto-fail -- caller decides' {
            { Invoke-VbrMigration `
                -SourceBaseUri 'https://src.test:9419' `
                -TargetBaseUri 'https://tgt.test:9419' `
                -SourceCredential $script:srcCred `
                -TargetCredential $script:tgtCred `
                -WorkingDirectory $script:tmpDir `
                -SkipCertificateCheck } | Should -Not -Throw
        }
    }
}
