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
    "hypervFolder" = "VMs";
    "hypervLANName" = "HVLAN";
    "hypervREFSwitchName" = "MDTREFIMGLAN";
    "hypervLANNetwork" = "192.168.35.0/24";
    "hypervLANIP" = "192.168.35.1";
    "mdtDeploymentFolder" = "Deploymentshare";
    "mdtLocalUser" = "MDTUser";
    "mdtLocalGroup" = "MDTUsers";
    "mdtLocalUserPwd" = "MDTP@ssw0rd!"; #Password will only be used during the creation of new reference images to connect to the MDT server
    "mdtEventFolder" = "EventShare";
    "mdtLogFolder" = "Logs";
    "mdtCaptureFolder" = "Captures";
}
#endregion


#regiondownloadsoftware
#Download all required software from Azure Storage Account
$azureStorageAccountName = 'wmugsatstorage01'
$azureStorageSourceFolder = 'Config'
$AzureStorageSourceFolderVersion = '1.0.1'
$AzureStorageFileShare = 'resources'
$destination = $(Join-Path -Path $config.RicDrive -ChildPath $config.mdtDeploymentFolder)
$saKey = '?sv=2017-11-09&ss=f&srt=sco&sp=rl&se=2018-06-23T17:00:00Z&st=2018-06-18T17:20:16Z&spr=https&sig=ajsTukvTNI2CFwZ143SuyozXTmI%2FTEiP3XFGN7Cgflg%3D'
$storageContext = New-AzureStorageContext -StorageAccountName $azureStorageAccountName -SasToken $saKey

Function Get-AzureFileStorageContent
{
    Param
        (
            [parameter(mandatory=$true)]
            $Source,
            [parameter(mandatory=$true)]
            $Destination,
            [parameter(mandatory=$true)]
            $StorageContext,
            [parameter(mandatory=$true)]
            $ShareName

        )

    $arrContent = Get-AzureStorageFile -ShareName $shareName -Path $Source -Context $storageContext | Get-AzureStorageFile
    foreach ($item in $arrContent)
    {
        if ($item.GetType().Name -eq "CloudFileDirectory")
        {
            Get-AzureFileStorageContent -Source "$Source/$($item.Name)" -Destination "$Destination/$($item.Name)" -StorageContext $StorageContext -ShareName $ShareName
        }
        else
        {
            if ($item.GetType().Name -eq "CloudFile")
            {
                if (!(Test-Path -Path $Destination))
                {
                    New-Item -Path $Destination -ItemType Directory
                }
                if (Test-Path "$Destination\$($item.Name)")
                {
                    #do nothing, file has already been downloaded
                }
                else
                {
                    $item.DownloadToFile("$Destination\$($item.Name)",1)
                }
            }
            else
            {
                #unknown type, do nothing
            }
        }
    }
}


Get-AzureFileStorageContent -Source "$($AzureStorageSourceFolder)/$($AzureStorageSourceFolderVersion)" -Destination $destination -StorageContext $storageContext -ShareName $azureStorageFileShare
#endregion

#regiondownloadvisualc++runtime
$vcScriptPath = Join-Path -Path $SCRIPT_PARENT -ChildPath 'Get-AllVCRuntimes'
& (Join-Path -Path $vcScriptPath -ChildPath 'Get-Downloads.ps1') -DownloadFile (Join-Path -Path $vcScriptPath -ChildPath 'download.xml') -DownloadFolder (Join-Path -Path $config.ricDrive -ChildPath "$($config.mdtDeploymentFolder)\Applications\InstallVCRuntime 1.00\Source")
E:\Deploymentshare\Applications\InstallVCRuntime 1.00\Source


#regioncreatebootimage
Import-Module "E:\Program Files\Microsoft Deployment Toolkit\bin\MicrosoftDeploymentToolkit.psd1"
New-PSDrive -Name "DS001" -PSProvider MDTProvider -Root "E:\Deploymentshare"
update-MDTDeploymentShare -path "DS001:" -Force -Verbose
#endregion



#regionLinks
https://github.com/DeploymentBunny/Files
https://github.com/DeploymentBunny
#endregion

#regiontips
Run WSUS clean before each image creation. It will flush out unused updates and preview updates you do not want
Version history can be kept in TS comments
#endregion
