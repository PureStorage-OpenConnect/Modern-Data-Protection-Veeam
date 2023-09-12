<#  Disclaimer
    The sample module and documentation are provided AS IS and are not supported by
	the author or the author's employer, unless otherwise agreed in writing. You bear
	all risk relating to the use or performance of the sample script and documentation.
	The author and the author’s employer disclaim all express or implied warranties
	(including, without limitation, any warranties of merchantability, title, infringement
	or fitness for a particular purpose). In no event shall the author, the author's employer
	or anyone else involved in the creation, production, or delivery of the scripts be liable
	for any damages whatsoever arising out of the use or performance of the sample script and
	documentation (including, without limitation, damages for loss of business profits,
	business interruption, loss of business information, or other pecuniary loss), even if
	such person has been advised of the possibility of such damages. #>

# Warning!!! This script will DESTROY snapshots.
# Use At Your Own Risk!

# This is an example post-backup script to provide some framework for allowing Veeam backup of FlashBlade file systems from snapshot
# Backing up shares/exports via snapshot provides for a consistent point in time and works around locked/open file issues
# While this is a fully functional script, it's intended as a starting point for someone with PowerShell skills to customize for use in their environment
# E.g. authentication can be done somewhat differently to obfuscate/secure credentials, error checking and logging may be modified/enhanced

# This script does the post-backup snapshot destruction, so that the snapshot created by pre-backup script doesn't live forever
# This example post-backup script will not attempt to eradicate the snapshot, so it will remain on the array for the duration of the eradication delay
# By default it will look for and destroy ALL snapshots matching the snapshot pattern used by the example pre-backup script
# That default pattern is the suffix "Veeam" followed by 14 digits representing the a timestamp down to the second

# Install PowerShell 7 to support FlashBlade PS module
# Install the FB module in pwsh for all users so that the Veeam service will be able to load it: Install-Module -Name PureFBModule -Scope AllUsers
# Then call this as a post-backup script in Veeam, and be sure to run it with PowerShell 7 e.g. like so:
#    "C:\Program Files\PowerShell\7\pwsh.exe" "<script_path>"

# Update the following variables appropriately:
$FlashBlade = "<FB_management_IP>"
$ApiToken = "<replace_with_valid_API_token"
$FileSystemName = "<name_of_FB_file_system>"
# The example value below is for a snapshot suffix matching "Veeam" followed by 14 numbers (timestamp down to seconds as used in example pre-script):
$SnapshotMatchPattern = 'Veeam\d{14}'

# Forcing script to require PowerShell v7:
#Requires -Version 7

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

# Import FB PS Module, gather all snapshots that match pattern specified above, then attempt to destroy each one that isn't already in the eradication bin:

Import-Module -Name PureFBModule

# We're first going to run a test to see if it looks like API invocation will succeed, since it seems the cmdlet on its own always exits with $LASTEXITCODE=0
$ProcessArguments = "-Command Import-Module -Name PureFBModule; Get-PfbFilesystemSnapshot -FlashBlade $FlashBlade -ApiToken $ApiToken -SkipCertificateCheck:$True -Names_or_Sources $FileSystemName"
$FlashBladeSnapshotListTest = Start-Process pwsh -NoNewWindow -PassThru -Wait -ArgumentList $ProcessArguments
If ($FlashBladeSnapshotListTest.ExitCode -eq "0") {
	$FlashBladeSnapshots = Get-PfbFilesystemSnapshot -FlashBlade $FlashBlade -ApiToken $ApiToken -SkipCertificateCheck:$True -Names_or_Sources $FileSystemName
	$snaps = @(foreach ($snap in $FlashBladeSnapshots) {if ($snap.name -match $SnapshotMatchPattern) {$snap}})
} else {
	Write-Host "`nFB Snapshot List API Call Test Appears to have FAILED!`n"
	Stop-Transcript
	Exit 1
}

# Do a loop through all matching snapshots returned in case previous cleanup didn't happen and we need to destroy multiple snapshots
foreach ($snap in $snaps) {
	if ($snap.Destroyed -eq $False) {
		Write-Host "`nDestroying snapshot: " $snap.Name "`n"
		Update-PfbFilesystemSnapshot -FlashBlade $FlashBlade -ApiToken $ApiToken -SkipCertificateCheck:$True -Names $snap.Name -Attributes '{ "destroyed":"true" }'
		if ($? -eq $True) {
			Write-Host "`nSnapshot appears to have been successfully destroyed!`n"
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
