function ConvertTo-ConformanceTestResultToCSVFile
{
[CmdletBinding()]
Param (
    [Parameter(Mandatory = $true)]
    [ValidateScript( {
        if(-Not ($_ | Test-Path) ) {
            throw "File or folder does not exist"
        }
        if(-Not ($_ | Test-Path -PathType Leaf) ) {
            throw "The Path argument must be a file."
        }
        if($_ -notmatch "(\.xml)") {
            throw "The FilePath must be of type xml"
        }
        return $true
    } )]
    [System.IO.FileInfo] $FilePath,

    [Parameter(Mandatory = $true)]
    [string] $ScenarioName,

    [Parameter(Mandatory = $true)]
    [string] $PackageVersion
    )

    $xmlObject =[xml](Get-Content -Path $FilePath)
    $skippedNum = 0
    $failedNum = 0
    $passedNum = 0
    $total = 0
    $retObj = $xmlObject.testsuite.testcase | ForEach-Object {
        $status = 'Unknown'
        $failureType = $null
        $failureMessage = $null
        $output = $null
        $total++
    
        if($_.skipped -ne $null)
        {
            $status = 'Skipped'
            $skippedNum++
        }
        elseif($_.failure -ne $null)
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
        'scenarioname' = $ScenarioName
        'containerplatformpackageversion' = $PackageVersion
        'name' = $_.name
        'testduration' = $_.time
        'classname' = $_.classname
        'status' = $status
        'failureType' = $failureType
        'failureMessage' = $failureMessage
        'output' = $output
        }
        New-Object -Type PSCustomObject -Property $prop
      }
      $outputfileName = $FilePath.FullName.Replace($sshpublicKeyPath.Extension, "csv")
      $retObj | Export-Csv $outputfileName -NoTypeInformation -Force

    Write-Host "total: $total"
    Write-Host "Unknown result: $($total-$passedNum-$failedNum-$skippedNum)"
    Write-Host "passed: $passedNum"
    Write-Host "failed: $failedNum"
    Write-Host "skipped: $skippedNum"
}