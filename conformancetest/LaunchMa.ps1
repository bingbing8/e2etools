<#
    Tests of cross version compatability for container hosts and images
    Tests assume host VHD with all required package installed in located at $BaseVHDDir
#>

param (
    # The path to the jason file containing setup information.
    [Parameter(Mandatory=$True)] [string] $VMSize,
    [Parameter(Mandatory = $true)] [string] $RunId,
    [Parameter(Mandatory = $true)] [string] $ResourceGroupName,
    [Parameter(Mandatory = $true)] [string] $region,
    [string] $PackageVersion = "0.0.14",
    [string] $VMOwner = "ContainerPlatDNI-akscluster",
    [string] $CertThumbprint = "F4E78788DDD9EC40C37888D3D9BEA592FC6D07CB",
    [string] $CertFilePath = "$PSScriptRoot\containerplattest.pfx",
    [string] $ConfigVersion = "3.0",
    [string] $MonitoringAccount = "containerplatformhost",
    [string] $CertStoreLocation = "LocalMachine\My",
    [string] $GenevaMonitoringAgentPackageFolder = "$PSScriptRoot",
    [string] $AtlasEnvironmentType = "DNITest",
    [string] $AtlasCustomer = "AKS",
    [SecureString] $CertPassword = $null
) 

$env:AtlasEnvironmentType=$AtlasEnvironmentType
$env:AtlasCustomer = $AtlasCustomer
$env:VMOwner=$VMOwner
$env:VMSize=$VMSize
$env:MONITORING_TENANT=$RunId
$env:MONITORING_ROLE="AKSConformance"
$env:MONITORING_DATA_DIRECTORY=join-path $env:LocalAppData Monitoring
$env:MONITORING_ROLE_INSTANCE="$($ResourceGroupName)_$env:COMPUTERNAME"
$env:MONITORING_GCS_ENVIRONMENT="DiagnosticsPROD"
$env:MONITORING_GCS_ACCOUNT="ContainerPlatformWarm"
$env:MONITORING_GCS_NAMESPACE="ContainerPlatformWarm"
$env:MONITORING_GCS_REGION=$region
$env:Location=$region
$env:MONITORING_GCS_THUMBPRINT=$CertThumbprint
$env:MONITORING_GCS_CERTSTORE=$CertStoreLocation
$env:MONITORING_CONFIG_VERSION=$ConfigVersion
$env:MDM_MONITORING_ACCOUNT=$MonitoringAccount

if(-Not (Test-Path "HKLM:\Software\Microsoft\ContainerPlatform"))
{
    New-Item "HKLM:\Software\Microsoft\ContainerPlatform" -Force    
}

if($null -eq (Get-ItemProperty -Path "HKLM:\Software\Microsoft\ContainerPlatform" -Name "PackageVersion" -ErrorAction Ignore))
{    
    New-ItemProperty -Path "HKLM:\Software\Microsoft\ContainerPlatform" -Name "PackageVersion" -Value "$PackageVersion" -PropertyType String -Force
}
else
{
    Set-ItemProperty -Path "HKLM:\Software\Microsoft\ContainerPlatform" -Name "PackageVersion" -Value "$PackageVersion" -Force
}

if($CertPassword)
{
    $pwd = $CertPassword
}
else
{
    $pwd = ConvertTo-SecureString -String "1234" -Force -AsPlainText
}
$cert = Import-PfxCertificate -FilePath $CertFilePath -CertStoreLocation "Cert:\$CertStoreLocation" -Password $pwd
<#if(-Not (Test-Path "$PSScriptRoot\Monitoring\Agent\MonAgentLauncher.exe" -PathType Leaf))
{
    $gmaPackages = Get-ChildItem "$GenevaMonitoringAgentPackageFolder\*.zip"
    if($gmaPackages)
    {
        $package = $gmaPackages[0]
        Expand-Archive $package.FullName -DestinationPath $PSScriptRoot -Force
    }
    else
    {
        throw "No package geneva monitoring agent found under $GenevaMonitoringAgentPackageFolder"
    }
}#>
if(Test-Path "C:\Packages\Plugins\Microsoft.Azure.Geneva.GenevaMonitoring\2.20.0.1\Monitoring\Agent\MonAgentLauncher.exe" -PathType Leaf)
{
    & C:\Packages\Plugins\Microsoft.Azure.Geneva.GenevaMonitoring\2.20.0.1\Monitoring\Agent\MonAgentLauncher.exe -useenv
}
else
{
    throw "No package geneva monitoring agent found under C:\Packages\Plugins\Microsoft.Azure.Geneva.GenevaMonitoring\2.20.0.1\Monitoring\Agent\"
}

<#$job = Start-Job { & $PSScriptRoot\Monitoring\Agent\MonAgentLauncher.exe -useenv}

$time = [System.Diagnostics.Stopwatch]::StartNew()
while($true)
{
    $ret = Receive-Job $job
    if($ret -imatch "Configured cpu rate for job")
    {
        Write-Host "Agent swork as expected ..."
        return $true
    }
    elseif($time.Elapsed.TotalMinutes -gt 3)
    {
        Write-Host "Agent does not work as expected after 3 mininues; stop Genewa agent"
        Stop-job $job
        return $false
    }
}#>