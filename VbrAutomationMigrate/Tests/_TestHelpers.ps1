# Shared helpers used by multiple test files. Sourced after _Setup.ps1.

function script:New-FakeVbrToken {
    param(
        [uri] $BaseUri = [uri]'https://vbr.example.test:9419'
    )
    $sec  = ConvertTo-SecureString 'FAKE.JWT.TOKEN.VALUE' -AsPlainText -Force
    $cred = [pscredential]::new('lab\admin', (ConvertTo-SecureString 'pw' -AsPlainText -Force))
    # Build via the in-module class.
    $module = Get-Module -Name VbrAutomationMigrate
    $tokenType = $module.Invoke({ [VbrToken] })
    return $tokenType::new($sec, [datetime]::UtcNow.AddHours(1), $BaseUri, $cred, $true)
}

function script:New-DeepFakeExportResponse {
    return [pscustomobject]@{
        items = @(
            [pscustomobject]@{ name = 'cred1'; type = 'standard'; password = 'redacted' },
            [pscustomobject]@{ name = 'cred2'; type = 'linux';    password = '' }
        )
        meta = [pscustomobject]@{ count = 2 }
        deeplyNested = [pscustomobject]@{
            l1 = [pscustomobject]@{
                l2 = [pscustomobject]@{
                    l3 = [pscustomobject]@{
                        l4 = [pscustomobject]@{
                            l5 = [pscustomobject]@{
                                l6 = [pscustomobject]@{
                                    l7 = [pscustomobject]@{
                                        value = 'leaf'
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

function script:New-FakeSessionResponse {
    param(
        [string]$Id    = '11111111-2222-3333-4444-555555555555',
        [string]$State = 'Working'
    )
    return [pscustomobject]@{
        id     = $Id
        state  = $State
        result = [pscustomobject]@{ message = "session $Id state=$State" }
    }
}
