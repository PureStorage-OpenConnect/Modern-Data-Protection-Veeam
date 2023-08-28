# Warning!!! This script will DESTROY snapshots.
# Use At Your Own Risk!

# Install PowerShell 7 to support FlashBlade PS module
# Install the FB module for all users so that the Veeam service will be able to load it: Install-Module -Name PureFBModule -Scope AllUsers
# Then call this as a post-backup script in Veeam, and be sure to run it with PowerShell 7 like so:
#    "C:\Program Files\PowerShell\7\pwsh.exe" "<script_path>"

# Update the following variables appropriately:
$FlashBlade = "<FB_management_IP>"
$ApiToken = "<replace_with_valid_API_token"
$FileSystemName = "<name_of_FB_file_system>"
# The example value below is for a file system named "bk-smb" and a snapshot suffix matching "Veeam" followed by 14 numbers (timestamp down to seconds):
$SnapshotMatchPattern = 'bk-smb.Veeam\d{14}'

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

# We're first going to run a test to see if it looks like API invocation will succeed, since it seems the cmdlet exits with $LASTEXITCODE=0 otherwise despite $?=$False
$ProcessArguments = "-Command Import-Module -Name PureFBModule; Get-PfbFilesystemSnapshot -FlashBlade $FlashBlade -ApiToken $ApiToken -SkipCertificateCheck:$True -Names_or_Sources $FileSystemName"
$FlashBladeSnapshotListTest = Start-Process pwsh -NoNewWindow -PassThru -Wait -ArgumentList $ProcessArguments
If ($FlashBladeSnapshotListTest.ExitCode -eq "0") {
	$FlashBladeSnapshots = Get-PfbFilesystemSnapshot -FlashBlade $FlashBlade -ApiToken $ApiToken -SkipCertificateCheck:$True -Names_or_Sources $FileSystemName
} else {
	Write-Host "`nFB Snapshot List API Call Test Appears to have FAILED!`n"
	Stop-Transcript
	Exit 1
}

foreach ($snap in $FlashBladeSnapshots) {
	if (($snap -match $SnapshotMatchPattern) -and ($snap.destroyed -eq $False)) {
		Write-Host "`nDestroying snapshot: " $snap.Name "`n"
		Update-PfbFilesystemSnapshot -FlashBlade $FlashBlade -ApiToken $ApiToken -SkipCertificateCheck:$True -Names $snap.Name -Attributes '{ "destroyed":"true" }'
		if ($? -eq $True) {
			Write-Host "`nSnapshot appears to have been successfully destroyed!`n"
			sleep 1
		} else {
			Write-Host "`nSnapshot destruction appears to have failed!`n"
			Stop-Transcript
			Exit 1
		}
	}
}

Stop-Transcript
