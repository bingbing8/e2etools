[CmdletBinding()]
Param (
    [Parameter(Mandatory = $true)]
    [string] $ScenarioName,

    [Parameter(Mandatory = $true)]
    [string] $PackageVersion,

    [Parameter(Mandatory = $true)]
    [string] $AccountKey,
    
    [string] $AccountName = "cirruscontainerplat",

    [string] $ContainerName = "containerplat-pkg",

    [string] $AgentVMSize = "Standard_D4s_V3",

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
        
    $xmlObject.testsuite.testcase | Where-Object { $_.skipped -eq $null } |  ForEach-Object {
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

$OutputFilePath = Join-Path $LogFileDirectory "$($TableName).csv"
if (Test-Path $OutputFilePath -PathType Leaf) {
    Remove-Item $OutputFilePath -Force
}

$retObj | Export-Csv $OutputFilePath -NoTypeInformation -Force
      
az storage blob upload --account-name $AccountName --account-key $AccountKey --container-name $ContainerName --file $OutputFilePath --name $TableName
    
Write-Host "total: $total"
Write-Host "Unknown result: $($total-$passedNum-$failedNum-$skippedNum)"
Write-Host "passed: $passedNum"
Write-Host "failed: $failedNum"


