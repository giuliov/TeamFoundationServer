function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$ControllerName,

		[parameter(Mandatory = $true)]
		[System.String]
		$CollectionUrl,

		[parameter(Mandatory = $true)]
		[System.Management.Automation.PSCredential]
		$ServiceAccount
	)

    # Load the necessary assemblies
    Add-Type -AssemblyName "Microsoft.TeamFoundation.Client,Version=12.0.0.0,Culture=neutral,PublicKeyToken=b03f5f7f11d50a3a"
    Add-Type -AssemblyName "Microsoft.TeamFoundation.Build.Client,Version=12.0.0.0,Culture=neutral,PublicKeyToken=b03f5f7f11d50a3a"

    # Open up a connection to TFS and ensure that we can authenticate
    Write-Verbose "Opening connection to Team Project Collection at $CollectionUrl authenticating as $($ServiceAccount.UserName)"
    $collection = New-Object Microsoft.TeamFoundation.Client.TfsTeamProjectCollection($CollectionUrl, $ServiceAccount)
    $collection.EnsureAuthenticated()

    # Get the build server instance
    Write-Verbose "Getting build server instance from Team Project Collection $($collection.Name)"
    $buildServer = $collection.GetService("Microsoft.TeamFoundation.Build.Client.IBuildServer")
    if ($buildServer -eq $null) {
        Write-Verbose "No build server instance found for Team Project Collection $($collection.Name)"
        $ensure = "Absent"
    } else {
        Write-Verbose "Searching for build controller with name $ControllerName in Team Project Collection $($collection.Name)"
        $buildController = $buildServer.QueryBuildControllers() | ? { $_.Name -eq $ControllerName } | Select-Object -First 1
        if ($buildController -eq $null) {
            Write-Verbose "No build controller with the name $ControllerName could be found in Team Project Collection $($collection.Name)"
            $ensure = "Absent"
        } else {
            Write-Verbose "Found build controller with name $ControllerName in Team Project Collection $($collection.Name)"
            $ensure = "Present"
            $numberOfAgents = $buildController.Agents.Count
        }
    }

	$returnValue = @{
		ControllerName = $ControllerName
		CollectionUrl = $CollectionUrl
		Ensure = $ensure
		ServiceAccount = $ServiceAccount
		NumberOfAgents = $numberOfAgents
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
		$ControllerName,

		[parameter(Mandatory = $true)]
		[System.String]
		$CollectionUrl,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure,

		[parameter(Mandatory = $true)]
		[System.Management.Automation.PSCredential]
		$ServiceAccount,

		[System.Int32]
		$NumberOfAgents
	)

    # Find TfsConfig executable and make sure it exists
    Write-Verbose "Locating TfsConfig.exe"
    $tfsConfig = $env:ProgramFiles + "\Microsoft Team Foundation Server 12.0\Tools\TfsConfig.exe"
    if ((Test-Path $tfsConfig) -eq $false) {
        throw "Microsoft Team Foundation Server 2013 is not yet installed on this machine."
    }

    # Determine if we need to configure or unconfigure
    $credential = $ServiceAccount.GetNetworkCredential()
    $tfsConfigInputs = "CollectionUrl=$CollectionUrl;IsServiceAccountBuiltIn=False;ServiceAccountName=$($credential.UserName);ServiceAccountPassword=$($credential.Password);"
    $tfsConfigInputs += "ConfigurationType=create;AgentCount=$NumberOfAgents"
    if ($Ensure -eq "Present") {
        # Execute the TfsConfig tool (as the service account) to verify an unattended configuration
        $exitCode = Invoke-Command -ComputerName localhost -Credential $ServiceAccount -Authentication Credssp -ErrorAction Stop -ScriptBlock {
            $VerbosePreference = 'Continue'
            Write-Verbose "$Using:tfsConfig unattend /configure /type:build /inputs:'$Using:tfsConfigInputs' /verify"
            & $Using:tfsConfig unattend /configure /type:build /inputs:"$Using:tfsConfigInputs" /verify 2>&1 | Write-Verbose
            $LASTEXITCODE
        }

        # Make sure that the verification ran correctly
        if ($exitCode -ne 0) {
            throw "Verifying the configuration failed with exit code $exitCode"
        }

        # Run the actual configuration
        $exitCode = Invoke-Command -ComputerName localhost -Credential $ServiceAccount -Authentication Credssp -ErrorAction Stop -ScriptBlock {
            $VerbosePreference = 'Continue'
            Write-Verbose "$Using:tfsConfig unattend /configure /type:build /inputs:'$Using:tfsConfigInputs' /continue"
            & $Using:tfsConfig unattend /configure /type:build /inputs:"$Using:tfsConfigInputs" /continue 2>&1 | Write-Verbose
            $LASTEXITCODE
        }

        # Make sure that the actual configuration ran correctly
        if ($exitCode -ne 0) {
            throw "Configuration failed with exit code $exitCode"
        }
    } else {
        # Execute the TfsConfig tool to unconfigure the build
        $exitCode = Invoke-Command -ComputerName localhost -Credential $ServiceAccount -Authentication Credssp -ErrorAction Stop -ScriptBlock {
            $VerbosePreference = 'Continue'
            Write-Verbose "$Using:tfsConfig setup /uninstall:TeamBuild"
            & $Using:tfsConfig setup /uninstall:TeamBuild
            $LASTEXITCODE
        }

        # Make sure that the uninstall ran correctly
        if ($exitCode -ne 0) {
            throw "Uninstalling Team Build failed with exit code $exitCode"
        }
    }

	#Include this line if the resource requires a system reboot.
	#$global:DSCMachineStatus = 1
}



