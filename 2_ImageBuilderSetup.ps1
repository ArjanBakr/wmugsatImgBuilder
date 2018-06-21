#added break in case the script is run by accident
break

#regionrequiredparameters
Set-ExecutionPolicy bypass -Scope Process -Force
$SCRIPT_PARENT = Get-Location
#endregion

#regionHashTable
#Create config hash table that can be used in the rest of the steps. All information in one hash table for easy of use
$config = @{
    "localAdminPwd" = "P@ssw0rd!"; #Password will only be used during the creation of reference image and will not be included in the published images (sysprep will delete the password)
    "ricDrive" = "E:\";
    "ricFreeSpace" = "280";
    "ricDriveLabel" = "ProgData";
    "ricWinFeature" = "Hyper-V","RSAT-Hyper-V-Tools","UpdateServices-Services","UpdateServices-RSAT","UpdateServices-UI","UpdateServices-WidDB";
    "hypervFolder" = "VMs";
    "hypervLANName" = "HVLAN";
    "hypervREFSwitchName" = "MDTREFIMGLAN";
    "hypervLANNetwork" = "192.168.35.0/24";
    "hypervLANIP" = "192.168.35.1";
    "dhcpSubnetMask" = "255.255.255.0";
    "dhcpPool" = "192.168.35.20-250";
    "dhcpServer" = "192.168.35.1";
    "wsusDBFolder" = "WSUS";
    "wsusClassification" = "Security Updates","Critical Updates","Definition Updates","Feature Packs","Update Rollups","Updates";
    "wsusProduct" = "Visual Studio 2005","Visual Studio 2008","Visual Studio 2010","Visual Studio 2012","Visual Studio 2013","Windows Defender","Windows Server 2016";
    "mdtDeploymentFolder" = "Deploymentshare";
    "mdtLocalUser" = "MDTUser";
    "mdtLocalGroup" = "MDTUsers";
    "mdtLocalUserPwd" = "MDTP@ssw0rd!"; #Password will only be used during the creation of new reference images to connect to the MDT server
    "mdtEventFolder" = "EventShare";
    "mdtLogFolder" = "Logs";
    "mdtCaptureFolder" = "Captures";
}
#adding some extra information to the hash table based on information from the hash table
$config += @{
    "ntfs_$($config.mdtDeploymentFolder)" = "/S BUILTIN\Administrators:F:FSFF /S NT AUTHORITY\SYSTEM:F:FSFF /S $($config.mdtLocalGroup):RX:FSFF /NOINHERITED /FORCE /PROTECT /REPLACE /SUB /FILES";
    "ntfs_$($config.mdtEventFolder)" = "/S BUILTIN\Administrators:F:FSFF /S NT AUTHORITY\SYSTEM:F:FSFF /S $($config.mdtLocalGroup):RXWD:FSFF /NOINHERITED /FORCE /REPLACE /SUB /FILES";
    "ntfs_$($config.mdtLogFolder)" = "/S BUILTIN\Administrators:F:FSFF /S NT AUTHORITY\SYSTEM:F:FSFF /S $($config.mdtLocalGroup):RXWD:FSFF /NOINHERITED /FORCE /REPLACE /SUB /FILES";
    "ntfs_$($config.mdtCaptureFolder)" = "/S BUILTIN\Administrators:F:FSFF /S NT AUTHORITY\SYSTEM:F:FSFF /S $($config.mdtLocalGroup):RXWD:FSFF /NOINHERITED /FORCE /REPLACE /SUB /FILES";
}

#endregion

#regionhypervconfigure
#Configure Hyper-V
#Creating a Hyper-V folder where VMs will be created by default
Import-Module Hyper-V -ErrorAction SilentlyContinue
$vmfolder = Join-Path -Path $config.ricDrive -ChildPath $config.hypervFolder
New-Item -Path (Join-Path -Path $vmfolder -ChildPath 'Virtual Hard Disks') -ItemType Directory
Set-VMHost -VirtualMachinePath $vmfolder -VirtualHardDiskPath (Join-Path -Path $vmfolder -ChildPath 'Virtual Hard Disks') -EnableEnhancedSessionMode $true

