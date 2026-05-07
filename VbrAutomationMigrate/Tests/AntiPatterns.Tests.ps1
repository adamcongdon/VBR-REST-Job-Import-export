# Source-level forbidden-pattern guards.
#
# These tests scan the module's *.ps1 files for patterns that the legacy
# scripts had and that we have decided are non-negotiable defects.
# They run against the contents of VbrAutomationMigrate/ only -- NOT
# against the legacy root scripts (which will be removed at the end of
# this PR per Risk R6).

BeforeAll {
    . (Join-Path $PSScriptRoot '_Setup.ps1')

    $script:moduleSourceFiles = @(
        Get-ChildItem -Path (Join-Path $script:ModuleRoot 'Public')  -Filter '*.ps1' -File -ErrorAction SilentlyContinue
        Get-ChildItem -Path (Join-Path $script:ModuleRoot 'Private') -Filter '*.ps1' -File -ErrorAction SilentlyContinue
        Get-ChildItem -Path $script:ModuleRoot -Filter '*.psm1' -File -ErrorAction SilentlyContinue
    )

    $script:sourceBag = @{}
    foreach ($f in $script:moduleSourceFiles) {
        $script:sourceBag[$f.FullName] = Get-Content -LiteralPath $f.FullName -Raw -Encoding utf8
    }
}

Describe 'Module source must not contain forbidden patterns' {

    It 'has no curl.exe references in any .ps1 file' {
        $offenders = @()
        foreach ($path in $script:sourceBag.Keys) {
            if ($script:sourceBag[$path] -match 'curl\.exe') { $offenders += $path }
        }
        $offenders | Should -BeNullOrEmpty -Because 'curl.exe is banned by Constitutional Principle C2 (no shell-out HTTP).'
    }

    It 'has no [System.Windows.MessageBox] references in any .ps1 file' {
        $offenders = @()
        foreach ($path in $script:sourceBag.Keys) {
            if ($script:sourceBag[$path] -match '\[System\.Windows\.MessageBox\]') { $offenders += $path }
        }
        $offenders | Should -BeNullOrEmpty -Because 'C3 -- module must run headless. No interactive MessageBox UI.'
    }

    It 'has no .Replace single-quote-for-double-quote JSON-mangling hack' {
        # The legacy scripts did .Replace('"', "'") to dodge cmd.exe quoting.
        # Build the literal pattern at runtime so we never have to escape it inline.
        $dq = [char]0x22  # double quote "
        $sq = [char]0x27  # single quote '
        # Two literal forms: .Replace('"', "'")  and  .Replace("\"", "'")
        $form1 = ".Replace($sq$dq$sq, $dq$sq$dq)"
        $form2 = ".Replace($dq\$dq$dq, $sq$sq$sq)"
        $offenders = @()
        foreach ($path in $script:sourceBag.Keys) {
            $content = $script:sourceBag[$path]
            if ($content.Contains($form1) -or $content.Contains($form2)) {
                $offenders += $path
            }
        }
        $offenders | Should -BeNullOrEmpty -Because 'JSON quote-mangling was a curl.exe-shell-out workaround. Banned.'
    }

    It 'has no hardcoded password literal "Veeam123!"' {
        $offenders = @()
        foreach ($path in $script:sourceBag.Keys) {
            if ($script:sourceBag[$path] -match 'Veeam123!') { $offenders += $path }
        }
        $offenders | Should -BeNullOrEmpty -Because 'C5 -- no hardcoded credentials in module source.'
    }

    It 'has no hardcoded basic-auth -u argument' {
        # Detect the curl-style "-u user:pass" pattern that the old scripts shipped.
        $offenders = @()
        foreach ($path in $script:sourceBag.Keys) {
            if ($script:sourceBag[$path] -match '\s-u\s+\w+:\S+') { $offenders += $path }
        }
        $offenders | Should -BeNullOrEmpty -Because 'Basic-auth -u was dead code in the legacy scripts; v13 is Bearer-only.'
    }

    It 'has no x-api-version values other than 1.3-rev1' {
        $offenders = @()
        $allowed = '1.3-rev1'
        $pattern = 'x-api-version[^A-Za-z0-9]+([0-9][0-9A-Za-z\.\-]*)'
        foreach ($path in $script:sourceBag.Keys) {
            $matches = [regex]::Matches($script:sourceBag[$path], $pattern, 'IgnoreCase')
            foreach ($m in $matches) {
                $val = $m.Groups[1].Value
                if ($val -ne $allowed) {
                    $offenders += "$path => '$val'"
                }
            }
        }
        $offenders | Should -BeNullOrEmpty -Because 'C6 -- exactly one x-api-version value across the module: 1.3-rev1.'
    }

    It 'has no Out-File without -Encoding utf8NoBOM in module code' {
        $offenders = @()
        foreach ($path in $script:sourceBag.Keys) {
            $content = $script:sourceBag[$path]
            $hits = [regex]::Matches($content, 'Out-File[^\r\n;|}]*', 'IgnoreCase')
            foreach ($h in $hits) {
                if ($h.Value -notmatch '-Encoding\s+utf8NoBOM') {
                    $offenders += "$path => $($h.Value.Trim())"
                }
            }
        }
        $offenders | Should -BeNullOrEmpty -Because 'Cross-platform UTF-8 must be BOM-less; default Out-File on Windows emits UTF-16.'
    }

    It 'has no plaintext access_token in any Write-Verbose / Write-Debug / Write-Host call' {
        $offenders = @()
        foreach ($path in $script:sourceBag.Keys) {
            $content = $script:sourceBag[$path]
            $hits = [regex]::Matches($content, '(?im)Write-(Verbose|Debug|Host)[^\r\n]*')
            foreach ($h in $hits) {
                $line = $h.Value
                if ($line -match 'access_token' -or $line -match '\$AccessToken' -or $line -match 'Bearer\s+\$') {
                    $offenders += "$path => $($line.Trim())"
                }
            }
        }
        $offenders | Should -BeNullOrEmpty -Because 'C4 -- bearer tokens never appear on verbose/debug/host streams.'
    }
}
