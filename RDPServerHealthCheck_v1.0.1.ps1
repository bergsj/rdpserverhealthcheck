################################################################################################
## RDPServerHealthCheck
## Sjoerd van den Berg
## 1 July 2014
## v1.0.1
## Based on XenAppServerHealthCheck (Jason Poyner) http://deptive.co.nz/xenapp-farm-health-check-v2/
##
## The script checks the health of an RDP Services Environment and e-mails the report. 
## This script checks the following:
##   - Ping response
##   - Logon enabled
##   - Collection Name
##   - Active sessions
##   - RDP port response 
##   - WMI response (to check for WMI corruption)
##	 - Remote Desktop Configuration, Remote Desktop Services, Remote Desktop Services UserMode Port Redirector services
##   - Server uptime (to ensure scheduled reboots are occurring)
##
## You are free to use this script in your environment but please e-mail me any improvements.
################################################################################################

Import-Module RemoteDesktop -ErrorAction SilentlyContinue
if ((Get-Module "RemoteDesktop") -eq $null) 
{
	Write-Error "Error loading Remote Desktop snapin"; 
	Return
}




# Change the below variables to suit your environment
#==============================================================================================
# NOT USED /Servers in the excluded folders will not be included in the health check
$excludedFolders = @("Servers/Dev & Test")
 
# We always schedule reboots on Remote Desktop Services farms, usually on a weekly basis. Set the maxUpTimeDays
# variable to the maximum number of days a XenApp server should be up for.
$maxUpTimeDays = 7

# RDP Broker to use the ge the information
$broker = "broker.corp.domain.com"

# E-mail report details
$emailFrom     = "noreply@domain.com"
$emailTo       = "rec@ipient1.com","rec@ipient2.com"
$smtpServer    = "mailserver.corp.domain.com"
$emailSubject  = ("Remote Desktop Services Farm Report - " + (Get-Date -format R))

#==============================================================================================




#$successCodes  = @("success","ok","enabled","default")
 
$currentDir = Split-Path $MyInvocation.MyCommand.Path
$logfile    = Join-Path $currentDir ("RDPServerHealthCheck.log")
$resultsHTM = Join-Path $currentDir ("RDPServerHealthCheckResults.htm")
$errorsHTM  = Join-Path $currentDir ("RDPServerHealthCheckErrors.htm")
 
$headerNames  = "CollectionName", "Weight", "Limit", "ActiveSessions", "Load", "Ping", "Logons", "RDPPort", "RDPConfig", "RDPSvc", "WMI", "RDPUm", "Uptime"
$headerWidths = "6",          	  "4",      "4",     "6",    		   "5",    "5",    "5",      "5",       "5", 	     "5",      "5",   "5",     "5"

#==============================================================================================
function LogMe() {
	Param(
		[parameter(Mandatory = $true, ValueFromPipeline = $true)] $logEntry,
		[switch]$display,
		[switch]$error,
		[switch]$warning,
		[switch]$progress
	)


	if ($error) {
		$logEntry = "[ERROR] $logEntry" ; Write-Host "$logEntry" -Foregroundcolor Red}
	elseif ($warning) {
		Write-Warning "$logEntry" ; $logEntry = "[WARNING] $logEntry"}
	elseif ($progress) {
		Write-Host "$logEntry" -Foregroundcolor Green}
	elseif ($display) {
		Write-Host "$logEntry" }
	 
	#$logEntry = ((Get-Date -uformat "%D %T") + " - " + $logEntry)
	$logEntry | Out-File $logFile -Append
}


#==============================================================================================
function Ping([string]$hostname, [int]$timeout = 200) {
	$ping = new-object System.Net.NetworkInformation.Ping #creates a ping object
	try {
		$result = $ping.send($hostname, $timeout).Status.ToString()
	} catch {
		$result = "Failure"
	}
	return $result
}


