function Write-VbrJsonFile {
    <#
    .SYNOPSIS
        UTF-8 (no BOM) JSON file writer at depth 50.
    .DESCRIPTION
        Serializes $InputObject as JSON (depth 50) and writes UTF-8 without
        BOM to $Path. Creates the parent directory if it doesn't already
        exist so callers don't have to mkdir first.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    $json = ConvertTo-VbrJson -InputObject $InputObject

    # Ensure the parent directory exists before writing.
    $parent = Split-Path -Path $Path -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    # Set-Content with -Encoding utf8NoBOM is the cross-platform safe write on PS7.
    Set-Content -LiteralPath $Path -Value $json -Encoding utf8NoBOM -NoNewline
}
