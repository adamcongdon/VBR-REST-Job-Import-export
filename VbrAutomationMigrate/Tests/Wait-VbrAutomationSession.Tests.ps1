BeforeAll {
    . (Join-Path $PSScriptRoot '_Setup.ps1')
    . (Join-Path $PSScriptRoot '_TestHelpers.ps1')
}

Describe 'Wait-VbrAutomationSession' {

    BeforeEach {
        $script:capturedUri = $null
        $script:capturedMethod = $null
        $script:capturedHeaders = $null
        $script:token = New-FakeVbrToken
    }

    Context 'request shape' {

        It 'GETs /api/v1/automation/sessions/{id} (NOT /api/v1/sessions/{id})' {
            Mock -ModuleName VbrAutomationMigrate -CommandName Invoke-RestMethod -MockWith {
                param($Uri, $Method, $Headers, $Body, $ContentType, $SkipCertificateCheck, $TimeoutSec)
                $script:capturedUri = $Uri
                $script:capturedMethod = $Method
                $script:capturedHeaders = $Headers
                return New-FakeSessionResponse -Id 'abc-1' -State 'Succeeded'
            }
            $null = Wait-VbrAutomationSession -Token $script:token -SessionId 'abc-1' -PollSeconds 1 -TimeoutSeconds 10
            $script:capturedMethod | Should -Be 'GET'
            "$script:capturedUri" | Should -Match '/api/v1/automation/sessions/abc-1$'
            "$script:capturedUri" | Should -Not -Match '/api/v1/sessions/abc-1$'
        }

        It 'sends header x-api-version: 1.3-rev1' {
            Mock -ModuleName VbrAutomationMigrate -CommandName Invoke-RestMethod -MockWith {
                param($Uri, $Method, $Headers)
                $script:capturedHeaders = $Headers
                return New-FakeSessionResponse -State 'Succeeded'
            }
            $null = Wait-VbrAutomationSession -Token $script:token -SessionId 'abc-2' -PollSeconds 1 -TimeoutSeconds 10
            $script:capturedHeaders['x-api-version'] | Should -Be '1.3-rev1'
        }

        It 'sends header Authorization: Bearer <token>' {
            Mock -ModuleName VbrAutomationMigrate -CommandName Invoke-RestMethod -MockWith {
                param($Uri, $Method, $Headers)
                $script:capturedHeaders = $Headers
                return New-FakeSessionResponse -State 'Succeeded'
            }
            $null = Wait-VbrAutomationSession -Token $script:token -SessionId 'abc-3' -PollSeconds 1 -TimeoutSeconds 10
            $script:capturedHeaders['Authorization'] | Should -Match '^Bearer\s+\S+'
        }
    }

    Context 'state machine' {

        It 'continues polling while state == "Working"' {
            $script:callCount = 0
            Mock -ModuleName VbrAutomationMigrate -CommandName Invoke-RestMethod -MockWith {
                $script:callCount++
                if ($script:callCount -lt 3) { return New-FakeSessionResponse -State 'Working' }
                return New-FakeSessionResponse -State 'Succeeded'
            }
            Mock -ModuleName VbrAutomationMigrate -CommandName Start-Sleep -MockWith { }
            $null = Wait-VbrAutomationSession -Token $script:token -SessionId 'abc-4' -PollSeconds 1 -TimeoutSeconds 30
            $script:callCount | Should -BeGreaterOrEqual 3
        }

        It 'returns when state == "Succeeded"' {
            Mock -ModuleName VbrAutomationMigrate -CommandName Invoke-RestMethod -MockWith {
                return New-FakeSessionResponse -Id 'abc-5' -State 'Succeeded'
            }
            $r = Wait-VbrAutomationSession -Token $script:token -SessionId 'abc-5' -PollSeconds 1 -TimeoutSeconds 10
            $r.state | Should -Be 'Succeeded'
            $r.id | Should -Be 'abc-5'
        }

        It 'throws when state == "Failed" with the session payload attached to the exception' {
            Mock -ModuleName VbrAutomationMigrate -CommandName Invoke-RestMethod -MockWith {
                return New-FakeSessionResponse -Id 'abc-6' -State 'Failed'
            }
            $err = $null
            try {
                Wait-VbrAutomationSession -Token $script:token -SessionId 'abc-6' -PollSeconds 1 -TimeoutSeconds 10
            } catch { $err = $_ }
            $err | Should -Not -BeNullOrEmpty
            $err.Exception.Message | Should -Match 'Failed'
            # Session payload attached to ErrorRecord.TargetObject.
            $err.TargetObject | Should -Not -BeNullOrEmpty
            $err.TargetObject.id | Should -Be 'abc-6'
        }

        It 'throws when state == "Stopped"' {
            Mock -ModuleName VbrAutomationMigrate -CommandName Invoke-RestMethod -MockWith {
                return New-FakeSessionResponse -State 'Stopped'
            }
            { Wait-VbrAutomationSession -Token $script:token -SessionId 'abc-7' -PollSeconds 1 -TimeoutSeconds 10 } |
                Should -Throw -ExpectedMessage '*Stopped*'
        }

        It 'throws when state == "Canceled"' {
            Mock -ModuleName VbrAutomationMigrate -CommandName Invoke-RestMethod -MockWith {
                return New-FakeSessionResponse -State 'Canceled'
            }
            { Wait-VbrAutomationSession -Token $script:token -SessionId 'abc-8' -PollSeconds 1 -TimeoutSeconds 10 } |
                Should -Throw -ExpectedMessage '*Canceled*'
        }

        It 'sleeps -PollSeconds between polls' {
            $script:callCount = 0
            Mock -ModuleName VbrAutomationMigrate -CommandName Invoke-RestMethod -MockWith {
                $script:callCount++
                if ($script:callCount -lt 3) { return New-FakeSessionResponse -State 'Working' }
                return New-FakeSessionResponse -State 'Succeeded'
            }
            Mock -ModuleName VbrAutomationMigrate -CommandName Start-Sleep -MockWith { }
            $null = Wait-VbrAutomationSession -Token $script:token -SessionId 'abc-9' -PollSeconds 7 -TimeoutSeconds 30
            # Working returned twice -> Start-Sleep -Seconds 7 invoked at least twice.
            Should -Invoke -ModuleName VbrAutomationMigrate -CommandName Start-Sleep -Times 2 -Exactly -ParameterFilter {
                $Seconds -eq 7
            }
        }
    }

    Context 'timeout' {

        It 'throws a TimeoutException when -TimeoutSeconds elapses before terminal state' {
            Mock -ModuleName VbrAutomationMigrate -CommandName Invoke-RestMethod -MockWith {
                return New-FakeSessionResponse -State 'Working'
            }
            # Use real Start-Sleep but at millisecond resolution: each "1 sec"
            # mocked sleep advances real time by ~50ms, and the deadline is
            # checked against real wall-clock UtcNow.
            Mock -ModuleName VbrAutomationMigrate -CommandName Start-Sleep -MockWith {
                param([int]$Seconds)
                [System.Threading.Thread]::Sleep(50)
            }

            $err = $null
            try {
                # 1-second deadline; with ~50ms real sleep per poll, expires inside ~1s.
                Wait-VbrAutomationSession -Token $script:token -SessionId 'abc-10' -PollSeconds 1 -TimeoutSeconds 1
            } catch { $err = $_ }
            $err | Should -Not -BeNullOrEmpty
            ($err.Exception -is [System.TimeoutException]) | Should -BeTrue
        }

        It 'does not throw when terminal state is reached just before timeout' {
            Mock -ModuleName VbrAutomationMigrate -CommandName Invoke-RestMethod -MockWith {
                return New-FakeSessionResponse -State 'Succeeded'
            }
            { Wait-VbrAutomationSession -Token $script:token -SessionId 'abc-11' -PollSeconds 1 -TimeoutSeconds 10 } |
                Should -Not -Throw
        }
    }
}