function Test-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Boolean])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$ControllerName,

		[parameter(Mandatory = $true)]
		[System.String]
		$CollectionUrl,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure,

		[parameter(Mandatory = $true)]
		[System.Management.Automation.PSCredential]
		$ServiceAccount,

		[System.Int32]
		$NumberOfAgents
	)

    # Load the necessary assemblies
    Add-Type -AssemblyName "Microsoft.TeamFoundation.Client,Version=12.0.0.0,Culture=neutral,PublicKeyToken=b03f5f7f11d50a3a"
    Add-Type -AssemblyName "Microsoft.TeamFoundation.Build.Client,Version=12.0.0.0,Culture=neutral,PublicKeyToken=b03f5f7f11d50a3a"

	# Open up a connection to TFS and ensure that we can authenticate
    Write-Verbose "Opening connection to Team Project Collection at $CollectionUrl authenticating as $($ServiceAccount.UserName)"
    $collection = New-Object Microsoft.TeamFoundation.Client.TfsTeamProjectCollection($CollectionUrl, $ServiceAccount.GetNetworkCredential())
    $collection.EnsureAuthenticated()

    # Get the build server instance
    Write-Verbose "Getting build server instance from Team Project Collection $($collection.Name)"
    $buildServer = $collection.GetService("Microsoft.TeamFoundation.Build.Client.IBuildServer")
    if ($buildServer -eq $null) {
        Write-Verbose "No build server instance found for Team Project Collection $($collection.Name)"
        $currentEnsure = "Absent"
    } else {
        Write-Verbose "Searching for build controller with name $ControllerName in Team Project Collection $($collection.Name)"
        $buildController = $buildServer.QueryBuildControllers() | ? { $_.Name -eq $ControllerName } | Select-Object -First 1
        if ($buildController -eq $null) {
            Write-Verbose "No build controller with the name $ControllerName could be found in Team Project Collection $($collection.Name)"
            $currentEnsure = "Absent"
        } else {
            Write-Verbose "Found build controller with name $ControllerName in Team Project Collection $($collection.Name)"
            $currentEnsure = "Present"
            $currentNumberOfAgents = $buildController.Agents.Count
        }
    }

	$result = $Ensure -eq $currentEnsure -And $NumberOfAgents -eq $currentNumberOfAgents
	
	$result
}



Export-ModuleMember -Function *-TargetResource