#Create a new Hyper-V switch
New-VMSwitch -SwitchName $config.hypervRefSwitchName -SwitchType Internal
#Setting a fixed IP address to the new interface
(Get-NetIPAddress -InterfaceIndex (Get-NetAdapter | Where-Object {$_.Name -match $config.hypervRefSwitchName}).ifIndex -AddressFamily IPv4).IPAddress
New-NetIPAddress -IPAddress $config.hypervLANIP -PrefixLength 24 -InterfaceIndex (Get-NetAdapter | Where-Object {$_.Name -match $config.hypervRefSwitchName}).ifIndex
#Checking the IP address
(Get-NetIPAddress -InterfaceIndex (Get-NetAdapter | Where-Object {$_.Name -match $config.hypervRefSwitchName}).ifIndex -AddressFamily IPv4).IPAddress
#endregion

#regionwsusconfigure
#Configure WSUS
$wsusFolder = Join-Path -Path $config.ricDrive -ChildPath $config.wsusDBFolder
New-Item -Path $wsusfolder -ItemType Directory
#Running postinstall for WSUS
$wsusConfigFile = Join-Path -Path $env:ProgramFiles -ChildPath 'Update Services\tools\wsusutil.exe'
$argument = @("postinstall", "CONTENT_DIR=$($wsusFolder)")
& "$wsusConfigFile" $argument

#Configure WSUS settings
#Connect to WSUS server
$wsus = Get-WSUSServer
$wsusConfig = $wsus.GetConfiguration()
   
#Set to download updates from Microsoft Updates
Set-WsusServerSynchronization -SyncFromMU
    
#Set update languages to English, disable WSUS configuration wizard and save configuration settings
$wsusConfig.AllUpdateLanguagesEnabled = $false
$wsusConfig.SetEnabledUpdateLanguages("en")
$wsusConfig.OOBEInitialized = $true
$wsusConfig.Save()

#Get WSUS Subscription
$subscription = $wsus.GetSubscription()    

#Get WSUS Subscription and perform initial synchronization to get latest categories
#Skipping this step because it takes 30 minutes to complete. Do this later!
##$subscription.StartSynchronizationForCategoryOnly()
    
#Configure the products that we want WSUS to receive updates for
Get-WsusProduct | Set-WsusProduct -Disable
Get-WsusProduct | where-Object {$_.Product.Title -in ($config.wsusProduct)} | Set-WsusProduct
    
#Configure the classifications
Get-WsusClassification | Set-WsusClassification -Disable
Get-WsusClassification | Where-Object {$_.Classification.Title -in ($config.wsusClassification)} | Set-WsusClassification
    
#Configure synchronizations
$subscription.SynchronizeAutomatically=$true
   
#Set synchronization schedule
$subscription.SynchronizeAutomaticallyTimeOfDay= (New-TimeSpan -Hours 14) #14 will translate to 07.00 AM #4 will translate to 09.00 PM (21.00)
$subscription.NumberOfSynchronizationsPerDay=1
$subscription.Save()

#Configuring default automatic approval rule
$rule = $wsus.GetInstallApprovalRules() | Where-Object -FilterScript {$_.Name -eq "Default Automatic Approval Rule"}
$class = $wsus.GetUpdateClassifications() | Where-Object -FilterScript {$_.Title -In ($config.wsusClassification)}
$class_coll = New-Object Microsoft.UpdateServices.Administration.UpdateClassificationCollection
$class_coll.AddRange($class)
$rule.SetUpdateClassifications($class_coll)
$rule.Enabled = $True
$rule.Save()
	
#not doing the sync now because it will take a while. It will run at the next scheduled time
#$subscription.StartSynchronization()
#endregion

#regionadditionalsoftware
# Install Additional required or recommended software
#Installing SQL CLR types (requirement for Reportviewer)
$MSI = (Join-Path -Path $SCRIPT_PARENT -ChildPath 'Source\SQLSysClrTypes.msi')
msiexec /i $msi /qb- /norestart

#Installing Microsoft Report Viewer
$MSI = (Join-Path -Path $SCRIPT_PARENT -ChildPath 'Source\Reportviewer.msi')
msiexec /i $msi /qb- /norestart

#Installing Windows Automated Installation Kit (WAIK)
$waikFile = Join-Path -Path $SCRIPT_PARENT -ChildPath 'Source\adksetup.exe'
$argument = @("/features","OptionId.DeploymentTools","OptionId.WindowsPreInstallationEnvironment","OptionId.UserStateMigrationTool","/installpath","""$(Join-Path -Path $config.ricDrive -ChildPath 'Program Files (x86)\Windows Kits\10')""")
& "$waikfile" $argument

