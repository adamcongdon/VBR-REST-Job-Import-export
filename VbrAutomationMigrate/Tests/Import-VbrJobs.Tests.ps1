BeforeAll {
    . (Join-Path $PSScriptRoot '_Setup.ps1')
    . (Join-Path $PSScriptRoot '_TestHelpers.ps1')
}

Describe 'Import-VbrJobs' {

    BeforeEach {
        $script:capturedUri = $null; $script:capturedMethod = $null
        $script:capturedHeaders = $null; $script:capturedBody = $null
        Mock -ModuleName VbrAutomationMigrate -CommandName Invoke-RestMethod -MockWith {
            param($Uri, $Method, $Headers, $Body, $ContentType, $SkipCertificateCheck, $TimeoutSec)
            $script:capturedUri = $Uri; $script:capturedMethod = $Method
            $script:capturedHeaders = $Headers; $script:capturedBody = $Body
            return [pscustomobject]@{ id = 'sess-job-001' }
        }
        $script:token = New-FakeVbrToken
        $script:spec = [pscustomobject]@{
            items = @([pscustomobject]@{ name = 'job1' })
            deeplyNested = [pscustomobject]@{ l1 = [pscustomobject]@{ l2 = [pscustomobject]@{ l3 = [pscustomobject]@{ l4 = [pscustomobject]@{ l5 = [pscustomobject]@{ l6 = [pscustomobject]@{ l7 = [pscustomobject]@{ value = 'deep' } } } } } } } }
        }
    }

    Context 'request shape' {
        It 'sends POST to /api/v1/automation/jobs/import' {
            $null = Import-VbrJobs -Token $script:token -Spec $script:spec
            $script:capturedMethod | Should -Be 'POST'
            "$script:capturedUri" | Should -Match '/api/v1/automation/jobs/import$'
        }
        It 'sends header x-api-version: 1.3-rev1' {
            $null = Import-VbrJobs -Token $script:token -Spec $script:spec
            $script:capturedHeaders['x-api-version'] | Should -Be '1.3-rev1'
        }
        It 'sends header Authorization: Bearer <token>' {
            $null = Import-VbrJobs -Token $script:token -Spec $script:spec
            $script:capturedHeaders['Authorization'] | Should -Match '^Bearer\s+\S+'
        }
        It 'sends Content-Type application/json' {
            $null = Import-VbrJobs -Token $script:token -Spec $script:spec
            Should -Invoke -ModuleName VbrAutomationMigrate -CommandName Invoke-RestMethod -Times 1 -ParameterFilter { $ContentType -eq 'application/json' }
        }
        It 'sends the supplied -Spec object as the JSON body at depth 50' {
            $null = Import-VbrJobs -Token $script:token -Spec $script:spec
            $parsed = $script:capturedBody | ConvertFrom-Json -Depth 50
            $parsed.deeplyNested.l1.l2.l3.l4.l5.l6.l7.value | Should -Be 'deep'
        }
        It 'does not mutate the supplied -Spec object' {
            $before = ($script:spec | ConvertTo-Json -Depth 50)
            $null = Import-VbrJobs -Token $script:token -Spec $script:spec
            $after = ($script:spec | ConvertTo-Json -Depth 50)
            $after | Should -Be $before
        }
    }
    Context 'return shape' {
        It 'returns an object exposing an Id property (the session id)' {
            $r = Import-VbrJobs -Token $script:token -Spec $script:spec
            $r.id | Should -Be 'sess-job-001'
        }
    }
}
