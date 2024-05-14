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
	
# Demo script to showcase how to configure Veeam to protect multiple FlashBlade object buckets distributed across multiple accounts
# High level explanation is that it will leverage DNS CNAME 'aliases" that reference one FlashBlade Data VIP DNS Host A record
# This allows us to add the same FlashBlade as an unstructured data source multiple times in Veeam
# Install PowerShell modules for FlashBlade and PoshSSH first
# Install-Module -Name Posh-SSH
# For FlashBlade module you'll need to install PowerShell 7, then run pwsh and: Install-Module -Name PureFBModule

# Update the following variables as appropriate (definitely $ApiToken at minimum):
$FlashBlade = "flashblade1.testdrive.local"
$arrayUsername = "pureuser"
$arrayPassword = "pureuser"
$ApiToken = "<replace_with_valid_API_token"
$VeeamCacheRepository = "FlashArray Windows ReFS Repo01"
$dnszone = "testdrive.local"
$fbobjectfqdn = "fbobject.testdrive.local"
$dnscnames = "fbobj1,fbobj2,fbobj3,fbobj4"


# Begin our work:
# Convert FlashBlade password to SecureString:
$arrayPasswordSS = ConvertTo-SecureString $arrayPassword -AsPlainText -Force
$arrayCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $arrayUsername, $arrayPasswordSS
# Split dns entries into array:
$dnscnames = $dnscnames = $dnscnames -split ','
foreach ($cname in $dnscnames) {
	# Add DNS records (localhost must be DNS server otherwise update command appropriately):
	Add-DnsServerResourceRecordCName -name "$cname" -HostNameAlias "$fbobjectfqdn" -ZoneName "$dnszone"

	# Getting ready too use PoshSSH to create FlashBlade object accounts/users/buckets:
	$fqdn = $cname + "." + $dnszone
	$fbobjaccount = $cname
	$fbobjectuser = $cname + "-user1"
	$fbobjectbucket = $cname + "-bucket1"
	Import-Module Posh-SSH
	$SSHSession = New-SSHSession -ComputerName $FlashBlade -Credential $arrayCredential -AcceptKey
	# Bulk SSH commands to run listed below, uncomment the 'virtual-host' one if appropriate for the environment:
	$FBCLIBulkCommands = @"
		#pureobj virtual-host create $fqdn
		pureobj account create $fbobjaccount
		pureobj secure-user create $fbobjaccount/$fbobjectuser
		pureobj secure-user add --policy pure:policy/full-access $fbobjaccount/$fbobjectuser
		purebucket create --account $fbobjaccount $fbobjectbucket
"@
	$FBCLIRunBulkCommands = (Invoke-SSHCommand -Command $FBCLIBulkCommands -SSHSession $SSHSession).Output

	# Create object access and secret keys, add to Veeam Cloud Credentials, add each FlashBlade "service point" source in Veeam
	$ProcessArguments = "-Command Import-Module -Name PureFBModule; `$newaccesskey = Add-PfbObjectStoreAccessKey -FlashBlade $FlashBlade -SkipCertificateCheck:$true -ApiToken $ApiToken -Name $fbobjaccount/$fbobjectuser; `$accesskey = @(`$newaccesskey.name); `$accesskey += @(`$newaccesskey.secret_access_key); `$accesskey | Set-Clipboard"
	$CreateAccessKey = Start-Process pwsh -NoNewWindow -PassThru -Wait -ArgumentList $ProcessArguments
	$newaccesskey = Get-Clipboard
	$accesskey = $newaccesskey | Select -First 1
	$secretkey = $newaccesskey | Select -Last 1
	$account = Add-VBRAmazonAccount -AccessKey $accesskey -SecretKey $secretkey -Description "$fbobjaccount/$fbobjectuser"
	Add-VBRS3CompatibleServer -FriendlyName "$cname" -Account $account -BucketName $fbobjectbucket -ServicePoint "$fqdn" -CacheRepository $VeeamCacheRepository
}
