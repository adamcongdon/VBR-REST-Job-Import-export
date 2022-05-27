<#
This script is a working document designed to test the export & import of jobs.

#>

$curlEXE = 'C:\Program Files\Git\mingw64\bin\curl.exe'

$serverAddress = "https://backup-v11:9419"
$exportJobsEndpoint = "/api/v1/automation/jobs/export"
$serverTime = "/api/v1/serverTime"
$endPoint = $serverAddress + $exportJobsEndpoint

#get Token
$getTokenLink = 'https://backup-v11:9419/api/oauth2/token'
#$passString = 'grant_type=password&username=administrator&password=Veeam123!&refresh_token=&code=&use_short_term_refresh='
$getTokenString = PostString($getTokenLink)
$tokenString = & $curlEXE @getTokenString

$t = $tokenString | ConvertFrom-Json
$t | gm
$token = $t.access_token


function GetString {
    param (
        $ApiLink
    )
    $string = '--insecure','-u', 'administrator:Veeam123!',
    '-X','GET',
    $ApiLink,
    '-H', 'accept: application/json',
    '-H', 'x-api-version: 1.0-rev1'
    return $string
}
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

function GetJobs{
    $authString = "Authorization: Bearer " + $token
    $string = '--insecure','-u', 'administrator:Veeam123!',
    '-X','POST',
    $endPoint,
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
function GetServerTime{
    $timeTarget = GetString($serverAddress + $serverTime)
    RunString($timeTarget)
}

$jobs = GetJobs
$jobs | out-file JobExport.json
<#
Next Steps:
1. Import Creds & passwords
2. Import managed servers
3. Import repos
4. Import Proxies
5. Import jobs
#>

#export Creds:
function ExportCreds{
    $target = $serverAddress + "/api/v1/automation/credentials/export"
    # POST
    #$string = '--insecure', '-u',
}