<#
.Synopsis
  Create a new aks-engine cluster

.Description
  Create a new aks-engine cluster

.Parameter Subscriptionid
  Azure subsription for aks-engine deployment

.Parameter ResourceGroupName
  Resource group name for AKS-Engine clsuter 

.Parameter ServicePrincipalIdAndSecret
  The client id and client secret associated with the AAD application / service principal

.Parameter sshpublicKeyPath
  The path to the ssh public key file. The key is used to access the linux master node

.Parameter apimodelFilePath
  The local path to the API model file which the cluster setup against. 
  For upstream tests, the api module files can be found at https://github.com/kubernetes-sigs/windows-testing/tree/master/job-templates 

.Parameter AKSEnginePath
  The local path to aks-engine.exe. only v0.57.0 or above support hyperv isolated runtime deployment

.Parameter Location
  The location where to deploy this cluster

.Parameter DnsNamePrefix
  The DNS name prefix for the cluster. Default is set to the Resource group name if it is not specfied. 
  A DnsNamePrefix which forms part of the hostname for the cluster.
  If you are not building a private cluster, the value of DnsNamePrefix must produce a unique fully-qualified
  domain name DNS record composed of <value of DnsNamePrefix>.<value of location>.cloudapp.azure.com.

.Parameter KubernetesVersion
  Kubernetes version

.Parameter WindowsContainerdURL
  The URL to the windows container package

.Parameter WindowsProfileAdminUser
  The admin user name of windows agent nodes

.Parameter WindowsProfileAdminpassword
  The admin user password of windows agent nodes

.Parameter WindowsProfileSku
  The Sku of windows agent node

.Parameter WindowsImageSourceUrl
  The source Url of windows image vhd

.Parameter NodeVmSize
  The vm size of the windows agent node

.Parameter NodeVmCount
  The count of windows agent nodes

