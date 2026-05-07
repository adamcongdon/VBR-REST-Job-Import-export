function Test-VbrCredentialPasswords {
    <#
    .SYNOPSIS
        Detects empty password / passphrase / privateKey fields in a
        VBR credentials export and emits a Write-Warning per affected name.

    .DESCRIPTION
        VBR's credentials export does not include the actual password
        material -- only metadata. After import on the destination server,
        operators must manually repopulate each credential's password.
        This function returns $true when EVERY credential has at least one
        non-empty secret-bearing field, and $false (with warnings) when
        any credential is missing one. Callers decide whether to halt.

    .PARAMETER Spec
        The PSCustomObject returned by Export-VbrCredentials (or the
        result of Read-VbrJsonFile on its serialized form).

    .OUTPUTS
        [bool] -- $true means all good, $false means at least one credential
        was flagged.

    .NOTES
        VMware vSphere primary backup jobs only.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [pscustomobject] $Spec
    )

    $items = @()
    if ($Spec.PSObject.Properties.Match('items').Count) {
        $items = @($Spec.items)
    } elseif ($Spec.PSObject.Properties.Match('credentials').Count) {
        $items = @($Spec.credentials)
    } else {
        # Treat the spec itself as a single-item collection.
        $items = @($Spec)
    }

    $offenders = @()
    foreach ($item in $items) {
        if ($null -eq $item) { continue }
        $name = if ($item.PSObject.Properties.Match('name').Count) { [string]$item.name } else { '<unknown>' }

        $hasSecret = $false
        foreach ($field in @('password', 'passphrase', 'privateKey')) {
            if ($item.PSObject.Properties.Match($field).Count) {
                $val = [string]$item.$field
                if (-not [string]::IsNullOrWhiteSpace($val)) { $hasSecret = $true; break }
            }
        }

        if (-not $hasSecret) {
            $offenders += $name
        }
    }

    if ($offenders.Count -gt 0) {
        $list = ($offenders -join ', ')
        Write-Warning ("Test-VbrCredentialPasswords: $($offenders.Count) credential(s) have no password/passphrase/privateKey: $list. Repopulate them on the target VBR server before backup jobs run.")
        Write-VbrLog -Level 'Warn' -Phase 'verify' -Context @{
            'empty-password-creds' = $list
            count                  = $offenders.Count
        } -Message 'Empty-password credentials detected'
        return $false
    }

    return $true
}
