function Read-VbrJsonFile {
    <#
    .SYNOPSIS
        UTF-8 (BOM-tolerant) JSON file reader at depth 50.
    .DESCRIPTION
        Reads $Path as UTF-8 and parses it as JSON at depth 50. Attempts the
        read directly (no upfront Test-Path) to avoid a time-of-check vs
        time-of-use race; missing files surface as a clearer error.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8 -ErrorAction Stop
    } catch [System.Management.Automation.ItemNotFoundException] {
        throw "Read-VbrJsonFile: file not found: $Path"
    } catch [System.IO.FileNotFoundException] {
        throw "Read-VbrJsonFile: file not found: $Path"
    } catch [System.IO.DirectoryNotFoundException] {
        throw "Read-VbrJsonFile: file not found: $Path"
    }

    return $raw | ConvertFrom-Json -Depth 50
}
