function New-VbrAuthHeader {
    <#
    .SYNOPSIS
        Materialize the Authorization: Bearer header from a VbrToken's
        SecureString access token. The plaintext token exists in this
        function's stack only.
    .NOTES
        Constitutional C4 -- never write tokens to verbose/debug/host streams.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Token
    )

    if (-not $Token -or -not $Token.AccessToken) {
        throw 'New-VbrAuthHeader: Token.AccessToken is null.'
    }

    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Token.AccessToken)
    try {
        $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }

    return @{ 'Authorization' = "Bearer $plain" }
}
