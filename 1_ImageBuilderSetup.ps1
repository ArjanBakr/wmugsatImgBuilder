#added break in case the script is run by accident
break

#regionrequiredparameters
Set-ExecutionPolicy bypass -Scope Process -Force
$SCRIPT_PARENT = Get-Location
#endregion

#regionHashTable
#Create config hash table that can be used in the rest of the steps. All information in one hash table for easy of use
$config = @{
    "ricDrive" = "E:\";
    "ricFreeSpace" = "280";
    "ricDriveLabel" = "ProgData";
    "ricWinFeature" = "Hyper-V","RSAT-Hyper-V-Tools","UpdateServices-Services","UpdateServices-RSAT","UpdateServices-UI","UpdateServices-WidDB";
}
#endregion

#regionazurermmodule
Install-PackageProvider -Name NuGet -Force
Install-module -Name AzureRM -verbose -force
#endregion

#regiondownloadsoftware
#Download all required software from Azure Storage Account
$azureStorageAccountName = 'wmugsatstorage01'
$azureStorageSourceFolder = 'Setup'
$AzureStorageSourceFolderVersion = '1.0.1'
$AzureStorageFileShare = 'resources'
$destination = $(Join-Path -Path $SCRIPT_PARENT -ChildPath 'Source')
$saKey = '?sv=2017-11-09&ss=f&srt=sco&sp=rl&se=2018-07-31T17:13:49Z&st=2018-06-24T09:00:00Z&spr=https&sig=qUyvQCxosQy40Ie83DAKgj%2FeJAGu6HYNCaOUdO0UwfQ%3D'
$storageContext = New-AzureStorageContext -StorageAccountName $azureStorageAccountName -SasToken $saKey
$arrContent = Get-AzureStorageFile -ShareName $azureStorageFileShare -Path "$($azureStorageSourceFolder)/$($azureStorageSourceFolderVersion)" -Context $storageContext | Get-AzureStorageFile
foreach ($item in $arrContent) {$item.DownloadToFile("$destination\$($item.Name)",1)}
#endregion


#regionmodules
#Copy required modules to PowerShell module folder
$sourceFolder = Join-Path -Path $SCRIPT_PARENT -ChildPath 'Source\Modules'
$destinationFolder = Join-Path -Path $env:ProgramFiles -ChildPath 'WindowsPowerShell\Modules'
Copy-Item -Path (join-path -Path $sourceFolder -ChildPath '*') -destination $destinationFolder -Force -Recurse
#endregion

#regionchangecdromdriveLetter
Set-WmiInstance -InputObject ( Get-WmiObject -Class Win32_volume -Filter "DriveLetter = 'e:'" ) -Arguments @{DriveLetter='Z:'}
#endregion


#regiondatadisk
#Check or create the presence of the E: disk with enough free space
$ricDriveLetter = $config.ricDrive -replace(":\\","")
$diskNumber = (Get-Disk | Where-Object {($_.Size /1gb) -ge $($config.ricFreeSpace)}).Number
Initialize-Disk -Number $diskNumber -PartitionStyle GPT -ErrorAction SilentlyContinue
New-Partition -UseMaximumSize -DriveLetter $ricDriveLetter -DiskNumber $diskNumber
Format-Volume -DriveLetter $ricDriveLetter -FileSystem NTFS -NewFileSystemLabel $config.ricDriveLabel
#endregion

#regioncmtrace
#Copy CMTrace
Copy-Item -Path (Join-Path -Path $SCRIPT_PARENT -ChildPath 'Source\CMTrace.exe') -Destination $config.ricDrive -Force -Recurse
#endregion


#regionfeatures
#Add the required windows features
foreach ($feature in $config.ricWinFeature.Split(",")) {Add-WindowsFeature -Name $feature -IncludeManagementTools}
#endregion

#regionrestartcomputer
restart-computer -Force
#endregion


