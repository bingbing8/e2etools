
if(-Not (Test-path c:\test -PathType Container))
{
    New-Item c:\test -ItemType Directory -force
}
$driverPath = "c:\test\MLNX_VPI_WinOF-5_50_54000_All_win2019_x64.exe"
if(-Not (Test-Path $driverPath -PathType Leaf))
{
    Invoke-WebRequest -Uri https://mywinimgbldstg.blob.core.windows.net/mywinimgbldcontr/MLNX_VPI_WinOF-5_50_54000_All_win2019_x64.exe -OutFile c:\test\MLNX_VPI_WinOF-5_50_54000_All_win2019_x64.exe
}
start-process -Wait -FilePath c:\buildActions\MLNX_VPI_WinOF-5_50_54000_All_win2019_x64.exe '/s','/v"/qn'
Get-NetAdapter