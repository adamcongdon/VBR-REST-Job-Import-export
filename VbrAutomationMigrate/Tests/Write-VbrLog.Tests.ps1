BeforeAll {
    . (Join-Path $PSScriptRoot '_Setup.ps1')
}

Describe 'Write-VbrLog' {

    BeforeEach {
        $script:logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("vbrlog-" + [guid]::NewGuid().ToString() + ".log")
    }

    AfterEach {
        if ($script:logPath -and (Test-Path -LiteralPath $script:logPath)) {
            Remove-Item -LiteralPath $script:logPath -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'basic file behavior' {

        It 'writes a line to a fresh path when the file did not exist' {
            InModuleScope VbrAutomationMigrate -Parameters @{ p = $script:logPath } {
                param($p)
                Write-VbrLog -Path $p -Level 'Info' -Message 'hello world'
            }
            Test-Path -LiteralPath $script:logPath | Should -BeTrue
            (Get-Content -LiteralPath $script:logPath) | Should -Match 'hello world'
        }

        It 'appends to an existing path without truncating earlier lines' {
            InModuleScope VbrAutomationMigrate -Parameters @{ p = $script:logPath } {
                param($p)
                Write-VbrLog -Path $p -Level 'Info' -Message 'first line'
                Write-VbrLog -Path $p -Level 'Info' -Message 'second line'
            }
            $lines = Get-Content -LiteralPath $script:logPath
            $lines.Count          | Should -Be 2
            $lines[0]             | Should -Match 'first line'
            $lines[1]             | Should -Match 'second line'
        }

        It 'prefixes each line with an ISO-8601 UTC timestamp ending in Z' {
            InModuleScope VbrAutomationMigrate -Parameters @{ p = $script:logPath } {
                param($p)
                Write-VbrLog -Path $p -Level 'Info' -Message 'iso8601 check'
            }
            $line = Get-Content -LiteralPath $script:logPath -First 1
            $line | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\s'
        }

        It 'writes the file as UTF-8 without a BOM' {
            InModuleScope VbrAutomationMigrate -Parameters @{ p = $script:logPath } {
                param($p)
                Write-VbrLog -Path $p -Level 'Info' -Message 'utf8 nobom'
            }
            $bytes = [System.IO.File]::ReadAllBytes($script:logPath)
            # First three bytes of a BOM-prefixed UTF-8 file are 0xEF 0xBB 0xBF.
            $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
            $hasBom | Should -BeFalse
        }
    }

    Context 'level formatting' {

        It 'formats Info as [INFO]' {
            InModuleScope VbrAutomationMigrate -Parameters @{ p = $script:logPath } {
                param($p)
                Write-VbrLog -Path $p -Level 'Info' -Message 'm'
            }
            (Get-Content -LiteralPath $script:logPath -First 1) | Should -Match '\[INFO\]'
        }

        It 'formats Warn as [WARN]' {
            InModuleScope VbrAutomationMigrate -Parameters @{ p = $script:logPath } {
                param($p)
                Write-VbrLog -Path $p -Level 'Warn' -Message 'm'
            }
            (Get-Content -LiteralPath $script:logPath -First 1) | Should -Match '\[WARN\]'
        }

        It 'formats Error as [ERROR]' {
            InModuleScope VbrAutomationMigrate -Parameters @{ p = $script:logPath } {
                param($p)
                Write-VbrLog -Path $p -Level 'Error' -Message 'm'
            }
            (Get-Content -LiteralPath $script:logPath -First 1) | Should -Match '\[ERROR\]'
        }

        It 'formats Debug as [DEBUG]' {
            InModuleScope VbrAutomationMigrate -Parameters @{ p = $script:logPath } {
                param($p)
                Write-VbrLog -Path $p -Level 'Debug' -Message 'm'
            }
            (Get-Content -LiteralPath $script:logPath -First 1) | Should -Match '\[DEBUG\]'
        }
    }

    Context 'phase and context' {

        It 'includes [phase=...] when -Phase is supplied' {
            InModuleScope VbrAutomationMigrate -Parameters @{ p = $script:logPath } {
                param($p)
                Write-VbrLog -Path $p -Level 'Info' -Phase 'export-source' -Message 'starting'
            }
            (Get-Content -LiteralPath $script:logPath -First 1) | Should -Match '\[phase=export-source\]'
        }

        It 'serializes -Context hashtable as inline key=value pairs' {
            InModuleScope VbrAutomationMigrate -Parameters @{ p = $script:logPath } {
                param($p)
                Write-VbrLog -Path $p -Level 'Debug' -Context @{ http = 'GET'; status = 200 } -Message ''
            }
            $line = Get-Content -LiteralPath $script:logPath -First 1
            $line | Should -Match 'http=GET'
            $line | Should -Match 'status=200'
        }
    }

    Context 'no-op behavior' {

        It 'is a no-op when both $script:VbrLogPath and -Path are null' {
            $sentinel = $script:logPath  # not yet created
            InModuleScope VbrAutomationMigrate {
                $script:VbrLogPath = $null
                # No -Path supplied, no module state -- must not write anywhere.
                Write-VbrLog -Level 'Info' -Message 'should not appear'
            }
            Test-Path -LiteralPath $sentinel | Should -BeFalse
        }

        It 'is a no-op when -Path is the literal /dev/null' {
            # We cannot test by reading /dev/null, but we can confirm no
            # exception is raised and no other file is written. A pre-flight
            # path that we own should remain absent.
            InModuleScope VbrAutomationMigrate {
                { Write-VbrLog -Path '/dev/null' -Level 'Info' -Message 'opt-out' } | Should -Not -Throw
            }
            Test-Path -LiteralPath $script:logPath | Should -BeFalse
        }
    }

    Context 'secret redaction (Constitutional C4)' {

        It 'does NOT write a literal Bearer <token> sequence' {
            InModuleScope VbrAutomationMigrate -Parameters @{ p = $script:logPath } {
                param($p)
                Write-VbrLog -Path $p -Level 'Debug' -Message 'header Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig'
            }
            $content = Get-Content -LiteralPath $script:logPath -Raw
            $content | Should -Not -Match 'Bearer\s+eyJ'
            $content | Should -Match 'Bearer <redacted>'
        }

        It 'does NOT write the literal "Veeam123!" password' {
            InModuleScope VbrAutomationMigrate -Parameters @{ p = $script:logPath } {
                param($p)
                # Same pattern that AntiPatterns.Tests.ps1 forbids in module source.
                Write-VbrLog -Path $p -Level 'Debug' -Message 'oauth body grant_type=password&username=admin&password=Veeam123!'
            }
            $content = Get-Content -LiteralPath $script:logPath -Raw
            $content | Should -Not -Match 'Veeam123!'
        }

        It 'redacts password=, passphrase=, and privateKey= form-encoded values' {
            InModuleScope VbrAutomationMigrate -Parameters @{ p = $script:logPath } {
                param($p)
                Write-VbrLog -Path $p -Level 'Debug' -Message 'k=v password=hunter2 passphrase=opensesame privateKey=mysecret tail'
            }
            $content = Get-Content -LiteralPath $script:logPath -Raw
            $content | Should -Not -Match 'hunter2'
            $content | Should -Not -Match 'opensesame'
            $content | Should -Not -Match 'mysecret'
            $content | Should -Match 'password=<redacted>'
            $content | Should -Match 'passphrase=<redacted>'
            $content | Should -Match 'privateKey=<redacted>'
        }

        It 'redacts access_token JSON-shape and key=value forms' {
            InModuleScope VbrAutomationMigrate -Parameters @{ p = $script:logPath } {
                param($p)
                Write-VbrLog -Path $p -Level 'Debug' -Message 'response: {"access_token":"sekret123","expires_in":3600} also access_token=anotherSekret'
            }
            $content = Get-Content -LiteralPath $script:logPath -Raw
            $content | Should -Not -Match 'sekret123'
            $content | Should -Not -Match 'anotherSekret'
            $content | Should -Match 'access_token'  # the redaction marker keeps the field name
            $content | Should -Match '<redacted>'
        }

        It 'redacts JSON-shape "password":"..." inside a serialized request body' {
            InModuleScope VbrAutomationMigrate -Parameters @{ p = $script:logPath } {
                param($p)
                Write-VbrLog -Path $p -Level 'Debug' -Message 'body={"name":"cred1","password":"hunter2","passphrase":"opensesame"}'
            }
            $content = Get-Content -LiteralPath $script:logPath -Raw
            $content | Should -Not -Match 'hunter2'
            $content | Should -Not -Match 'opensesame'
            $content | Should -Match '"password":"<redacted>"'
            $content | Should -Match '"passphrase":"<redacted>"'
        }
    }
}
