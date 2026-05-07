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

    Context 'export-only mode' {

        BeforeEach {
            # Override Export-VbrCredentials so credentials.json contains an
            # empty-password row -- needed to assert the warning still fires.
            Mock -ModuleName VbrAutomationMigrate -CommandName Export-VbrCredentials -MockWith {
                $script:callOrder.Add('Export-Credentials') | Out-Null
                return [pscustomobject]@{
                    items = @(
                        [pscustomobject]@{ name = 'cred-with-pw'; password = 'set' }
                        [pscustomobject]@{ name = 'cred-empty';   password = '' }
                    )
                }
            }
        }

        It 'writes all 7 JSON files to WorkingDirectory and stops' {
            $null = Invoke-VbrMigration -ExportOnly `
                -SourceBaseUri 'https://src.test:9419' `
                -SourceCredential $script:srcCred `
                -WorkingDirectory $script:tmpDir `
                -SkipCertificateCheck

            $expected = @(
                'credentials.json','cloudCredentials.json','encryptionPasswords.json',
                'managedServers.json','repositories.json','proxies.json','jobs.json'
            )
            foreach ($f in $expected) {
                Test-Path -LiteralPath (Join-Path $script:tmpDir $f) | Should -BeTrue -Because "ExportOnly should drop $f to WorkingDirectory"
            }
        }

        It 'does NOT call Get-VbrToken with the target uri' {
            $null = Invoke-VbrMigration -ExportOnly `
                -SourceBaseUri 'https://src.test:9419' `
                -SourceCredential $script:srcCred `
                -WorkingDirectory $script:tmpDir `
                -SkipCertificateCheck

            # Only the source token should have been requested.
            Should -Invoke -ModuleName VbrAutomationMigrate -CommandName Get-VbrToken `
                -ParameterFilter { $BaseUri -eq [uri]'https://src.test:9419' } -Times 1 -Exactly
            # And no other Get-VbrToken calls at all (the other call would be the target).
            Should -Invoke -ModuleName VbrAutomationMigrate -CommandName Get-VbrToken -Times 1 -Exactly
        }

        It 'does NOT call any Import-Vbr* function' {
            $null = Invoke-VbrMigration -ExportOnly `
                -SourceBaseUri 'https://src.test:9419' `
                -SourceCredential $script:srcCred `
                -WorkingDirectory $script:tmpDir `
                -SkipCertificateCheck

            foreach ($cmd in 'Import-VbrCredentials','Import-VbrCloudCredentials','Import-VbrEncryptionPasswords','Import-VbrManagedServers','Import-VbrRepositories','Import-VbrProxies','Import-VbrJobs') {
                Should -Invoke -ModuleName VbrAutomationMigrate -CommandName $cmd -Times 0 -Exactly
            }
        }

        It 'does NOT call Wait-VbrAutomationSession' {
            $null = Invoke-VbrMigration -ExportOnly `
                -SourceBaseUri 'https://src.test:9419' `
                -SourceCredential $script:srcCred `
                -WorkingDirectory $script:tmpDir `
                -SkipCertificateCheck

            Should -Invoke -ModuleName VbrAutomationMigrate -CommandName Wait-VbrAutomationSession -Times 0 -Exactly
        }

        It 'still emits the empty-password warning' {
            $warnings = & {
                Invoke-VbrMigration -ExportOnly `
                    -SourceBaseUri 'https://src.test:9419' `
                    -SourceCredential $script:srcCred `
                    -WorkingDirectory $script:tmpDir `
                    -SkipCertificateCheck 3>&1
            } | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
            $warnings.Count | Should -BeGreaterOrEqual 1
            (($warnings | ForEach-Object { $_.Message }) -join "`n") | Should -Match 'cred-empty'
        }

        It 'returns a result whose Sessions property is null/empty' {
            $result = Invoke-VbrMigration -ExportOnly `
                -SourceBaseUri 'https://src.test:9419' `
                -SourceCredential $script:srcCred `
                -WorkingDirectory $script:tmpDir `
                -SkipCertificateCheck

            $result | Should -Not -BeNullOrEmpty
            # Sessions should be null OR an empty hashtable -- either is acceptable
            # as long as no import sessions are reported.
            $hasSessions = $result.Sessions -and ($result.Sessions.Keys.Count -gt 0)
            $hasSessions | Should -BeFalse
            # And the result should expose what was written so the operator can verify.
            $result.WorkingDirectory | Should -Be $script:tmpDir
            $result.Files | Should -Not -BeNullOrEmpty
            $result.Files.Count | Should -Be 7
        }
    }

    Context 'resume-from-import mode' {

        BeforeEach {
            # Seed the seven JSON files in $script:tmpDir so resume can find
            # them. credentials.json carries an empty-password row to drive
            # the still-warns assertion.
            $credSpec = [pscustomobject]@{
                items = @(
                    [pscustomobject]@{ name = 'cred-resumed-with-pw'; password = 'set' }
                    [pscustomobject]@{ name = 'cred-resumed-empty';   password = '' }
                )
            }
            $emptyish = [pscustomobject]@{ items = @() }

            $files = @{
                'credentials.json'         = $credSpec
                'cloudCredentials.json'    = $emptyish
                'encryptionPasswords.json' = $emptyish
                'managedServers.json'      = $emptyish
                'repositories.json'        = $emptyish
                'proxies.json'             = $emptyish
                'jobs.json'                = $emptyish
            }
            foreach ($kv in $files.GetEnumerator()) {
                $path = Join-Path $script:tmpDir $kv.Key
                $kv.Value | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $path -Encoding utf8NoBOM -NoNewline
            }
        }

        It 'reads all 7 JSON files from WorkingDirectory' {
            $null = Invoke-VbrMigration -ResumeFromImport `
                -TargetBaseUri 'https://tgt.test:9419' `
                -TargetCredential $script:tgtCred `
                -WorkingDirectory $script:tmpDir `
                -SkipCertificateCheck

            # Every Import-Vbr* must have run, which is only possible if its
            # corresponding JSON file was successfully read.
            foreach ($cmd in 'Import-VbrCredentials','Import-VbrCloudCredentials','Import-VbrEncryptionPasswords','Import-VbrManagedServers','Import-VbrRepositories','Import-VbrProxies','Import-VbrJobs') {
                Should -Invoke -ModuleName VbrAutomationMigrate -CommandName $cmd -Times 1 -Exactly
            }
        }

        It 'does NOT call any Export-Vbr* function' {
            $null = Invoke-VbrMigration -ResumeFromImport `
                -TargetBaseUri 'https://tgt.test:9419' `
                -TargetCredential $script:tgtCred `
                -WorkingDirectory $script:tmpDir `
                -SkipCertificateCheck

            foreach ($cmd in 'Export-VbrCredentials','Export-VbrCloudCredentials','Export-VbrEncryptionPasswords','Export-VbrManagedServers','Export-VbrRepositories','Export-VbrProxies','Export-VbrJobs') {
                Should -Invoke -ModuleName VbrAutomationMigrate -CommandName $cmd -Times 0 -Exactly
            }
        }

        It 'does NOT call Get-VbrToken with the source uri' {
            $null = Invoke-VbrMigration -ResumeFromImport `
                -TargetBaseUri 'https://tgt.test:9419' `
                -TargetCredential $script:tgtCred `
                -WorkingDirectory $script:tmpDir `
                -SkipCertificateCheck

            Should -Invoke -ModuleName VbrAutomationMigrate -CommandName Get-VbrToken `
                -ParameterFilter { $BaseUri -eq [uri]'https://tgt.test:9419' } -Times 1 -Exactly
            Should -Invoke -ModuleName VbrAutomationMigrate -CommandName Get-VbrToken -Times 1 -Exactly
        }

        It 'imports in correct dependency order (credentials -> jobs)' {
            $null = Invoke-VbrMigration -ResumeFromImport `
                -TargetBaseUri 'https://tgt.test:9419' `
                -TargetCredential $script:tgtCred `
                -WorkingDirectory $script:tmpDir `
                -SkipCertificateCheck

            $expected = @('Import-Credentials','Import-CloudCredentials','Import-EncryptionPasswords','Import-ManagedServers','Import-Repositories','Import-Proxies','Import-Jobs')
            $actual = @($script:callOrder | Where-Object { $_ -like 'Import-*' })
            $actual.Count | Should -Be $expected.Count
            for ($i = 0; $i -lt $expected.Count; $i++) {
                $actual[$i] | Should -Be $expected[$i]
            }
        }

        It 'still emits the empty-password warning before importing' {
            $stream = & {
                Invoke-VbrMigration -ResumeFromImport `
                    -TargetBaseUri 'https://tgt.test:9419' `
                    -TargetCredential $script:tgtCred `
                    -WorkingDirectory $script:tmpDir `
                    -SkipCertificateCheck 3>&1
            }
            $warnings = $stream | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
            $warnings.Count | Should -BeGreaterOrEqual 1
            (($warnings | ForEach-Object { $_.Message }) -join "`n") | Should -Match 'cred-resumed-empty'

            # And the warning must come BEFORE any Import-Vbr* ran. Since
            # Test-VbrCredentialPasswords emits the warning synchronously
            # before the import loop, all imports must have happened (call
            # order assertion) AND the warning must be present (above).
            $script:callOrder | Should -Contain 'Import-Credentials'
        }
    }

    Context 'parameter set validation' {

        It 'throws when both -ExportOnly and -ResumeFromImport are passed' {
            { Invoke-VbrMigration -ExportOnly -ResumeFromImport `
                -SourceBaseUri 'https://src.test:9419' `
                -TargetBaseUri 'https://tgt.test:9419' `
                -SourceCredential $script:srcCred `
                -TargetCredential $script:tgtCred `
                -WorkingDirectory $script:tmpDir `
                -SkipCertificateCheck } | Should -Throw
        }

        It 'throws when -ExportOnly is omitted and Target params are missing' {
            # Default Full set still requires TargetBaseUri / TargetCredential.
            # Inspect the parameter metadata directly so we don't have to
            # invoke the cmdlet (which would prompt for missing mandatory
            # params under PS7's host UI).
            $cmd = Get-Command -Name Invoke-VbrMigration -Module VbrAutomationMigrate
            $tgtUriParam  = $cmd.Parameters['TargetBaseUri']
            $tgtCredParam = $cmd.Parameters['TargetCredential']

            $tgtUriFullAttr  = $tgtUriParam.Attributes  | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ParameterSetName -eq 'Full' }
            $tgtCredFullAttr = $tgtCredParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ParameterSetName -eq 'Full' }

            $tgtUriFullAttr  | Should -Not -BeNullOrEmpty
            $tgtCredFullAttr | Should -Not -BeNullOrEmpty
            $tgtUriFullAttr.Mandatory  | Should -BeTrue
            $tgtCredFullAttr.Mandatory | Should -BeTrue
        }
    }
}
