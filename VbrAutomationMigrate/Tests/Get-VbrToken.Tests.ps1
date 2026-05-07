BeforeAll {
    . (Join-Path $PSScriptRoot '_Setup.ps1')

    # Helper: build a PSCredential from plaintext (test-only).
    function script:New-TestCredential {
        param([string]$User = 'lab\administrator', [string]$Pass = 'p@ss-w0rd-not-real')
        $sec = ConvertTo-SecureString $Pass -AsPlainText -Force
        return [pscredential]::new($User, $sec)
    }

    # Build a fake successful token response object as Invoke-RestMethod would return.
    function script:New-FakeTokenResponse {
        param([int]$ExpiresIn = 3600)
        return [pscustomobject]@{
            access_token  = 'FAKE.JWT.TOKEN.VALUE'
            token_type    = 'bearer'
            expires_in    = $ExpiresIn
            refresh_token = 'FAKE.REFRESH.TOKEN.VALUE'
        }
    }
}

Describe 'Get-VbrToken' {

    Context 'happy path' {

        BeforeEach {
            $script:capturedUri    = $null
            $script:capturedMethod = $null
            $script:capturedHeaders = $null
            $script:capturedBody   = $null
            $script:capturedContentType = $null

            Mock -ModuleName VbrAutomationMigrate -CommandName Invoke-RestMethod -MockWith {
                param(
                    $Uri, $Method, $Headers, $Body, $ContentType, $SkipCertificateCheck, $TimeoutSec
                )
                $script:capturedUri         = $Uri
                $script:capturedMethod      = $Method
                $script:capturedHeaders     = $Headers
                $script:capturedBody        = $Body
                $script:capturedContentType = $ContentType
                return (New-FakeTokenResponse)
            }
        }

        It 'POSTs to /api/oauth2/token on the supplied BaseUri' {
            $cred = New-TestCredential
            $null = Get-VbrToken -BaseUri 'https://vbr.example.test:9419' -Credential $cred -SkipCertificateCheck
            $script:capturedMethod | Should -Be 'POST'
            "$script:capturedUri" | Should -Match '/api/oauth2/token$'
            "$script:capturedUri" | Should -Match '^https://vbr\.example\.test:9419/'
        }

        It 'sends Content-Type application/x-www-form-urlencoded' {
            $cred = New-TestCredential
            $null = Get-VbrToken -BaseUri 'https://vbr.example.test:9419' -Credential $cred -SkipCertificateCheck
            $script:capturedContentType | Should -Be 'application/x-www-form-urlencoded'
        }

        It 'sends grant_type=password in the body' {
            $cred = New-TestCredential
            $null = Get-VbrToken -BaseUri 'https://vbr.example.test:9419' -Credential $cred -SkipCertificateCheck
            $script:capturedBody | Should -Match 'grant_type=password'
        }

        It 'sends username and password from the supplied PSCredential in the body' {
            $cred = New-TestCredential -User 'lab\admin42' -Pass 'P@55w0rd!xyz'
            $null = Get-VbrToken -BaseUri 'https://vbr.example.test:9419' -Credential $cred -SkipCertificateCheck
            $script:capturedBody | Should -Match 'username=lab%5Cadmin42'
            $script:capturedBody | Should -Match 'password=P%4055w0rd%21xyz'
        }

        It 'returns an object with AccessToken populated as a SecureString' {
            $cred = New-TestCredential
            $tok = Get-VbrToken -BaseUri 'https://vbr.example.test:9419' -Credential $cred -SkipCertificateCheck
            $tok | Should -Not -BeNullOrEmpty
            $tok.AccessToken | Should -BeOfType ([securestring])
        }

        It 'returns an object with ExpiresAt set in the future' {
            $cred = New-TestCredential
            $tok = Get-VbrToken -BaseUri 'https://vbr.example.test:9419' -Credential $cred -SkipCertificateCheck
            $tok.ExpiresAt | Should -BeOfType ([datetime])
            $tok.ExpiresAt | Should -BeGreaterThan ([datetime]::UtcNow)
        }
    }

    Context 'error paths' {

        It 'throws a terminating error when the response has no access_token field' {
            Mock -ModuleName VbrAutomationMigrate -CommandName Invoke-RestMethod -MockWith {
                return [pscustomobject]@{ token_type = 'bearer'; expires_in = 3600 }
            }
            $cred = New-TestCredential
            { Get-VbrToken -BaseUri 'https://vbr.example.test:9419' -Credential $cred -SkipCertificateCheck } |
                Should -Throw -ExpectedMessage '*access_token*'
        }

        It 'throws a terminating error when Invoke-RestMethod throws a network exception' {
            Mock -ModuleName VbrAutomationMigrate -CommandName Invoke-RestMethod -MockWith {
                throw [System.Net.WebException]::new('Connection refused')
            }
            $cred = New-TestCredential
            { Get-VbrToken -BaseUri 'https://vbr.example.test:9419' -Credential $cred -SkipCertificateCheck } |
                Should -Throw
        }

        It 'wraps the inner exception so the caller can see the original error' {
            Mock -ModuleName VbrAutomationMigrate -CommandName Invoke-RestMethod -MockWith {
                throw [System.Net.WebException]::new('Connection refused by remote host')
            }
            $cred = New-TestCredential
            $err = $null
            try {
                Get-VbrToken -BaseUri 'https://vbr.example.test:9419' -Credential $cred -SkipCertificateCheck
            } catch {
                $err = $_
            }
            $err | Should -Not -BeNullOrEmpty
            # Either the message contains the inner text, or InnerException is preserved.
            $hasInnerMsg = ($err.Exception.Message -match 'Connection refused') -or
                           ($null -ne $err.Exception.InnerException -and $err.Exception.InnerException.Message -match 'Connection refused')
            $hasInnerMsg | Should -BeTrue
        }
    }

    Context 'security' {

        BeforeEach {
            Mock -ModuleName VbrAutomationMigrate -CommandName Invoke-RestMethod -MockWith {
                return (New-FakeTokenResponse)
            }
        }

        It 'does not write the password to Verbose stream when -Verbose is set' {
            $cred = New-TestCredential -User 'lab\admin' -Pass 'SuperSecretPasswordXYZ'
            $verboseCapture = & {
                $VerbosePreference = 'Continue'
                Get-VbrToken -BaseUri 'https://vbr.example.test:9419' -Credential $cred -SkipCertificateCheck -Verbose 4>&1
            } | Out-String
            $verboseCapture | Should -Not -Match 'SuperSecretPasswordXYZ'
        }

        It 'does not write the password to Debug stream when -Debug is set' {
            $cred = New-TestCredential -User 'lab\admin' -Pass 'AnotherSecretQRS'
            $debugCapture = & {
                $DebugPreference = 'Continue'
                Get-VbrToken -BaseUri 'https://vbr.example.test:9419' -Credential $cred -SkipCertificateCheck -Debug 5>&1
            } | Out-String
            $debugCapture | Should -Not -Match 'AnotherSecretQRS'
        }

        It 'does not write the access_token to Verbose stream when -Verbose is set' {
            $cred = New-TestCredential
            $verboseCapture = & {
                $VerbosePreference = 'Continue'
                Get-VbrToken -BaseUri 'https://vbr.example.test:9419' -Credential $cred -SkipCertificateCheck -Verbose 4>&1
            } | Out-String
            $verboseCapture | Should -Not -Match 'FAKE\.JWT\.TOKEN\.VALUE'
        }
    }
}
