<#
The purpose of this script is to migrate VBR jobs to a new server.
!! This script only migrates VMware Backup Jobs at this time due to limitations with REST API


Directions:
1. edit the variables in the CustomizeMe Section Below
2. After EXPORT, remember to manually edit the JSON exports for the following:
    a. passwords must not be empty
    b. repository mount hosts will need adjusted if target server name is different
    c. 
#>



#CustomizeMe
$sourceVbrServer = ""
$targetVbrServer = ""
$sourceVbrRestPort = "9419"
$targetVbrRestPort = "9419"
$sourceVbrCred = Get-Credential
$targetVbrCred = Get-Credential





#constants - DO NOT CHANGE
$curlEXE = 'C:\Program Files\Git\mingw64\bin\curl.exe'
$srcServer = "https://" + $sourceVbrServer + ":" + $sourceVbrRestPort
$tarServer = "https://" + $targetVbrServer + ":" + $targetVbrRestPort


#region shared
$tokenEp = "/api/oauth2/token"

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

#endregion

#region Export
$exportJobs = $srcServer +  "/api/v1/automation/jobs/export"
$exportCreds = $srcServer + "/api/v1/automation/credentials/export"
$exportManagedServer = $srcServer + "/api/v1/automation/managedServers/export"
$exportRepo = $srcServer + "/api/v1/automation/repositories/export"
$exportProxy = $srcServer + "/api/v1/automation/proxies/export"

$srcTokenLink = $srcServer + $tokenEp

#endregion