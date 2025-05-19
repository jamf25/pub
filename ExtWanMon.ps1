$wanHosts = @(
    ubiquitiHost1
    ubiquitiHost2
	ubiquitiHost3
	ubiquitiHost4
)

    
$downHosts = @()

$headers = @{
    "Host" = "siterelic.com"
    "Sec-Ch-Ua-Platform" = '"Windows"'
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36"
    "Accept" = "application/json, text/plain, */*"
    "Sec-Ch-Ua" = '"Chromium";v="136", "Google Chrome";v="136", "Not.A/Brand";v="99"'
    "Content-Type" = "application/json"
}


function mailFunction {


	# parameters are unnecessary, we can just hard code them
    param (
        [string]$smtpServer = "smtp.yourserver.com",  # SMTP server address
        [string]$smtpFrom = "your-email@domain.com",  # From address
        [string]$smtpUser = "your-smtp-user",         # SMTP user
        [string]$smtpPass = "your-smtp-password",     # SMTP password
        [string]$toEmail = "jimbo@mail.com"           # To address
    )
    
    # Convert the array to a string (one host per line)
    $body = $downHosts -join "`n"

    # Create the mail message
    $mailMessage = New-Object system.net.mail.mailmessage
    $mailMessage.from = ($smtpFrom)
    $mailMessage.To.add($toEmail)
    $mailMessage.Subject = "Hosts Down Notification"
    $mailMessage.Body = $body
    
    # Set up the SMTP client
    $smtpClient = New-Object Net.Mail.SmtpClient($smtpServer)
    $smtpClient.Credentials = New-Object System.Net.NetworkCredential($smtpUser, $smtpPass)
    
    # Send the email.  Try/catch is overkill
    try {
        $smtpClient.Send($mailMessage)
        Write-Host "Email sent successfully to $toEmail"
    }
    catch {
        Write-Host "Error sending email: $_"
    }
}




foreach ($i in $wanHosts){
	$body = @{
		url = "$i"
	} | ConvertTo-Json
	
	
	
	$response = Invoke-RestMethod -Uri "https://siterelic.com/siterelic-api/ping" `
								-Method Post `
								-Headers $headers `
								-Body $body `
								-UseBasicParsing
	
	if ($response.data.loss -gt 1 ) { 
		$downHosts += $i.data.ip 
	} 
}

if ( $downHosts.length() -gt 0 ) {
	mailFunction()
}