.Example    
    $secret = ConvertTo-SecureString -AsPlainText "<your secret string>" -Force
    $spnCred = New-Object -TypeName PSCredential -ArgumentList "cae4de68-6c6b-46f5-a50b-8bcb65cccede", $secret
    $windowscred = ConvertTo-SecureString -AsPlainText "p@ssw0rd" -Force
    New-AKSEngineCluster.ps1 -Subscriptionid "b5341903-894f-4576-aa51-7bac74bd2e5a" -ResourceGroupName aksHyperv -ServicePrincipalIdAndSecret $spnCred `
     -sshpublicKeyPath C:\users\<user>\.ssh\id_rsa.pub -apimodelFilePath F:\windows-testing\job-templates\kubernetes_2004_containerd_hyperv.json `
     -AKSEnginePath F:\aks-engine-v0.57.0-windows-amd64\aks-engine.exe -Location westus2 -DnsNamePrefix aksypervtest `
     -KubernetesVersion 1.19 -Verbose -linuxProfileAdminUser azuser -WindowsProfileAdminUser windowsuser -WindowsProfileAdminpassword $windowscred
#>
[CmdletBinding()]
Param (
    [ValidateNotNullOrEmpty()]    
    [string] $Subscriptionid = "b5341903-894f-4576-aa51-7bac74bd2e5a",

    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [PSCredential]$ServicePrincipalIdAndSecret,

    [Parameter(Mandatory = $true)]
    [ValidateScript( {
        if(-Not ($_ | Test-Path) ) {
            throw "File or folder does not exist"
        }
        if(-Not ($_ | Test-Path -PathType Leaf) ) {
            throw "The Path argument must be a file."
        }
        if($_ -notmatch "(\.pub)") {
            throw "The sshpublicKeyPath must be of type pub"
        }
        return $true
    } )]
    [System.IO.FileInfo] $sshpublicKeyPath,

    [Parameter(Mandatory = $true)]
    [ValidateScript( {
        if(-Not ($_ | Test-Path) ) {
            throw "File or folder does not exist"
        }
        if(-Not ($_ | Test-Path -PathType Leaf) ) {
            throw "The Path argument must be a file."
        }
        if($_ -notmatch "(\.json)") {
            throw "The apimodelFilePath file must be of type json"
        }
        return $true
    } )]    
    [System.IO.FileInfo] $apimodelFilePath,

    [Parameter(Mandatory = $true)]
    [ValidateScript( {
        if(-Not ($_ | Test-Path) ) {
            throw "File or folder does not exist"
        }
        if(-Not ($_ | Test-Path -PathType Leaf) ) {
            throw "The Path argument must be a file."
        }
        if($_ -notmatch "aks-engine") {
            throw "The aks-engine file name must be aks-engine.exe"
        }
        return $true
    } )]    
    [System.IO.FileInfo] $AKSEnginePath,

    [ValidateNotNullOrEmpty()]
    [string] $Location = "westus2",

    [ValidateNotNullOrEmpty()]
    [string] $DnsNamePrefix = $ResourceGroupName,

    [ValidateSet("1.16","1.17","1.18","1.19","1.20")]
    [string] $KubernetesVersion = "1.19",

    [ValidateNotNullOrEmpty()]
    [string] $linuxProfileAdminUserName,

    [ValidateNotNullOrEmpty()]
    [string] $WindowsContainerdURL,

    [ValidateNotNullOrEmpty()]
    [string] $WindowsProfileAdminUserName,

    [ValidateNotNull()]
    [SecureString] $WindowsProfileAdminpassword,

    [ValidateNotNullOrEmpty()]
    [string] $WindowsProfileSku,

    [ValidateNotNullOrEmpty()]    
    [string] $WindowsImageSourceUrl,

    [ValidateNotNullOrEmpty()]
    [string] $NodeVmSize,

    [int] $NodeCount = 2
)

Connect-AzAccount -Credential $ServicePrincipalIdAndSecret -Subscription $Subscriptionid -Tenant '72f988bf-86f1-41af-91ab-2d7cd011db47' -ServicePrincipal
$context = Get-AzContext

if($null -eq $context.Account) {
    $message = "You are not logged into Azure. Please run Connect-AzAccount to log in first."
    throw $message 
}

try
{
    if($context.Subscription.Id -ine $Subscriptionid )
    {
        Set-AzContext -SubscriptionId $Subscriptionid -ErrorAction Stop
    }
}
catch
{
    $message =  "Set-AzContext failed. Please make sure you have valid SubscriptionId"
    throw $message 
}

$rg = Get-AzResourceGroup -Name $ResourceGroupName -Location $Location -ErrorAction Ignore
if(-not $rg)
{
    New-AzResourceGroup -Name $ResourceGroupName -Location $location
}

$spnid = $ServicePrincipalIdAndSecret.UserName

$spnobj = Get-AzADServicePrincipal -ServicePrincipalName $spnid -ErrorAction Ignore
if(-Not $spnobj)
{
    throw "service principal name $spnid is not found"
}
$roleAssignment = Get-AzRoleAssignment -ResourceGroupName $ResourceGroupName -RoleDefinitionName Contributor -ObjectId $spnobj.Id -ErrorAction Ignore
if(-Not $roleAssignment)
{
    New-AzRoleAssignment -ResourceGroupName $ResourceGroupName -RoleDefinitionName Contributor -ObjectId $spnobj.Id
}

#load template
$inJson = Get-Content $apimodelFilePath.FullName | ConvertFrom-Json

#set custom values
if ($PSBoundParameters.ContainsKey("KubernetesVersion"))
{
    $inJson.properties.orchestratorProfile.orchestratorRelease = $KubernetesVersion
}
elseif([String]::IsNullOrEmpty($inJson.properties.orchestratorProfile.orchestratorRelease))
{
    $inJson.properties.orchestratorProfile.orchestratorRelease = $KubernetesVersion
}

$inJson.properties.masterProfile.dnsPrefix = $DnsNamePrefix
$inJson.properties.linuxProfile.ssh.publicKeys[0].keyData = [string](Get-Content $sshpublicKeyPath)
$inJson.properties.servicePrincipalProfile.clientId = $spnid
$spnsecret = $ServicePrincipalIdAndSecret.GetNetworkCredential().Password
$inJson.properties.servicePrincipalProfile.secret = $spnsecret

#optional parameters to override those in the template
#The script currently assumes the properties present in the api model
#Todo: check presence of the item; add-member if the item is not contained in api model file
if ($PSBoundParameters.ContainsKey("WindowsContainerdURL"))
{
    $inJson.properties.orchestratorProfile.kubernetesConfig.windowsContainerdURL = $WindowsContainerdURL
}

if ($PSBoundParameters.ContainsKey("linuxProfileAdminUserName"))
{
    $inJson.properties.linuxProfile.adminUsername = $linuxProfileAdminUserName
}

if ($PSBoundParameters.ContainsKey("WindowsProfileAdminUserName"))
{
    $inJson.properties.windowsProfile.adminUsername = $WindowsProfileAdminUserName
}

if ($PSBoundParameters.ContainsKey("WindowsProfileAdminpassword") -and ($null -ne $WindowsProfileAdminpassword))
{
    $adminPassword = [PSCredential]::new(".", $WindowsProfileAdminpassword).GetNetworkCredential().Password
    $inJson.properties.windowsProfile.adminPassword = $adminPassword
}

if ($PSBoundParameters.ContainsKey("WindowsProfileSku"))
{
    $inJson.properties.windowsProfile.windowsSku = $WindowsProfileSku
}

if ($PSBoundParameters.ContainsKey("WindowsImageSourceUrl"))
{
    $inJson.properties.windowsProfile.ImageSourceUrl = $WindowsImageSourceUrl
}

if ($PSBoundParameters.ContainsKey("NodeVmSize"))
{
    $vmsize = Get-AzVMSize -Location $Location | Where-Object -Property Name -ieq $NodeVmSize
    if(-not $vmsize)
    {
        throw "vm size $NodeVmSize is not found in $Location; please enter valid vm size "
    }
    $inJson.properties.agentPoolProfiles.vmSize = $NodeVmSize
}

if ($PSBoundParameters.ContainsKey("NodeCount"))
{
    $inJson.properties.agentPoolProfiles.count = $NodeCount
}


$adminUsernameToMaster = $inJson.properties.linuxProfile.adminUsername
$tempapiModelFile = join-path $env:TEMP $apimodelFilePath.Name
if(Test-Path $tempapiModelFile -PathType Leaf)
{
    Remove-item $tempapiModelFile -Force
}

$inJson | ConvertTo-Json -Depth 5 | Out-File -Encoding ascii -FilePath $tempapiModelFile
$outputDir = Join-Path $PSScriptRoot "_output\$DnsNamePrefix"
#generate ARM template
Invoke-Expression -command "$($AKSEnginePath.FullName) generate -m ""$tempapiModelFile"" -o ""$outputDir"""
try
{
    #deploy ARM template
    $deploy = New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -Name "deployment-$resourceGroupName" `
                            -TemplateFile $outputDir\azuredeploy.json -TemplateParameterFile $outputDir\azuredeploy.parameters.json `
                            -Mode Incremental -Verbose -ErrorAction Stop
    $masterNode = Get-AzPublicIpAddress -ResourceGroupName $resourceGroupName | Where-Object {$_.Name -imatch "k8s-master-ip-$($DnsNamePrefix)-*"} 
    $privateKeyFilePath = $sshpublicKeyPath.FullName.Replace($sshpublicKeyPath.Extension, "")
    Write-Host "Invoke below command to access to master node of the cluster. ($privateKeyFilePath should not have any permission to users other than current user, administrators, and local system)"
    Write-Host "ssh -i $privateKeyFilePath $($adminUsernameToMaster)@$($masterNode.IpAddress)" -ForegroundColor Green
}
catch 
{
    Write-host "Deployment failed with error:" -ForegroundColor Yellow
    $_.Exception
}
