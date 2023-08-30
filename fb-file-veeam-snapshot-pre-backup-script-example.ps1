# This script comes with no warranty or support, either implied or otherwise, and anyone who chooses to use it accepts full responsibility for any outcomes

# This is an example pre-backup script to provide some framework for allowing Veeam backup of FlashBlade file systems from snapshot
# Backing up shares/exports via snapshot provides for a consistent point in time and works around locked/open file issues
# While this is a fully functional script, it's intended as a starting point for someone with PowerShell skills to customize for use in their environment
# E.g. authentication can be done somewhat differently to obfuscate/secure credentials, error checking and logging may be modified/enhanced

# This script does the pre-backup snapshot creation, then updates the Veeam File Share configuration to use the new snapshot path
# By default it will create a unique snapshot by using the suffix "Veeam" followed by 14 digits representing the current timestamp down to the second
# The full name of the snapshot will thus be the file system name followed by something like ".Veeam20230829093153"

# Install PowerShell 7 to support FlashBlade PS module
# We still need [to run this from] PowerShell 5 though, since the Veeam module doesn't yet support 7 as of July, 2023
# Install the FB module in pwsh for all users so that the Veeam service will be able to load it: Install-Module -Name PureFBModule -Scope AllUsers
# Then call this as a pre-backup script in Veeam

# Update the following variables appropriately:
$FlashBlade = "<FB_management_IP>"
$ApiToken = "<replace_with_valid_API_token"
$FileSystemName = "<name_of_FB_file_system>"
$FileSharePath = "<full_path_name_as_shown_in_Veeam_share_inventory>"

# Set up variables for unique snapshot suffix, leave alone unless you know what you're doing:
$SnapTimestamp = Get-Date -UFormat "%Y%m%d%H%M%S"
$SnapSuffix = "Veeam" + $SnapTimestamp

# Logging details:
$InvokeTimestamp = Get-Date -UFormat "%Y%m%d%H%M%S"
$scriptpath = Split-Path -parent $MyInvocation.MyCommand.Definition
$scriptname = $MyInvocation.MyCommand | select -ExpandProperty Name
$suffix = "-" + "$InvokeTimestamp" + ".log"
$logfile = $scriptname.Replace(".ps1","$suffix")
$logdir = $scriptpath + "\log"
$logpath = $logdir+"\"+$logfile

Try {
	$logdirexists = Get-Item $logdir -ErrorAction Stop
} Catch {
	New-Item -ItemType directory -Path $logdir | Out-Null
}

Try {Stop-Transcript | Out-Null} Catch {}
Start-Transcript -path $logpath

# Now we call on PowerShell 7 to import FB module and create snapshot:
$ProcessArguments = "-Command Import-Module -Name PureFBModule; Add-PfbFilesystemSnapshot -FlashBlade $FlashBlade -ApiToken $ApiToken -SkipCertificateCheck:$True -Sources $FileSystemName -Suffix $SnapSuffix"
$FlashBladeSnapshot = Start-Process pwsh -NoNewWindow -PassThru -Wait -ArgumentList $ProcessArguments
If ($FlashBladeSnapshot.ExitCode -eq "0") {
	Write-Host "`nFlashBlade Snapshot Request Succeeded!`n"
} else {
	Write-Host "`nFlashBlade Snapshot Request Failed`n"
}

# Now we update the Veeam file share configuration to use new snapshot path:
$SnapshotPath = $FileSharePath + "\.snapshot\" + $FileSystemName + "." + $SnapSuffix
$NASFileServer = Get-VBRNASServer -Name $FileSharePath
Set-VBRNASSMBServer -Server $NASFileServer -StorageSnapshotPath $SnapshotPath -EnableDirectBackupFailover:$False

Stop-Transcript