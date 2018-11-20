Param(
   [string] [Parameter(Mandatory=$true)] $ArtifactStagingDirectory,
   [string] [Parameter(Mandatory=$true)] $destApplicationId,
   [string] [Parameter(Mandatory=$true)] $destApplicationKey
)

#
# Detect tools folder, exit if no tools folder exists
# 
$toolsFolderPath = $ArtifactStagingDirectory+'\tools\'
$toolsExisting = [System.Boolean](Test-Path $toolsFolderPath)

if ($toolsExisting)
{
    Write-Host "Tools folder found in $ArtifactStagingDirectory"    
    # invoke tools\Labs-Template-Tools.ps1 if tools folder exists
    $scriptPath = $ArtifactStagingDirectory+'\tools\Labs-Template-Tool.ps1'
    $argumentList = '-ArtifactStagingDirectory "$ArtifactStagingDirectory" -destApplicationId $destApplicationId -destApplicationKey $destApplicationKey'

    Write-Host "Running template specific script"
    Write-Host "$scriptPath $argumentList"

    Invoke-Expression "& `"$scriptPath`" $argumentList"
}
else {
    Write-Host "Tools folder not found in $ArtifactStagingDirectory, runing labs script now."
}