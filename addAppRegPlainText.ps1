<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.238
	 Created on:   	27-8-2024 16:39
	 Created by:   	Rink Turksma
	 Organization: 	
	 Filename:     	addAppRegPlainText.ps1
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>
param
(
	[parameter(Mandatory = $true)]
	[string]$appRegName,
	[string]$customername,
	[string]$customPrivacyURL
)

#Requires -RunAsAdministrator

$customerloc = "C:\Users\$env:username\.IntunePrepTool\$customername.csv"


class config_tenantinfo {
	[string]$customername
	[string]$customPrivacyURL
	[string]$appRegName
	[string]$tenantID
	[string]$appId
	[string]$clientsecret
	[datetime]$validdate
}


# Least privilege: only Application.ReadWrite.All is requested. Combined with the
# Application Developer role this only allows creating and managing app registrations
# the signed-in user owns. Admin consent is granted afterwards by an administrator.
Connect-MgGraph -Scopes "Application.ReadWrite.All" -ContextScope Process -NoWelcome
$tenantInfo = Get-MgContext

$requiredResourceAccess = @{
	'resourceAccess' = @(
		# DeviceManagementApps.ReadWrite.All (Application) - the only permission the upload functions need
		@{
			'id'   = "78145de6-330d-4800-a6ce-494ff2d33d07"
			'type' = "Role"
		}
	)
	'resourceAppId'  = "00000003-0000-0000-c000-000000000000"
}
try
{
	$appInfo = New-MgApplication -DisplayName $appRegName -RequiredResourceAccess $requiredResourceAccess
}
catch
{
	$_.Exception | Format-List -Force
	$_.Exception.InnerException
}


$appId = $appInfo.Id
$appID2 = Get-MgApplication -ApplicationId $appID
$passwordCredential = @{
	"displayName" = $appRegName
	"endDateTime" = (Get-Date).AddMonths(+ 12)
}
$clientSecret = Add-MgApplicationPassword -ApplicationId ($appInfo.Id) -PasswordCredential $passwordCredential

$tenantID = $tenantInfo.TenantId
$appID = $appInfo.AppId
#Encrypt the secret with Windows DPAPI before it is written to disk (readable only by this user on this computer)
$clientSecret = ConvertTo-SecureString -String $clientSecret.SecretText -AsPlainText -Force | ConvertFrom-SecureString
$username = $appInfo.AppId
$password = $clientSecret.SecretText
$config_tenantinfo = $null;

if ($CustomPrivacyUrl -like 'nvt')
{
	
	$config_tenantinfo += @([config_tenantinfo]@{
			customername	 = $customername
			customPrivacyURL = $null
			appRegName	     = $appRegName
			tenantID		 = $tenantID
			appID		     = $appId
			clientsecret	 = $clientSecret
			validdate	     = (Get-Date).AddMonths(+ 12)
			
		})
}
else
{
	$config_tenantinfo += @([config_tenantinfo]@{
			customername	 = $customername
			customPrivacyURL = $customPrivacyURL
			appRegName	     = $appRegName
			tenantID		 = $tenantID
			appID		     = $appId
			clientsecret	 = $clientSecret
			validdate	     = (Get-Date).AddMonths(+ 12)
			
		})
}


# The service principal is also created automatically when admin consent is granted, so a failure here is not fatal
try { New-MgServicePrincipal -AppId $appInfo.appId -ErrorAction Stop | Out-Null }
catch { Write-Warning "Service principal not created yet; it will be created when admin consent is granted. $($_.Exception.Message)" }
try
{
	write-host "App Registration done!"
	$config_tenantinfo2 = [PSCustomObject]@{ customername  = $customername; target = "plain"}
	$config_tenantinfo2 | Export-Csv "c:\users\$env:username\.IntunePrepTool\config_tenantinfo.csv" -NoTypeInformation -append
	$config_tenantinfo | export-csv $customerloc -NoTypeInformation -Force
}
catch
{
	$_.Exception | Format-List -Force
	$_.Exception.InnerException
}

# Admin consent is no longer granted by this script (that required AppRoleAssignment.ReadWrite.All
# and a Global Admin / Privileged Role Administrator). Show the link where an administrator can grant it.
if (-not $appInfo) { return }
$consentUrl = "https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/CallAnAPI/appId/$($appInfo.AppId)/isMSAApp~/false"
Write-Host "App Registration created. Admin consent is still required:" -ForegroundColor Yellow
Write-Host $consentUrl
try { Set-Clipboard -Value $consentUrl } catch { }
Add-Type -AssemblyName System.Windows.Forms
$consentMessage = "App registration '$appRegName' was created.`r`n`r`nAn administrator (Global Admin or Privileged Role Administrator) must now grant admin consent for 'DeviceManagementApps.ReadWrite.All':`r`nAPI permissions > Grant admin consent for <tenant>.`r`n`r`nThe link has been copied to the clipboard. Open it now?`r`n`r`n$consentUrl"
if ([System.Windows.Forms.MessageBox]::Show($consentMessage, 'Admin consent required', [System.Windows.Forms.MessageBoxButtons]::YesNo) -eq 'Yes')
{
	Start-Process $consentUrl
}
