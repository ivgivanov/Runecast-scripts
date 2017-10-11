#Get-Module -Name VMware* -ListAvailable | Import-Module #Importing PowerCLI modules in case it was initated from directly from PowerShell, uncomment if needed
#Variables - Step1#
$vCenter = 'myvCenter.my.domain' #vCenter Server where to deploy Runecast
$username = 'administrator@vsphere.local' #vCenter username
$password = 'VMware1!' #Password for the provided username
$cluster= 'My-VSAN-Cluster' #Cluster where to deploy Runecast
$datastore = 'vsanDatastore' #Datastore name
$ovaPath = 'C:\Runecast\1.5.6.0\RCapp_OVF10.ova' #Path to the OVA
$rcHostname = 'rc-cli' #Hostname for Runecast Analyzer
$rcVMname = 'Runecast Analyzer' #VM name
$rcFQDN = '' #Leave blank if you don't have valid DNS record
$rcDeployOption = 'small' #accepted values: small, medium, large
$rcIPprotocol = 'IPv4'
$rcNetwork = 'VM Network' #Network name
$rcGateway = '10.1.0.1'
$rcDNS = '10.1.0.2' #Comma separated if multiple, leave blank if DHCP desired
$rcIP = '10.1.0.3' #Leave blank if DHCP desired
$rcNetMask = '255.255.0.0' #Leave blank if DHCP desired
$rcUser = 'rcuser' #The default local user of Runecast Analyzer
$rcPassword = 'Runecast!' #Passowrd for the Runecast user
$vcToAdd = 'myvCenter.my.domain' #vCenter to add to Runecast after deployment
$vcPort = 443
$vcUser = 'administrator@vsphere.local'
$vcPassword = 'VMware1!'

#Do not edit beyond here

#Accept self signed certificates
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

#Deploying Runecast Analyzer - Step 2#
Write-Host "Connecting to $vCenter..." -foregroundcolor "yellow"
Connect-VIServer -server $vCenter -User $username -Password $password

$vmHost = Get-Cluster -Name $cluster | Get-VMHost | Where-Object {$_.ConnectionState -eq "Connected"} | Get-Random
$portGroup = Get-VirtualPortGroup -Host $vmHost -Name $rcNetwork
$targetDatastore = Get-Datastore -Name $datastore

$ovaConfig = Get-OvfConfiguration -Ovf $ovaPath
$ovaConfig.Common.vami.hostname.value = $rcHostname
$ovaConfig.DeploymentOption.Value = $rcDeployOption
$ovaConfig.IpAssignment.IpProtocol.Value = $rcIPprotocol
$ovaConfig.NetworkMapping.Network_1.Value = $portGroup
$ovaConfig.vami.Runecast_analyzer.gateway.Value = $rcGateway
$ovaConfig.vami.Runecast_analyzer.DNS.Value = $rcDNS
$ovaConfig.vami.Runecast_analyzer.ip0.Value = $rcIP
$ovaConfig.vami.Runecast_analyzer.netmask0.Value = $rcNetMask

Write-Host "Deploying Runecast Analyzer..." -foregroundcolor "yellow"
$RC = Import-VApp -Source $ovaPath -OvfConfiguration $ovaConfig -Name $rcVMname -VMHost $vmHost -Datastore $targetDatastore -DiskStorageFormat "Thin"

Write-Host "Starting $rcVMname" -foregroundcolor "yellow"
Start-VM -VM $RC | Out-Null

Write-Host "Disconnecting from $vCenter..." -foregroundcolor "yellow"
Disconnect-VIServer -Confirm:$false

#Waiting Runecast Analyzer to load - Step 3#
if ($rcFQDN -eq '') {
	$baseUrl = "https://$rcIP/rc2"
} else {
	$BaseUrl = "https://$rcFQDN/rc2"
}
$numTries = 60 # 5 minutes timeout
do {
	Write-Host "Waiting for Runecast Analyzer to load..." -foregroundcolor "yellow"
	Start-Sleep -s 5
	$numTries--
	try { $queryRC = Invoke-WebRequest -Uri $baseUrl } catch { Write-Host "Not ready" }
} until ($queryRC.StatusCode -eq '200' -Or $numTries -lt 1)

if ($numTries -eq 0) {
	Write-Host "Timeout reached. Giving up..."
	exit
} else { Write-Host "Runecast Analyzer is up" }

#Configuration - Step 4#
$credentials = $username + ':' + $password
$bytes = [System.Text.Encoding]::UTF8.GetBytes($credentials)
$encryptedCredentials = [System.Convert]::ToBase64String($bytes)
$headers = @{"Authorization"="Basic $encryptedCredentials";"Content-Type"="application/json";"Accept"="application/json"}
$url = $BaseUrl+"/api/v1/users/local/$rcUser/tokens"

$body = '{
	"description": "Auto config",
    "password" : "'+$rcPassword+'"

}'
Write-Host "Requesting access token..." -foregroundcolor "yellow"
$getToken = Invoke-WebRequest -Uri $url -Method Post -Body $body -Headers $headers

if ($getToken -ne $null) {
    if ($getToken.StatusCode -eq '200') {
		$jsonContent = $getToken.Content | ConvertFrom-Json
		$token = $jsonContent.token
		Write-Host "Token received"
    }
} else { Write-Host 'Request not successful' }

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