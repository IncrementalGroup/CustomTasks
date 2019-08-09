 Param(
        [Parameter(Mandatory = $true)]
        [string]
        $SourceFolder,
        [Parameter(Mandatory = $true)]
        [string]
        $Destination
    )

function Install-Package ($ver, $Folder) {
     <#
		.SYNOPSIS
		Deploys AX Package to local machine

		.DESCRIPTION
        This function takes the path of the downloaded Azure DevOps package, moves and renames the package. Two master files needed for the deployment and copied and replace the current files. It then creates a runbook from the package and the excutes it.
    
        .PARAMETER ver
		The current ID of the package from HotfixInstallationInfo.xml 

		.PARAMETER downloadFolder
		Current location of package folder

		.EXAMPLE
		Install-Package $currentVersionFile $packageName

		.NOTES
			Author: Zoe Mackay
			Created: October 2018			
    #>
    Write-Host $ver $folder
    #region Parameters
    $runbookId = 'Runbook_' + $ver
    $ErrorActionPreference = 'Stop'
    #endregion
 
    #region Derived values
    $runbookFile = Join-Path 'C:\RunbookOutput' ($runbookId + '.xml')
    $topologyFile = Join-Path $folder 'DefaultTopologyData.xml'
    $serviceModelFile = Join-Path $folder 'DefaultServiceModelData.xml'
    #endregion
    
    #change working directory to deployable folder
    Set-Location $folder

    #copy master files for deployment into the current deployable package
    #Add-Content -Path $logFile -Value ((Get-Date -Format "dd-MM-yyyy hh:mm") + " Copying master files to  " + $folder)
    #Copy-Item G:\DeployablePackages\DefaultServiceModelData.xml -Destination $folder -Force
    #Copy-Item G:\DeployablePackages\DefaultTopologyData.xml -Destination $folder -Force

    #creating topology data file
    [xml]$xml = Get-Content $topologyFile
    $machine = $xml.TopologyData.MachineList.Machine
 
    # Set computer name
    $machine.Name = $env:computername
 
    #Set service models
    $serviceModelList = $machine.ServiceModelList
    $serviceModelList.RemoveAll()
 
    $instalInfoDll = Join-Path $folder 'Microsoft.Dynamics.AX.AXInstallationInfo.dll'
    [void][System.Reflection.Assembly]::LoadFile($instalInfoDll)
 
    $models = [Microsoft.Dynamics.AX.AXInstallationInfo.AXInstallationInfo]::GetInstalledServiceModel()
    foreach ($name in $models.Name)
    {
        $element = $xml.CreateElement('string')
        $element.InnerText = $name
        $serviceModelList.AppendChild($element)
    }
 
    $xml.Save($topologyFile)

    #generate runbook
    Add-Content -Path $logFile -Value ((Get-Date -Format "dd-MM-yyyy hh:mm") + " Generating runbook  " + $runbookId + " " + $runbookFile)
    .\AXUpdateInstaller.exe generate -runbookid="$runbookid" -topologyfile="$topologyFile" -servicemodelfile="$serviceModelFile" -runbookfile="$runbookFile"

    #import runbook
    .\AXUpdateInstaller.exe import -runbookfile="$runbookFile"
        
    #run runbook
    Add-Content -Path $logFile -Value ((Get-Date -Format "dd-MM-yyyy hh:mm") + " Excuting runbook  " + $runbookId)
    .\AXUpdateInstaller.exe execute -runbookid="$runbookid" > 'AXDeployment.Log' #start logging for package deployment
    
    Write-Host "Deployment has finished with code: " $LastExitCode
    if ($LastExitCode -ne 0) {
        $axlog =  Join-Path $Package "AXDeployment.Log"
        Write-Host "##vso[task.uploadfile]$axlog"
        Write-Host "##vso[task.uploadfile]$logfile"
        if(Select-String -Path .\AXDeployment.Log -Pattern 'The step: 8 is in failed state')
        {
            .\AXUpdateInstaller.exe execute -runbookId="$runbookId" -rerunstep=8 > 'AXDeployment_Attempt2.Log' #start logging for package deployment
			if($LastExitCode -ne 0)
			{
				throw "Deployment failed with exit code $LastExitCode. Please check logs $folder."   
			}  
        }
        else
        {
            throw "Deployment failed with exit code $LastExitCode. Please check logs $folder."
        }
    }

    #export runbook
    Add-Content -Path $logFile -Value ((Get-Date -Format "dd-MM-yyyy hh:mm") + " Exporting runbook  " + $runbookFile)
    .\AXUpdateInstaller.exe export -runbookid="$runbookid" -runbookfile="$runbookFile"

}
##if destination drive folder doesnt exists check each drive for deployablepackages folder
if((Test-Path $Destination) -eq $false)
{
    $Drives = Get-WmiObject Win32_LogicalDisk
    foreach($Drive in $Drives)
    {
        $TempPath = Join-Path $Drive.DeviceID "DeployablePackages"
        if(Test-Path $TempPath)
        {
            $Destination = $TempPath
            break
        }
    }
}

Write-Output $Destination

$logfile = Join-Path $Destination "PSDeploy.log"

$PackageFolder = Get-ChildItem $SourceFolder -Filter AXDeploy*
$DestinationFolder = (Join-Path $Destination $PackageFolder.Name) -replace ".zip", ""
Add-Content -Path $logfile -Value ((Get-Date -Format "dd-MM-yyyy hh:mm") + " Starting the deployment for package " + $PackageFolder.FullName)
    
# Unzip's the AXDeployableRuntime DeployablePackage folder
Add-Type -assembly 'system.io.compression.filesystem'
[io.compression.zipfile]::ExtractToDirectory($packageFolder.FullName, $DestinationFolder)

#update folder name to version ID
[xml]$currentVersionFile = Get-Content ($DestinationFolder + '\HotfixInstallationInfo.xml')
try
{
    Rename-Item -Path $DestinationFolder -NewName $currentVersionFile.HotfixInstallationInfo.Name
}
catch
{
    #If there is an error renaming package its because it already exisits
    #Delete folder and exit script
    Remove-Item -Path $DestinationFolder -Recurse
    Add-Content -Path $logfile -Value ((Get-Date -Format "dd-MM-yyyy hh:mm") + " Package has already been installed " + $DestinationFolder)
    Write-Output "Package has already been installed exiting release" $currentVersionFile.HotfixInstallationInfo.Name
    ##Exit
}

$Package = Join-Path $Destination $currentVersionFile.HotfixInstallationInfo.Name
Add-Content -Path $logfile -Value ((Get-Date -Format "dd-MM-yyyy hh:mm") + " Moved and renamed folder, now " + $Package )
#run function to deploy package  
Install-Package $currentVersionFile.HotfixInstallationInfo.Name $Package

#ending deployment updating and upload any logs
Add-Content -Path $logfile -Value ((Get-Date -Format "dd-MM-yyyy hh:mm") + " Deployment has complete Errors: " + $Error)

$axlog =  Join-Path $Package "AXDeployment.Log"

##troubleshooting log upload
$contentAXlog = Get-Content $axlog
Write-Host "AXLog: " $axlog " Content: " $contentAXlog.Length

$contentLogFile = Get-Content $logfile
Write-Host " LogFile: " $logfile " Content: " $contentLogFile.Length
Write-Host "##vso[task.uploadfile]$axlog"
Write-Host "##vso[task.uploadfile]$logfile"