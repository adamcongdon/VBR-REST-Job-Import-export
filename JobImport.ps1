<#
Next Steps:
1. Import Creds & passwords
    Passwords may not be passed as blank values
2. Import managed servers
3. Import repos
    - remove default backup repository
4. Import Proxies
    - remove default proxies
5. Import jobs
#>

$curlEXE = 'C:\Program Files\Git\mingw64\bin\curl.exe'
$serverAddress = "https://devbox:9419"

#files ! all files need double quotes replaced with single quotes
$managedServerJson = Get-Content "managedservers.json"
$managedServerJson = $managedServerJson.Replace('"', "'")


# ! Need to update mount hosts.
$repoJson = Get-content "repos.json"
$repoJson = $repoJson.Replace('"', "'")
$proxyJson = Get-Content "proxies.json"
$proxyJson = $proxyJson.Replace('"', "'")
#$credsJson = Get-Content -Raw .\CredExport.json | Out-String  # -Encoding utf8 # | ConvertTo-Json
$credsJson = Get-Content .\CredExport.json   # -Encoding utf8 # | ConvertTo-Json

$credsJson = $credsJson.Replace('"', "'")
$jobJson =  Get-Content "JobExport.json"
$jobJson = $jobJson.Replace('"', "'")

$importJobs = $serverAddress +  "/api/v1/automation/jobs/import"
$importCreds = $serverAddress + "/api/v1/automation/credentials/import"
$importManagedServer = $serverAddress + "/api/v1/automation/managedServers/import"
$importRepo = $serverAddress + "/api/v1/automation/repositories/import"
$importProxy = $serverAddress + "/api/v1/automation/proxies/import"

#get Token
$TokenLink = $serverAddress +'/api/oauth2/token'
$getTokenString = PostString($TokenLink)
$tokenString = & $curlEXE @getTokenString
$t = $tokenString | ConvertFrom-Json
$token = $t.access_token



function GetCreds{
    $authString = "Authorization: Bearer " + $token
    $string =  '--insecure','-u', 'administrator:Veeam123!',
    '-X','POST',
    $importCreds,
    '-H', 'accept: application/json',
    '-H', 'Content-Type: application/json',
    '-H', 'x-api-version: 1.0-rev1',
    '-H', $authString,
    '-d',  $credsJson

    RunString($string)
}
function GetManagedServers{
    $authString = "Authorization: Bearer " + $token
    $string = '--insecure','-u', 'administrator:Veeam123!',
    '-X','POST',
    $importManagedServer,
    '-H', 'accept: application/json',
    '-H', 'Content-Type: application/json',
    '-H', 'x-api-version: 1.0-rev1',
    '-H', $authString,
    '-d', $managedServerJson

    RunString($string)
}
function GetRepos{
    $authString = "Authorization: Bearer " + $token
    $string = '--insecure','-u', 'administrator:Veeam123!',
    '-X','POST',
    $importRepo,
    '-H', 'accept: application/json',
    '-H', 'Content-Type: application/json',
    '-H', 'x-api-version: 1.0-rev2',
    '-H', $authString,
    '-d', $repoJson

    RunString($string)
}
function GetProxies{
    $authString = "Authorization: Bearer " + $token
    $string = '--insecure','-u', 'administrator:Veeam123!',
    '-X','POST',
    $importProxy,
    '-H', 'accept: application/json',
    '-H', 'Content-Type: application/json',
    '-H', 'x-api-version: 1.0-rev2',
    '-H', $authString,
    '-d', $proxyJson

    RunString($string)
}

function GetJobs{
    $authString = "Authorization: Bearer " + $token
    $string = '--insecure','-u', 'administrator:Veeam123!',
    '-X','POST',
    $importJobs,
    '-H', 'accept: application/json',
    '-H', 'Content-Type: application/json',
    '-H', 'x-api-version: 1.0-rev2',
    '-H', $authString,
    '-d', $jobJson

    RunString($string)
}

function GetSessionStatus{
    param($session)
    $authString = "Authorization: Bearer " + $token
    $string = '--insecure','-u', 'administrator:Veeam123!',
    '-X','GET',
    $session,
    '-H', 'accept: application/json',
    #'-H', 'Content-Type: application/json',
    '-H', 'x-api-version: 1.0-rev1',
    '-H', $authString
    #'-d', $jobJson

    RunString($string)
}
function RunString {
    param(
        $target
    )
    & $curlEXE @target
}

function WaitForComplete{
    param($sessionId)
    $sessionString = $serverAddress + "/api/v1/automation/sessions/" + $sessionId.id
    $breaker = $true
    $sessionInfo;
    while($breaker){
        $sessionInfo = GetSessionStatus($sessionString)| ConvertFrom-Json
        if($sessionInfo.state -ne "Working"){
            $breaker = $false
        }
        write-host("working...")
        Start-Sleep -Seconds 5
    }
    if($sessionInfo.result.result -eq "Failed"){
        [System.Windows.MessageBox]::Show('Failure detected during import.')
    } 
    write-host("done")

}

$credSession = GetCreds | ConvertFrom-Json
WaitForComplete($credSession)

$mSession = GetManagedServers | ConvertFrom-Json
WaitForComplete($mSession)

$repoSession = GetRepos | ConvertFrom-Json
WaitForComplete($repoSession)

$proxySession = GetProxies | ConvertFrom-Json
WaitForComplete($proxySession)

$jobSession = GetJobs | ConvertFrom-Json
WaitForComplete($jobSession)
