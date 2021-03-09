[CmdletBinding()]
Param (
    [Parameter(Mandatory = $true)]
    [string] $ScenarioName,

    [Parameter(Mandatory = $true)]
    [string] $PackageVersion,

    [Parameter(Mandatory = $true)]
    [string] $KubernetesVersion,

    [Parameter(Mandatory = $true)]
    [string] $AccountKey,

    [string] $AccountName = "cirruscontainerplat",

    [string] $ContainerName = "k8slog",

    [string] $AgentVMSize = "Standard_D2s_V3",

    [string] $AgentWindowsSku = "Datacenter-Core-2004-with-Containers-smalldisk",

    [string] $TableName = "K8SConformanceTestResults",

    [int] $TestInstance = 0
)

az storage blob download-batch -d . --pattern *.xml -s $ContainerName --account-name $AccountName --account-key $AccountKey

$failedNum = 0
$passedNum = 0
$total = 0
$retObj = @()
$retObj = Get-ChildItem -Filter *junit_*.xml | ForEach-Object {
    $filePath = $_.FullName
    $fileStartUtcTime = (Get-item $filePath).CreationTimeUtc
    $fileEndUtcTime = (Get-item $filePath).LastWriteTimeUtc
    if ($fileStartUtcTime -gt $fileEndUtcTime) {
        #No file creation time is stored on linux
        $fileStartUtcTime = $fileEndUtcTime
    }
    $xmlObject = [xml](Get-Content -Path $filePath)
        
    $xmlObject.testsuite.testcase | Where-Object { $null -eq $_.skipped } |  ForEach-Object {
        $status = 'Unknown'
        $failureType = $null
        $failureMessage = $null
        $output = $null
        $total++
    
        if ($_.failure -ne $null) {
            $failureobj = $_.failure
            $status = 'Failed'
            $failureType = $failureobj.type
            $failureMessage = $failureobj.'#text'
            $failedNum++
        }
        else {
            $status = 'Passed'
            $passedNum++
        }
        $output = $_.'system-out'

        $prop = [ordered]@{
            'StartTimeStamp'  = $fileStartUtcTime
            'EndTimeStamp'    = $fileEndUtcTime
            'ScenarioName'    = $ScenarioName
            'PackageVersion'  = $PackageVersion
            'KubernetesVersion' = $KubernetesVersion
            'AgentVMSize'     = $AgentVMSize
            'AgentWindowsSku' = $AgentWindowsSku
            'Name'            = $_.name
            'RuntimeSecond'   = $_.time
            'ClassName'       = $_.classname
            'Status'          = $status
            'FailureType'     = $failureType
            'FailureMessage'  = $failureMessage            
            'TestInstance'    = $TestInstance
            'Output'          = $output
        }
        New-Object -Type PSCustomObject -Property $prop
    }
}

Write-Host "Total: $total"
Write-Host "Unknown result: $($total-$passedNum-$failedNum-$skippedNum)"
Write-Host "Passed: $passedNum"
Write-Host "Failed: $failedNum"

$OutputFilePath = "$($TableName).csv"
if (Test-Path $OutputFilePath -PathType Leaf) {
    Remove-Item $OutputFilePath -Force
}

Write-Host $OutputFilePath

$retObj | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1 | Set-Content $OutputFilePath

if (Test-Path $OutputFilePath -PathType Leaf) {
    Get-Item $OutputFilePath
}
else {
    Write-Host "the file doesn't exist"
}

az storage blob upload --account-name $AccountName --account-key $AccountKey --container-name $ContainerName --file $OutputFilePath --name $TableName
$expiretime = (Get-Date).ToUniversalTime().AddMinutes(180).ToString("yyyy-MM-dTH:mZ")
$sasurl = az storage blob generate-sas --account-name $AccountName --account-key $AccountKey --container-name $ContainerName --name $TableName --permission r --expiry $expiretime  --full-uri
Write-Output "##vso[task.setvariable variable=csvlogfileurl]$sasurl"
Write-Host $sasurl