#Installing Starwind Image Converter
$starwindFile = Join-Path -Path $SCRIPT_PARENT -ChildPath 'Source\starwindconverter.exe'
$argument = @("/Silent", "/NoRestart")
& "$starwindFile" $argument

#Installing DotNet Framework 3.5 on Windows Server 2016
. dism.exe /Online /Enable-Feature /FeatureName:NetFx3 /All /LimitAccess /Source:""$(Join-Path -Path $SCRIPT_PARENT -ChildPath 'Source')""

#Install DotNet Framework 3.5 using Add and Remove Features
Add-WindowsFeature -Name NET-Framework-Core

#Installing Notepad++
$nppFile = $(Get-ChildItem -Path $(Join-Path -Path $SCRIPT_PARENT -ChildPath 'Source\npp.7.5.6.Installer.x64.exe')).FullName
$argument = @("/S", "/D=$(Join-Path -Path $config.ricDrive -ChildPath 'Program Files\Notepad++')")
& "$nppFile" $argument


#Installing Microsoft Deployment Toolkit (MDT)
$MSI = (Join-Path -Path $SCRIPT_PARENT -ChildPath 'Source\MicrosoftDeploymentToolkit.msi')
msiexec /i $MSI /qb- INSTALLDIR="""$(Join-Path -Path $config.ricDrive -ChildPath 'Program Files\Microsoft Deployment Toolkit')"""
#endregion

#regionlocalaccountandgroup
#Creating local user account and group for MDT
#Creating new local user account $($config.mdtLocalUser)
$password = ConvertTo-SecureString $Config.mdtLocalUserPwd -AsPlainText -force
New-LocalUser -Name $config.mdtLocalUser -Password $password -AccountNeverExpires -Description "MDT local user account" -PasswordNeverExpires -UserMayNotChangePassword

#Creating new local group $($config.mdtLocalGroup)
New-LocalGroup -Name $config.mdtLocalGroup -Description "MDT local group"
#Add local account to new local group
Add-LocalGroupMember -Group $config.mdtLocalGroup -Member $config.mdtLocalUser
#endregion

#regionmdtconfigure
#Configuring MDT

#FileACL
$fileACLExe = Join-Path $SCRIPT_PARENT "tools\fileacl.exe"

#Folder array
$arrFolder = @(
    @{"folderName" = $($config.mdtDeploymentFolder); "folderPath" = (Join-Path -Path $config.ricDrive -ChildPath $config.mdtDeploymentFolder); "ntfs" = $($config.ntfs_Deploymentshare)}
    @{"folderName" = $($config.mdtEventFolder); "folderPath" = (Join-Path -Path $config.ricDrive -ChildPath (Join-Path -Path $config.mdtDeploymentFolder -ChildPath $config.mdtEventFolder)); "ntfs" = $($config.ntfs_EventShare)}
    @{"folderName" = $($config.mdtLogFolder); "folderPath" = (Join-Path -Path $config.ricDrive -ChildPath (Join-Path -Path $config.mdtDeploymentFolder -ChildPath $config.mdtLogFolder)); "ntfs" = $($config.ntfs_Logs)}
    @{"folderName" = $($config.mdtCaptureFolder); "folderPath" = (Join-Path -Path $config.ricDrive -ChildPath (Join-Path -Path $config.mdtDeploymentFolder -ChildPath $config.mdtCaptureFolder)); "ntfs" = $($config.ntfs_Captures)}
    )
New-Item -Path $arrFolder[0].folderPath -ItemType Directory
$argument = ($($arrFolder[0].folderPath) + " " + $($arrFolder[0].ntfs))
& $fileACLExe $argument

