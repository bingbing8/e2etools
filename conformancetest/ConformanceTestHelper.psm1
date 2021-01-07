function Convert-XMLResultToCSVFile
{
[CmdletBinding()]
Param (
    [Parameter(Mandatory = $true)]
    [ValidateScript( {
        if(-Not ($_ | Test-Path) ) {
            throw "Path LogFileDirectory does not exist"
        }
        if(-Not ($_ | Test-Path -PathType Container) ) {
            throw "The LogFileDirectory argument must be a directory."
        }
        return $true
    } )]    
    [string] $LogFileDirectory,

    [Parameter(Mandatory = $true)]
    [string] $ScenarioName,

    [Parameter(Mandatory = $true)]
    [string] $PackageVersion,

    [string] $AgentVMSize = "Standard_D4s_V3",

    [string] $AgentWindowsSku = "Datacenter-Core-2004-with-Containers-smalldisk",

    [string] $TableName = "K8ConformanceTestResults"
    )

    $failedNum = 0
    $passedNum = 0
    $total = 0
    $retObj = @()
    $retObj = Get-ChildItem -Path $LogFileDirectory -Filter *junit_*.xml | ForEach-Object {
        $filePath = $_.FullName
        $fileStartUtcTime = (Get-item $filePath).CreationTimeUtc
        $fileEndUtcTime = (Get-item $filePath).LastWriteTimeUtc
        if($fileStartUtcTime -gt $fileEndUtcTime)
        {
            #No file creation time is stored on linux
            $fileStartUtcTime = $fileEndUtcTime
        }
        $xmlObject =[xml](Get-Content -Path $filePath)
        
            $xmlObject.testsuite.testcase | Where-Object {$_.skipped -eq $null} |  ForEach-Object {
            $status = 'Unknown'
            $failureType = $null
            $failureMessage = $null
            $output = $null
            $total++
    
            if($_.failure -ne $null)
            {
                $failureobj =  $_.failure
                $status = 'Failed'
                $failureType = $failureobj.type
                $failureMessage = $failureobj.'#text'
                $failedNum++
            }
            else
            {
                $status = 'Passed'
                $passedNum++
            }
            $output = $_.'system-out'

            $prop = [ordered]@{
            'StartTimeStamp' = $fileStartUtcTime
            'EndTimeStamp' = $fileEndUtcTime
            'ScenarioName' = $ScenarioName
            'PackageVersion' = $PackageVersion
            'AgentVMSize' = $AgentVMSize
            'AgentWindowsSku' = $AgentWindowsSku
            'Name' = $_.name
            'RuntimeSecond' = $_.time
            'ClassName' = $_.classname
            'Status' = $status
            'FailureType' = $failureType
            'FailureMessage' = $failureMessage
            'Output' = $output
            }
            New-Object -Type PSCustomObject -Property $prop
          }
      }

      $OutputFilePath = Join-Path $LogFileDirectory "$($TableName).csv"
      if(Test-Path $OutputFilePath -PathType Leaf)
      {
        Remove-Item $OutputFilePath -Force
      }

      $retObj | Export-Csv $OutputFilePath -NoTypeInformation -Force

    Write-Host "total: $total"
    Write-Host "Unknown result: $($total-$passedNum-$failedNum-$skippedNum)"
    Write-Host "passed: $passedNum"
    Write-Host "failed: $failedNum"
}

function Push-DataToKusto
{
    #  Part 1 of 3
    #  ------------
    #  Packages location - This is an example of the location from where you extract the Microsoft.Azure.Kusto.Tools package.
    #  Please make sure you load the types from a local directory and not from a remote share.
    $packagesRoot = "C:\Program Files\PackageManagement\NuGet\Packages\Microsoft.Azure.Kusto.Tools.5.0.4\tools"

    #  Part 2 of 3
    #  ------------
    #  Loading the Kusto.Client library and its dependencies
    dir $packagesRoot\* | Unblock-File
    [System.Reflection.Assembly]::LoadFrom("$packagesRoot\Kusto.Data.dll")

    #  Part 3 of 3
    #  ------------
    #  Defining the connection to your cluster / database
    $clusterUrl = "https://kustolab.kusto.windows.net;Fed=True"
    $databaseName = "1"

    #   Option A: using Azure AD User Authentication
    $kcsb = New-Object Kusto.Data.KustoConnectionStringBuilder($clusterUrl, $databaseName)

    $adminProvider = [Kusto.Data.Net.Client.KustoClientFactory]::CreateCslAdminProvider($kcsb)
    $command = [Kusto.Data.Common.CslCommandGenerator]::GenerateTableIngestPushCommand("", $false, "")
    Write-Host "Executing command: '$command' with connection string: '$($kcsb.ToString())'"
    $reader = $adminProvider.ExecuteControlCommand($databaseName, $command)
}