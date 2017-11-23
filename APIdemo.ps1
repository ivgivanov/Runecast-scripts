#Variables#
$rcAddress = '' #Runecast Analyzer address
$token = '' #API access token
$vcToAdd = '' #vCenter Server address to add
$vcPort = 443 #vCenter Server port
$vcUser = '' #User with sufficient permissions on the vCenter
$vcPassword = '' #User's password

#Accept self signed certificates#
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

#Do not edit beyond here#

$baseUrl = "https://$rcAddress/rc2"

#Add vCenter Server
$headers = @{"Authorization"=$token;"Content-Type"="application/json";"Accept"="application/json"}
$url = $baseUrl+"/api/v1/vcenters"
$body = '{
  "address": "'+$vcToAdd+'",
  "password": "'+$vcPassword+'",
  "port": '+$vcPort+',
  "username": "'+$vcUser+'"
}'
Write-Host "Adding $vcToAdd..." -foregroundcolor "yellow"
$addVC = Invoke-WebRequest -Uri $url -Method Put -Body $body -Headers $headers
if ($addVC -ne $null) {
    if ($addVC.StatusCode -eq '200') {
		$jsonContent = $addVC.Content | ConvertFrom-Json
		$vc = $jsonContent.address
		$vcId = $jsonContent.uid
		Write-Host "vCenter Server $vc added successfully"
    }
} else { Write-Host 'Request not successful' }

$url = $baseUrl+"/api/v1/scan/$vcId"
$body = ''
Write-Host "Triggering scan against $vc..." -foregroundcolor "yellow"
$scanVC = Invoke-WebRequest -Uri $url -Method Post -Headers $headers
if ($scanVC -ne $null) {
    if ($scanVC.StatusCode -eq '202') {
		Write-Host "Scan triggered successfully"
    }
} else { Write-Host 'Request not successful' }
