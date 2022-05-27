<#
This script is a working document designed to test the export & import of jobs.

#>

$curlEXE = 'C:\Program Files\Git\mingw64\bin\curl.exe'
$serverAddress = "https://backup-v11:9419"


$exportJobs = $serverAddress +  "/api/v1/automation/jobs/export"
$exportCreds = $serverAddress + "/api/v1/automation/credentials/export"
$exportManagedServer = $serverAddress + "/api/v1/automation/managedServers/export"
$exportRepo = $serverAddress + "/api/v1/automation/repositories/export"
$exportProxy = $serverAddress + "/api/v1/automation/proxies/export"

#get Token
$TokenLink = 'https://backup-v11:9419/api/oauth2/token'
$getTokenString = PostString($TokenLink)
$tokenString = & $curlEXE @getTokenString
$t = $tokenString | ConvertFrom-Json
$token = $t.access_token
function PostString {
    param (
        $ApiLink,
        $SecToken
    )
    $string = '--insecure','-u', 'administrator:Veeam123!',
    '-X','POST',
    $ApiLink,
    '-H', 'accept: application/json',
    '-H', 'x-api-version: 1.0-rev1',
    #'-H', 'X-Auth-Token:' + $SecToken
    '-d', 'grant_type=password&username=administrator&password=Veeam123!&refresh_token=&code=&use_short_term_refresh='

    #'-H', 'Content-Type: application/x-www-form-urlencoded'
    return $string
}

function GetCreds{
    $authString = "Authorization: Bearer " + $token
    $string = '--insecure','-u', 'administrator:Veeam123!',
    '-X','POST',
    $exportCreds,
    '-H', 'accept: application/json',
    '-H', 'Content-Type: application/json',
    '-H', 'x-api-version: 1.0-rev2',
    '-H', $authString,
    '-d', '{\"names\":[]}'

    RunString($string)
}
function GetManagedServers{
    $authString = "Authorization: Bearer " + $token
    $string = '--insecure','-u', 'administrator:Veeam123!',
    '-X','POST',
    $exportManagedServer,
    '-H', 'accept: application/json',
    '-H', 'Content-Type: application/json',
    '-H', 'x-api-version: 1.0-rev2',
    '-H', $authString,
    '-d', '{\"names\":[]}'

    RunString($string)
}
function GetRepos{
    $authString = "Authorization: Bearer " + $token
    $string = '--insecure','-u', 'administrator:Veeam123!',
    '-X','POST',
    $exportRepo,
    '-H', 'accept: application/json',
    '-H', 'Content-Type: application/json',
    '-H', 'x-api-version: 1.0-rev2',
    '-H', $authString,
    '-d', '{\"names\":[]}'

    RunString($string)
}
function GetProxies{
    $authString = "Authorization: Bearer " + $token
    $string = '--insecure','-u', 'administrator:Veeam123!',
    '-X','POST',
    $exportProxy,
    '-H', 'accept: application/json',
    '-H', 'Content-Type: application/json',
    '-H', 'x-api-version: 1.0-rev2',
    '-H', $authString,
    '-d', '{\"names\":[]}'

    RunString($string)
}

function GetJobs{
    $authString = "Authorization: Bearer " + $token
    $string = '--insecure','-u', 'administrator:Veeam123!',
    '-X','POST',
    $exportJobs,
    '-H', 'accept: application/json',
    '-H', 'Content-Type: application/json',
    '-H', 'x-api-version: 1.0-rev2',
    '-H', $authString,
    '-d', '{\"names\":[]}'

    RunString($string)
}
function RunString {
    param(
        $target
    )
    & $curlEXE @target
}


$jobs = GetJobs
$jobs | out-file JobExport.json

$creds = GetCreds
#$creds |  out-file CredExport.json

$mgdServer = GetManagedServers
#$mgdServer | out-file managedservers.json

#GetRepos | Out-File repos.json

#GetProxies | out-file proxies.json -Encoding utf8

<#
Next Steps:
1. Import Creds & passwords
2. Import managed servers
3. Import repos
4. Import Proxies
5. Import jobs
#>