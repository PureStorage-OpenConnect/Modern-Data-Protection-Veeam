# This script comes with no warranty or support, either implied or otherwise, and anyone who chooses to use it accepts full responsibility for any outcomes

# This is an example pre-backup script to provide some framework for allowing Veeam backup of FlashArray File Managed Directories from snapshot
# Backing up shares/exports via snapshot provides for a consistent point in time and works around locked/open file issues
# While this is a fully functional script, it's intended as a starting point for someone with PowerShell skills to customize for use in their environment
# E.g. authentication can be done somewhat differently to obfuscate/secure credentials, error checking and logging may be modified/enhanced

# This script does the pre-backup snapshot creation, then updates the Veeam File Share configuration to use the new snapshot path
# By default it will create a unique snapshot by using the prefix "Veeam" followed by a suffix of "Backup" plus 14 digits representing the current timestamp down to the second
# The full name of the snapshot will thus be the Managed Directory name followed by something like ".Veeam.Backup20230829093153"

# Install the FlashArray PowerShell SDK2 first: Install-Module -Name PureStoragePowerShellSDK2 -Scope AllUsers

# This example script uses simple user/password for authentication, for additional authentication options see the article referenced in the SDK2 Examples here:
# https://github.com/PureStorage-Connect/PowerShellSDK2/blob/master/SDK2-Examples.ps1

# Specify appropriate values for FA connection, full FA directory name, and Veeam File Share path:
$faendpoint = "<FA_Management_IP_or_FQDN>"
$arrayUsername = "<array_username>"
$arrayPassword = "<array_password>"
$SnapDirectory = "<FA_Managed_Directory_Name>"  # As shown in FlashArray Directory list, e.g. "user-shares01::user-shares01:lab-files"
$FileSharePath = "<full_path_name_as_shown_in_Veeam_share_inventory>"  # Example: "\\172.16.16.15\lab-files"

# Set up variables for unique snapshot suffix, leave alone unless you know what you're doing:
$SnapPrefix = "Veeam"
$SnapTimestamp = Get-Date -UFormat "%Y%m%d%H%M%S"
$SnapSuffix = "Backup" + $SnapTimestamp
$SnapLifetime = 604800000  # snap lifespan is specified in milliseconds - e.g. 1 month is 2629800000, 1 week is 604800000

Import-Module PureStoragePowerShellSDK2

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

Clear
Try {Stop-Transcript | Out-Null} Catch {}
Start-Transcript -path $logpath

# Connect to FlashArray '$faendpoint':
Write-Host "`nConnecting to Flash Array '$faendpoint' and creating directory snapshot '$SnapDirectory.$SnapPrefix.$SnapSuffix'...`n"

# Primary FlashArray Credential for user/password authentication
$arrayPasswordSS = ConvertTo-SecureString $arrayPassword -AsPlainText -Force
$arrayCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $arrayUsername, $arrayPasswordSS

$flasharray = Connect-Pfa2Array -Endpoint $faendpoint -Credential $arrayCredential -IgnoreCertificateError

# Create snapshot on directory "$SnapDirectory":
$directorysnap = New-Pfa2DirectorySnapshot -Array $flasharray -SourceNames $SnapDirectory -KeepFor $SnapLifetime -ClientName $SnapPrefix -Suffix $SnapSuffix

if ($? -eq $True) {
	Write-Host "`nSnapshot creation appears to have succeeded!`n"
} else {
	Write-Host "`nSnapshot creation appears to have failed! Exiting...`n"
	Stop-Transcript
	Exit 1
}

# Now we update the Veeam file share configuration to use new snapshot path:
$SnapshotPath = $FileSharePath + "\.snapshot\" + $SnapPrefix + "." + $SnapSuffix
$NASFileServer = Get-VBRNASServer -Name $FileSharePath
Set-VBRNASSMBServer -Server $NASFileServer -StorageSnapshotPath $SnapshotPath -EnableDirectBackupFailover:$False

Stop-Transcript