#Import MDT PowerShell module
$mdtModule = Join-Path -Path (Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Deployment 4" -Name "Install_Dir") -ChildPath 'Bin\MicrosoftDeploymentToolkit.psd1'
Import-Module $mdtModule

#Connecting to MDT PSDrive
$mdtDeploymentShare = Join-Path -Path $config.ricDrive -ChildPath $config.mdtDeploymentFolder
new-PSDrive -Name "DS001" -PSProvider "MDTProvider" -Root $mdtDeploymentShare -Description "MDT Deployment Share" -NetworkPath $("\\"  + $ENV:ComputerName + "\" + "$($config.mdtDeploymentFolder)$") | add-MDTPersistentDrive

#creating the rest of the required folders, share them and set NTFS rights
foreach($item in $arrFolder)
{
    if (!(Test-Path $item.folderPath)) {New-Item -Path $item.folderPath -ItemType Directory}
    New-SmbShare -Name "$($item.folderName)$" -Path $item.folderPath -FullAccess Administrators -ChangeAccess $config.mdtLocalGroup
    $argument = ($($item.folderPath) + " " + $($item.ntfs))
    #Write-Output $argument
    & $fileACLExe $argument
}


#Creating the bootstrap.ini file for MDT
$bootstrapFile = @"
[Settings]
Priority=Default

[Default]
DeployRoot=\\$($ENV:ComputerName)\DeploymentShare$
UserDomain=$($ENV:ComputerName)
UserID=$($config.mdtLocalUser)
UserPassword=$($config.mdtLocalUserPwd)

SkipBDDWelcome=YES
"@ #DO NOT INDENT THESE LINES!!!

$bootstrapFile | out-File -Encoding ascii -FilePath (Join-Path -Path $config.ricDrive -Childpath (Join-Path $config.mdtDeploymentFolder -ChildPath 'Control\Bootstrap.ini'))

#Creating the customsettings.ini file for MDT"
$customSettingsFile = @"
[Settings]
Priority=Serialnumber,Default
Properties=RefVersion

[Default]
WUMU_ExcludeKB001=3186539
WUMU_ExcludeKB002=4033369
_SMSTSORGNAME=%TaskSequenceName%
UserDataLocation=NONE
OSInstall=Y
AdminPassword=$($config.localAdminPwd)
JoinWorkgroup=WORKGROUP
HideShell=NO
FinishAction=SHUTDOWN
WSUSServer=http://$($ENV:ComputerName):8530
ApplyGPOPack=NO
SLShare=\\$($ENV:ComputerName)\Logs$
SLShareDynamicLogging=\\$($ENV:ComputerName)\Logs$
EventShare=\\$($ENV:ComputerName)\EventShare$
ComputerBackupLocation=NETWORK
BackupShare=\\$($ENV:ComputerName)\DeploymentShare$
BackupDir=Captures
SkipAdminPassword=YES
SkipProductKey=YES
SkipComputerName=YES
SkipDomainMembership=YES
SkipUserData=YES
SkipLocaleSelection=YES
SkipTaskSequence=NO
SkipTimeZone=YES
SkipBitLocker=YES
SkipSummary=YES
SkipRoles=YES
SkipCapture=NO
SkipFinalSummary=YES
EventService=http://$($ENV:ComputerName):9800

"@ #DO NOT INDENT THESE LINES!!!

$customSettingsFile | out-File -Encoding ascii -FilePath (Join-Path -Path $config.ricDrive -Childpath (Join-Path $config.mdtDeploymentFolder -ChildPath 'Control\CustomSettings.ini'))


#Copy MDTRefImageCreator folder to local disk
Copy-Item -Path (Join-Path -Path $SCRIPT_PARENT -ChildPath 'Source\ImageCreator') -Destination $config.ricDrive -force -Recurse
#Enabling monitoring of MDT deploymentshare
Enable-MDTMonitorService -EventPort 9800 -DataPort 9801
Restore-MDTPersistentDrive
Set-ItemProperty -Path "$($(Get-MDTPersistentDrive).Name):" -Name MonitorHost -Value $ENV:COMPUTERNAME
    
#Creating DHCP configuration file
$dhcpFile = @"
[SETTINGS]
IPPOOL_1=$($config.dhcpPool)
IPBIND_1=$($config.dhcpServer)
AssociateBindsToPools=1
Trace=1
DeleteOnRelease=1
ExpiredLeaseTimeout=3600

[GENERAL]
LEASETIME=3600
NODETYPE=8
SUBNETMASK=$($config.dhcpSubnetMask)
NEXTSERVER=$($config.dhcpServer)
ROUTER_0=0.0.0.0

[DNS-SETTINGS]
EnableDNS=0

"@ #DO NOT INDENT THESE LINES!!!

$dhcpFile | out-File -Encoding ascii -FilePath (Join-Path -Path $config.ricDrive -Childpath (Join-Path 'ImageCreator' -ChildPath 'DHCPServer\dhcpsrv.ini'))


#Creating required Firewall rules"
$program = Join-Path -Path $config.ricDrive -ChildPath 'MDTRefImageCreator\DHCPServer\dhcpsrv.exe'
if (!(Get-NetFirewallRule -Name 'mdt-dhcp-in-tcp-domain' -ErrorAction SilentlyContinue))
{
    Write-Output "Creating firewall rule for DHCP server (TCP Domain)"
    New-NetFirewallRule -Name 'mdt-dhcp-in-tcp-domain' -DisplayName 'MDT DHCP Server for Windows' -Program $program -Protocol TCP -LocalPort Any -RemotePort Any -Direction Inbound -Profile Domain
}
if (!(Get-NetFirewallRule -Name 'mdt-dhcp-in-udp-domain' -ErrorAction SilentlyContinue))
{
    Write-Output "Creating firewall rule for DHCP server (UDP Domain)"
    New-NetFirewallRule -Name 'mdt-dhcp-in-udp-domain' -DisplayName 'MDT DHCP Server for Windows' -Program $program -Protocol UDP -LocalPort Any -RemotePort Any -Direction Inbound -Profile Domain
}
if (!(Get-NetFirewallRule -Name 'mdt-dhcp-in-tcp-private' -ErrorAction SilentlyContinue))
{
    Write-Output "Creating firewall rule for DHCP server (TCP Private)"
    New-NetFirewallRule -Name 'mdt-dhcp-in-tcp-private' -DisplayName 'MDT DHCP Server for Windows' -Program $program -Protocol UDP -LocalPort Any -RemotePort Any -Direction Inbound -Profile Private
}
if (!(Get-NetFirewallRule -Name 'mdt-dhcp-in-udp-private' -ErrorAction SilentlyContinue))
{
    Write-Output "Creating firewall rule for DHCP server (UDP Private)"
    New-NetFirewallRule -Name 'mdt-dhcp-in-udp-private' -DisplayName 'MDT DHCP Server for Windows' -Program $program -Protocol UDP -LocalPort Any -RemotePort Any -Direction Inbound -Profile Private
}
if (!(Get-NetFirewallRule -Name 'mdt-dhcp-in-tcp-public' -ErrorAction SilentlyContinue))
{
    Write-Output "Creating firewall rule for DHCP server (TCP Public)"
    New-NetFirewallRule -Name 'mdt-dhcp-in-tcp-public' -DisplayName 'MDT DHCP Server for Windows' -Program $program -Protocol UDP -LocalPort Any -RemotePort Any -Direction Inbound -Profile Public
}
if (!(Get-NetFirewallRule -Name 'mdt-dhcp-in-udp-public' -ErrorAction SilentlyContinue))
{
    Write-Output "Creating firewall rule for DHCP server (UDP Public)"
    New-NetFirewallRule -Name 'mdt-dhcp-in-udp-public' -DisplayName 'MDT DHCP Server for Windows' -Program $program -Protocol UDP -LocalPort Any -RemotePort Any -Direction Inbound -Profile Public
}
#endregion

#regionwsusmaintenance
#Install ODBC driver 13 for SQL
$MSI = (Join-Path -Path $SCRIPT_PARENT -ChildPath 'Source\msodbcsql.msi')
msiexec /i $msi /qb- /norestart

#Install SQL command line utilities version 13
$MSI = (Join-Path -Path $SCRIPT_PARENT -ChildPath 'Source\MsSqlCmdLnUtils.msi')
msiexec /i $msi /qb- /norestart

#Copy WSUSMaintenance folder to local disk
Copy-Item -Path (Join-Path -Path $SCRIPT_PARENT -ChildPath 'Source\WSUSMaintenance') -Destination $config.ricDrive -force -Recurse
$wsusMaintanceScript = Join-Path -Path $config.ricDrive -ChildPath 'WSUSMaintenance\WSUSMaintenance.ps1'
#Prepare WSUS Maintence script
& $wsusMaintanceScript -FirstRun
#Schedule WSUSMaintenance script
& $wsusMaintanceScript -ScheduledRun
#endregion




