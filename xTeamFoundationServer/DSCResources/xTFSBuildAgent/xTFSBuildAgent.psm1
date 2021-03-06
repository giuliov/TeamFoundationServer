function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$AgentName,

		[parameter(Mandatory = $true)]
		[System.String]
		$PoolName,

		[parameter(Mandatory = $true)]
		[System.String]
		$ServerUrl,

		[parameter(Mandatory = $true)]
		[System.String]
		$AgentFolder,
		
		[parameter(Mandatory = $true)]
		[System.Boolean]
		$RunAsWindowsService,
		
		[parameter(Mandatory = $true)]
		[PSCredential]
		$WindowsServiceCredential
	)
	
	# Try to find the agent in the specified folder
	Write-Verbose "Locating agent in agent folder $AgentFolder"
	if (Test-Path $AgentFolder) {
		# Make sure that a settings.json file exists at the location
		$settingsJsonFile = Join-Path $AgentFolder "settings.json"
		if (Test-Path $settingsJsonFile) {
			# Get the settings from the file
			$settings = Get-Content -Raw $settingsJsonFile | ConvertFrom-Json
			$AgentName = $settings.AgentName
			$PoolName = $settings.PoolName
			$ServerUrl = $settings.ServerUrl
			$AgentFolder = $AgentFolder
			$RunAsWindowsService = [System.Convert]::ToBoolean($settings.RunAsWindowsService)
			$ensure = "Present"
		} else {
			# No settings.json file found, so we have no idea if there's an agent here
			Write-Verbose "No settings.json found in agent folder $AgentFolder"
			$ensure = "Absent"	
		}
	} else {
		# Agent folder wasn't found, so we're pretty sure it doesn't exist
		Write-Verbose "No agent found in agent folder $AgentFolder"
		$ensure = "Absent"
	}

	$returnValue = @{
		AgentName = $AgentName
		Ensure = $ensure
		PoolName = $PoolName
		ServerUrl = $ServerUrl
		AgentFolder = $AgentFolder
		RunAsWindowsService = $RunAsWindowsService
	}

	$returnValue
}


function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$AgentName,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure,

		[parameter(Mandatory = $true)]
		[System.String]
		$PoolName,

		[parameter(Mandatory = $true)]
		[System.String]
		$ServerUrl,

		[parameter(Mandatory = $true)]
		[System.String]
		$AgentFolder,

		[parameter(Mandatory = $true)]
		[System.Boolean]
		$RunAsWindowsService,

		[parameter(Mandatory = $true)]
		[System.Management.Automation.PSCredential]
		$WindowsServiceCredential
	)
	
	# Check if we need to ensure the agent is present or absent
	if ($Ensure -eq "Present") {
		# Ensure that the agent folder exists
		Write-Verbose "Checking if agent folder $AgentFolder already exists..."
		if (!(Test-Path $AgentFolder)) {
			# Create the agent folder
			Write-Verbose "Creating agent folder $AgentFolder"
			md $AgentFolder
			
			# Download the agent from the server
			Write-Verbose "Downloading agent from $ServerUrl/_apis/distributedTask/packages/agent to $AgentFolder\agent.zip"
			Invoke-WebRequest "$ServerUrl/_apis/distributedTask/packages/agent" -OutFile "$AgentFolder\agent.zip" -Credential $WindowsServiceCredential
			
			# Unzip the agent
			Write-Verbose "Unzipping agent into $AgentFolder"
			Add-Type -AssemblyName System.IO.Compression.FileSystem
			[System.IO.Compression.ZipFile]::ExtractToDirectory("$AgentFolder\agent.zip", "$AgentFolder")
			
			# Delete the zip
			Remove-Item "$AgentFolder\agent.zip"
			$reconfigure = $False
		} else {
			# Agent folder already exists
			Write-Verbose "Agent folder $AgentFolder already exists. Assuming reconfiguration."
			$reconfigure = $True
		}
		
		# Determine the configuration parameters
		$configureParameters = @("/configure", "/noprompt", "/serverUrl:$ServerUrl", "/name:$AgentName", "/PoolName:$PoolName")
		if ($RunAsWindowsService) {
			# Add the required parameters for configuring to run as a Windows Service
			$configureParameters += "/RunningAsService"
			$configureParameters +=	"/WindowsServiceLogonAccount:$($WindowsServiceCredential.UserName)"
			$configureParameters += "/WindowsServiceLogonPassword:$($WindowsServiceCredential.GetNetworkCredential().Password)"
		}
		
		# Check if we need to reconfigure the service
		if ($reconfigure) {
			$configureParameters += "/force"
		}
		
		# Run the configuration
		Write-Verbose "$AgentFolder\Agent\vsoAgent.exe $configureParameters"
		Invoke-Command -ScriptBlock { & "$Using:AgentFolder\Agent\vsoAgent.exe" $Using:configureParameters } -ComputerName localhost -Authentication CredSSP -Credential $WindowsServiceCredential 
	} elseif ($Ensure -eq "Absent") {
		# Unconfigure the agent
		Write-Verbose "$AgentFolder\Agent\vsoAgent.exe /unconfigure"
		Invoke-Command -ScriptBlock { & "$Using:AgentFolder\Agent\vsoAgent.exe" /unconfigure } -ComputerName localhost -Authentication CredSSP -Credential $WindowsServiceCredential
			
		# Remove the agent
		Remove-Item "$AgentFolder" 
	}	
}


function Test-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Boolean])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$AgentName,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure,

		[parameter(Mandatory = $true)]
		[System.String]
		$PoolName,

		[parameter(Mandatory = $true)]
		[System.String]
		$ServerUrl,

		[parameter(Mandatory = $true)]
		[System.String]
		$AgentFolder,

		[parameter(Mandatory = $true)]
		[System.Boolean]
		$RunAsWindowsService,

		[parameter(Mandatory = $true)]
		[System.Management.Automation.PSCredential]
		$WindowsServiceCredential
	)

	# Try to find the agent in the specified folder
	Write-Verbose "Locating agent in agent folder $AgentFolder"
	if (Test-Path $AgentFolder) {
		# Make sure that a settings.json file exists at the location
		$settingsJsonFile = Join-Path $AgentFolder "settings.json"
		if (Test-Path $settingsJsonFile) {
			# Get the settings from the file
			$settings = Get-Content -Raw $settingsJsonFile | ConvertFrom-Json
			$currentAgentName = $settings.AgentName
			$currentPoolName = $settings.PoolName
			$currentServerUrl = $settings.ServerUrl
			$currentAgentFolder = $AgentFolder
			$currentRunAsWindowsService = [System.Convert]::ToBoolean($settings.RunAsWindowsService)
			$currentEnsure = "Present"
		} else {
			# No settings.json file found, so we have no idea if there's an agent here
			Write-Verbose "No settings.json found in agent folder $AgentFolder"
			$currentEnsure = "Absent"	
		}
	} else {
		# Agent folder wasn't found, so we're pretty sure it doesn't exist
		Write-Verbose "No agent found in agent folder $AgentFolder"
		$currentEnsure = "Absent"
	}

	$result = ($currentEnsure -eq $Ensure) -And ($currentAgentName -eq $AgentName) -And ($currentPoolName -eq $PoolName) -And `
			  ($currentServerUrl -eq $ServerUrl) -And ($currentAgentFolder -eq $AgentFolder) -And ($currentRunAsWindowsService -eq $RunAsWindowsService)
	
	$result
}


Export-ModuleMember -Function *-TargetResource

