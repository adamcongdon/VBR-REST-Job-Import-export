function ConvertTo-VbrJson {
    <#
    .SYNOPSIS
        ConvertTo-Json wrapper that always uses -Depth 50 (Constitutional C8).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        $InputObject
    )

    process {
        return ConvertTo-Json -InputObject $InputObject -Depth 50
    }
}