#==============================================================================================
Function writeHtmlHeader
{
param($title, $fileName)
$date = ( Get-Date -format R)
$head = @"
<html>
<head>
<meta http-equiv='Content-Type' content='text/html; charset=iso-8859-1'>
<title>$title</title>
<STYLE TYPE="text/css">
<!--
td {
font-family: Tahoma;
font-size: 11px;
border-top: 1px solid #999999;
border-right: 1px solid #999999;
border-bottom: 1px solid #999999;
border-left: 1px solid #999999;
padding-top: 0px;
padding-right: 0px;
padding-bottom: 0px;
padding-left: 0px;
overflow: hidden;
}
body {
margin-left: 5px;
margin-top: 5px;
margin-right: 0px;
margin-bottom: 10px;
table {
table-layout:fixed; 
border: thin solid #000000;
}
-->
</style>
</head>
<body>
<table width='1200'>
<tr bgcolor='#CCCCCC'>
<td colspan='7' height='48' align='center' valign="middle">
<font face='tahoma' color='#003399' size='4'>
<!--<img src="http://servername/administration/icons/xenapp.png" height='42'/>-->
<strong>$title - $date</strong></font>
</td>
</tr>
</table>
<table width='1200'>
<tr bgcolor='#CCCCCC'>
<td width=50% height='48' align='center' valign="middle">
<font face='tahoma' color='#003399' size='4'>
<!--<img src="http://servername/administration/icons/active.png" height='32'/>-->
Active Sessions:  $TotalActiveSessions</font>
<td width=50% height='48' align='center' valign="middle">
<font face='tahoma' color='#003399' size='4'>
<!--<img src="http://servername/administration/icons/disconnected.png" height='32'/>-->
Disconnected Sessions:  $TotalDisconnectedSessions</font>
</td>
</tr>
</table>
"@
$head | Out-File $fileName
}

# ==============================================================================================
Function writeTableHeader
{
param($fileName)
$tableHeader = @"
<table width='1200'><tbody>
<tr bgcolor=#CCCCCC>
<td width='6%' align='center'><strong>ServerName</strong></td>
"@

$i = 0
while ($i -lt $headerNames.count) {
	$headerName = $headerNames[$i]
	$headerWidth = $headerWidths[$i]
	$tableHeader += "<td width='" + $headerWidth + "%' align='center'><strong>$headerName</strong></td>"
	$i++
}

$tableHeader += "</tr>"

$tableHeader | Out-File $fileName -append
}

# ==============================================================================================
Function writeData
{
	param($data, $fileName)
	
	$data.Keys | sort | foreach {
		$tableEntry += "<tr>"
		$computerName = $_
		$tableEntry += ("<td bgcolor='#CCCCCC' align=center><font color='#003399'>$computerName</font></td>")
		#$data.$_.Keys | foreach {
		$headerNames | foreach {
			#"$computerName : $_" | LogMe -display
			try {
				if ($data.$computerName.$_[0] -eq "SUCCESS") { $bgcolor = "#387C44"; $fontColor = "#FFFFFF" }
				elseif ($data.$computerName.$_[0] -eq "WARNING") { $bgcolor = "#FF7700"; $fontColor = "#FFFFFF" }
				elseif ($data.$computerName.$_[0] -eq "ERROR") { $bgcolor = "#FF0000"; $fontColor = "#FFFFFF" }
				else { $bgcolor = "#CCCCCC"; $fontColor = "#003399" }
				$testResult = $data.$computerName.$_[1]
			}
			catch {
				$bgcolor = "#CCCCCC"; $fontColor = "#003399"
				$testResult = ""
			}
			
			$tableEntry += ("<td bgcolor='" + $bgcolor + "' align=center><font color='" + $fontColor + "'>$testResult</font></td>")
		}
		
		$tableEntry += "</tr>"
	}
	
	$tableEntry | Out-File $fileName -append
}

 
# ==============================================================================================
Function writeHtmlFooter
{
param($fileName)
@"
</table>

</body>
</html>
"@ | Out-File $FileName -append
}

Function Check-Port  
{
	param ([string]$hostname, [string]$port)
	try 
	{
		$socket = new-object System.Net.Sockets.TcpClient($hostname, $Port) #creates a socket connection to see if the port is open
	} 
	catch 
	{
		$socket = $null
		"Socket connection failed" | LogMe -display -error
		return $false
	}

	if (($socket -ne $null) -and ($socket.Connected))
	{
		"Socket Connection Successful" | LogMe
		return $true
	} 
	else 
	{ 
		"Socket connection failed" | LogMe -display -error; 
		return $false 
	}
}

# ==============================================================================================
# ==                                       MAIN SCRIPT                                        ==
# ==============================================================================================
"Checking server health..." | LogMe -display

rm $logfile -force -EA SilentlyContinue

# Data structure overview:
# Individual tests added to the tests hash table with the test name as the key and a two item array as the value.
# The array is called a testResult array where the first array item is the Status and the second array
# item is the Result. Valid values for the Status are: SUCCESS, WARNING, ERROR and $NULL.
# Each server that is tested is added to the allResults hash table with the computer name as the key and
# the tests hash table as the value.
# The following example retrieves the Logons status for server NZCTX01:
# $allResults.NZCTX01.Logons[0]

$allResults = @{}

$usersessions = Get-RDUserSession -connectionbroker $broker
$RDSessionHosts = Get-SessionCollection -connectionbroker $broker | foreach {
	$loadbalanceconfig = Get-RDSessionCollectionConfiguration -CollectionName $_.CollectionName -LoadBalancing -ConnectionBroker $broker
	Get-RDsessionhost -connectionbroker $broker -collection $_.CollectionName | foreach {
	
		$tests = @{}
		
		## TODO: excluded servers
		
		$server = $_.SessionHost
		$server | LogMe -display -progress
		
		$tests.FolderPath   = $null, $_.FolderPath		 #TODO, needed?
		$tests.CollectionName = $null, $_.CollectionName 
		
		
		# Check server logons
		if($_.NewConnectionAllowed -eq "No"){
			"Logons are disabled on this server" | LogMe -display -warning
			$tests.Logons = "WARNING", "Disabled"
		} else {
			$tests.Logons = "SUCCESS", "Enabled"
		}
		
		# Report on active server sessions
		$tests.ActiveSessions = "WARNING","0"
		$sessioncount = ($usersessions | Where-Object { (($_.SessionState -eq "STATE_CONNECTED") -or ($_.SessionState -eq "STATE_ACTIVE")) -and $_.HostServer -match $server }).Count
		if ($sessioncount -gt 0) {$tests.ActiveSessions = "SUCCESS",[string]$sessioncount}
			
		# Ping server 
		$result = Ping $server 100
		if ($result -ne "SUCCESS") { $tests.Ping = "ERROR", $result }
		else { $tests.Ping = "SUCCESS", $result 
		
			# Test RDP connectivity
			if (Check-Port $server "3389") { $tests.RDPPort = "SUCCESS", "Success" }
			else { $tests.RDPPort = "ERROR","No response" }
						
			# Check services
			if ((Get-Service -Name "SessionEnv" -ComputerName $server).Status -Match "Running") {
				"Remote Desktop Configuration service running..." | LogMe
				$tests.RDPConfig = "SUCCESS", "Success"
			} else {
				"Remote Desktop Configuration service stopped"  | LogMe -display -error
				$tests.RDPConfig = "ERROR", "Error"
			}
				
			if ((Get-Service -Name "TermService" -ComputerName $server).Status -Match "Running") {
				"Remote Desktop Services service running..." | LogMe
				$tests.RDPSvc = "SUCCESS","Success"
			} else {
				"Remote Desktop Services service stopped"  | LogMe -display -error
				$tests.RDPSvc = "ERROR","Error"
			}
				
			if ((Get-Service -Name "UmRdpService" -ComputerName $server).Status -Match "Running") {
				"Remote Desktop Services UserMode Port Redirector service running..." | LogMe
				$tests.RDPUm = "SUCCESS","Success"
			} else {
				"Remote Desktop Services UserMode Port Redirector service stopped"  | LogMe -display -error
				$tests.RDPUm = "ERROR","Error"
			}
			
			$tests.Weight = "SUCCESS",[string](($loadbalanceconfig | Where-Object { $_.SessionHost -eq $server }).RelativeWeight)
			$tests.Limit = "SUCCESS",[string](($loadbalanceconfig | Where-Object { $_.SessionHost -eq $server }).SessionLimit)
			
			$CurrentServerLoad = (Get-Counter -Counter "\Processor(_Total)\% Processor Time" -SampleInterval 1 -MaxSamples 20 -ComputerName $server | Select -ExpandProperty countersamples | select -ExpandProperty cookedvalue | Measure-Object -Average).average
			$CurrentServerLoad = [string]([Math]::Round([decimal]($CurrentServerload)))
			if( [int] $CurrentServerLoad -lt 30) {
				  "Serverload is low" | LogMe
				  $tests.Load = "SUCCESS", $CurrentServerLoad
				}
			elseif([int] $CurrentServerLoad -lt 70 -and [int] $CurrentServerLoad -gt 30) {
				"Serverload is Medium" | LogMe -display -warning
				$tests.Load = "WARNING", $CurrentServerload
			}   	
			else {
				"Serverload is High" | LogMe -display -error
				$tests.Load = "ERROR", $CurrentServerload
			}   
			$CurrentServerLoad = 0
			
			# Test WMI
			$tests.WMI = "ERROR","Error"
			try { $wmi=Get-WmiObject -class Win32_OperatingSystem -computer $server } 
			catch {	$wmi = $null }

			# Perform WMI related checks
			if ($wmi -ne $null) {
				$tests.WMI = "SUCCESS", "Success"
				$LBTime=$wmi.ConvertToDateTime($wmi.Lastbootuptime)
				[TimeSpan]$uptime=New-TimeSpan $LBTime $(get-date)

				if ($uptime.days -gt $maxUpTimeDays){
					 "Server reboot warning, last reboot: {0:D}" -f $LBTime | LogMe -display -warning
					 $tests.Uptime = "WARNING", [string]$uptime.days
				} else {
					 $tests.Uptime = "SUCCESS", [string]$uptime.days
				}
				
			} else { "WMI connection failed - check WMI for corruption" | LogMe -display -error	}

		}
		
		$allResults.$server = $tests
	}
}

# Get farm session info

$ActiveSessions       = ($usersessions | Where-Object { ($_.SessionState -eq "STATE_CONNECTED") -or ($_.SessionState -eq "STATE_ACTIVE") }).Count
$DisconnectedSessions = ($usersessions | Where-Object { ($_.SessionState -eq "STATE_DISCONNECTED") }).Count

if ($ActiveSessions) { $TotalActiveSessions = $ActiveSessions }
else { $TotalActiveSessions = 0 }

if ($DisconnectedSessions) { $TotalDisconnectedSessions = $DisconnectedSessions }
else { $TotalDisconnectedSessions = 0 }

"Total Active Sessions: $TotalActiveSessions" | LogMe -display
"Total Disconnected Sessions: $TotalDisconnectedSessions" | LogMe -display

# Write all results to an html file
Write-Host ("Saving results to html report: " + $resultsHTM)
writeHtmlHeader "Remote Desktop Services Report" $resultsHTM
writeTableHeader $resultsHTM
$allResults | sort-object -property FolderPath | % { writeData $allResults $resultsHTM }
writeHtmlFooter $resultsHTM

# Write only the errors to an html file
#$allErrors = $allResults | where-object { $_.Ping -ne "success" -or $_.Logons -ne "enabled" -or $_.LoadEvaluator -ne "default" -or $_.ICAPort -ne "success" -or $_.IMA -ne "success" -or $_.XML -ne "success" -or $_.WMI -ne "success" -or $_.Uptime -Like "NOT OK*" }
#$allResults | % { $_.Ping -ne "success" -or $_.Logons -ne "enabled" -or $_.LoadEvaluator -ne "default" -or $_.ICAPort -ne "success" -or $_.IMA -ne "success" -or $_.XML -ne "success" -or $_.WMI -ne "success" -or $_.Uptime -Like "NOT OK*" }
#Write-Host ("Saving errors to html report: " + $errorsHTM)
#writeHtmlHeader "XenApp Farm Report Errors" $errorsHTM
#writeTableHeader $errorsHTM
#$allErrors | sort-object -property FolderPath | % { writeData $allErrors $errorsHTM }
#writeHtmlFooter $errorsHTM

$mailMessageParameters = @{
	From       = $emailFrom
	To         = $emailTo
	Subject    = $emailSubject
	SmtpServer = $smtpServer
	Body       = (gc $resultsHTM) | Out-String
	Attachment = $resultsHTM
}

Send-MailMessage @mailMessageParameters -BodyAsHtml