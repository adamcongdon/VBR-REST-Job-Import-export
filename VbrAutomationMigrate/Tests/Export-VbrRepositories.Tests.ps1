BeforeAll {
    . (Join-Path $PSScriptRoot '_Setup.ps1')
    . (Join-Path $PSScriptRoot '_TestHelpers.ps1')
}

Describe 'Export-VbrRepositories' {

    BeforeEach {
        $script:capturedUri = $null; $script:capturedMethod = $null
        $script:capturedHeaders = $null; $script:capturedBody = $null
        Mock -ModuleName VbrAutomationMigrate -CommandName Invoke-RestMethod -MockWith {
            param($Uri, $Method, $Headers, $Body, $ContentType, $SkipCertificateCheck, $TimeoutSec)
            $script:capturedUri = $Uri; $script:capturedMethod = $Method
            $script:capturedHeaders = $Headers; $script:capturedBody = $Body
            return New-DeepFakeExportResponse
        }
        $script:token = New-FakeVbrToken
    }

    Context 'request shape' {
        It 'sends POST to /api/v1/automation/repositories/export' {
            $null = Export-VbrRepositories -Token $script:token
            $script:capturedMethod | Should -Be 'POST'
            "$script:capturedUri" | Should -Match '/api/v1/automation/repositories/export$'
        }
        It 'sends header x-api-version: 1.3-rev1' {
            $null = Export-VbrRepositories -Token $script:token
            $script:capturedHeaders['x-api-version'] | Should -Be '1.3-rev1'
        }
        It 'sends header Authorization: Bearer <token>' {
            $null = Export-VbrRepositories -Token $script:token
            $script:capturedHeaders['Authorization'] | Should -Match '^Bearer\s+\S+'
        }
        It 'sends Content-Type application/json' {
            $null = Export-VbrRepositories -Token $script:token
            Should -Invoke -ModuleName VbrAutomationMigrate -CommandName Invoke-RestMethod -Times 1 -ParameterFilter { $ContentType -eq 'application/json' }
        }
        It 'sends body {"names":[]} when -Names is omitted' {
            $null = Export-VbrRepositories -Token $script:token
            $parsed = $script:capturedBody | ConvertFrom-Json -Depth 50
            ,$parsed.names | Should -BeOfType ([array])
            $parsed.names.Count | Should -Be 0
        }
        It 'sends body {"names":["foo","bar"]} when -Names is supplied' {
            $null = Export-VbrRepositories -Token $script:token -Names @('foo', 'bar')
            $parsed = $script:capturedBody | ConvertFrom-Json -Depth 50
            $parsed.names | Should -Be @('foo', 'bar')
        }
    }

    Context 'return shape' {
        It 'returns a parsed PSCustomObject (not a raw string)' {
            $r = Export-VbrRepositories -Token $script:token
            $r | Should -Not -BeOfType ([string])
            $r | Should -BeOfType ([pscustomobject])
        }
        It 'preserves nested objects beyond the default ConvertFrom-Json depth' {
            $r = Export-VbrRepositories -Token $script:token
            $r.deeplyNested.l1.l2.l3.l4.l5.l6.l7.value | Should -Be 'leaf'
        }
    }
}
