# This script comes with no warranty or support, either implied or otherwise, and anyone who chooses to use it accepts full responsibility for any outcomes

# Warning!!! This script will DESTROY snapshots.
# Use At Your Own Risk!

# This is an example post-backup script to provide some framework for allowing Veeam backup of FlashArray File Managed Directories from snapshot
# Backing up shares/exports via snapshot provides for a consistent point in time and works around locked/open file issues
# While this is a fully functional script, it's intended as a starting point for someone with PowerShell skills to customize for use in their environment
# E.g. authentication can be done somewhat differently to obfuscate/secure credentials, error checking and logging may be modified/enhanced

# This is an optional script that does post-backup snapshot destruction
# The pre-backup script sets a lifespan for the snapshot, which you can adjust as desired, so you can alternatively just allow it to expire based on that
# This example post-backup script will not attempt to eradicate the snapshot, so it will remain on the array for the duration of the eradication delay
# By default it will look for and destroy ALL snapshots matching the snapshot pattern used by the example pre-backup script
# That default pattern is the prefix "Veeam" followed by a suffix of "Backup" plus 14 digits representing the current timestamp down to the second

# Install the FlashArray PowerShell SDK2 first: Install-Module -Name PureStoragePowerShellSDK2 -Scope AllUsers

# This example script uses simple user/password for authentication, for additional authentication options see the article referenced in the SDK2 Examples here:
# https://github.com/PureStorage-Connect/PowerShellSDK2/blob/master/SDK2-Examples.ps1

# Specify variables for FA connection, full directory name, and snapshot details:
$faendpoint = "<FA_Management_IP_or_FQDN>"
$arrayUsername = "<array_username>"
$arrayPassword = "<array_password>"
$SnapDirectory = "<FA_Directory_Name>"  # As shown in FlashArray Directory list, e.g. "user-shares01::user-shares01:lab-files"
# The example value below is for a snapshot prefix matching "Veeam" followed by a snapshot suffix of "Backup" followed by 14 numbers (timestamp down to seconds as used in example pre-script):
$SnapshotMatchPattern = 'Veeam.Backup\d{14}'

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

# Destroy then eradicate (Delete) specified directory snapshot
Write-Host "`nConnecting to Flash Array '$faendpoint' and retrieving directory snapshot list for '$snapdirectory'...`n"
#$arrayCredential = Get-Credential -Message "Specify Credentials for FlashArray '$faendpoint'"

# Primary FlashArray Credential for user/password authentication
$arrayPasswordSS = ConvertTo-SecureString $arrayPassword -AsPlainText -Force
$arrayCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $arrayUsername, $arrayPasswordSS

$flasharray = Connect-Pfa2Array -Endpoint $faendpoint -Credential $arrayCredential -IgnoreCertificateError

# Get snaps for specified directory and match any to specified snap prefix+suffix
$DirectorySnaps = Get-Pfa2DirectorySnapshot -Array $flasharray -SourceNames $SnapDirectory
$snaps = @(foreach ($snap in $DirectorySnaps) {if ($snap.name -match $SnapshotMatchPattern) {$snap}})

if ($snaps) {
	Write-Host "`nFound the following directory snapshots matching specified criteria:"
	$snaps
} else {
	Write-Host "`nFound no directory snapshots matching the specified criteria. Exiting...`n"
	Stop-Transcript
	Exit 1
}

# Do a loop through all id's returned in case previous cleanup didn't happen and we need to destroy and eradicate multiple snapshots
## (not applicable if snapshot suffix was specified as you can't have more than one snapshot on a given object with precisely the same name)
foreach ($snap in $snaps) {
	if ($snap.Destroyed -eq $False) {
		Write-Host "`nDestroying snapshot: " $snap.name
		$directorysnapdestroy = Update-Pfa2DirectorySnapshot -Array $flasharray -Ids $snap.id -Destroyed:$True
		if ($? -eq $True) {
			Write-Host "`nSnapshot appears to have been successfully destroyed`n"
			sleep 1
		} else {
			Write-Host "`nSnapshot destroy appears to have failed!`n"
			Stop-Transcript
			Exit 1
		}
	} else {
		Write-Host "`nIt looks like the Snapshot" $snap.name "was already destroyed`n"
	}
}

Stop-Transcript