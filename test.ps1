param(
    [Parameter(Mandatory)]
    [string] $ResourceGroup,
    
    [string] $Region = "Central US",
    
    [string] $SubscriptionId = "3e80626f-af91-4f0a-98ea-26ec24654d8e",
    
    # Allowed values : DotNet6InProcFunctionFiles, DotNet3InProcFunctionFiles
    [string] $FunctionFilesPath = "$PSScriptRoot/DotNet6InProcFunctionFiles",

    [string] $FunctionRuntime= "dotnet",

    # Allowed values : v6.0, ""
    [string] $NetFrameWorkVersion = "v6.0",

    [bool] $Use32BitWorker = $True
)

#################################################################################################
# Validate parameters
#################################################################################################

If ("v6.0", "" -NotContains $NetFrameWorkVersion)
{
    Throw "$NetFrameWorkVersion is not a valid NetFrameWorkVersion. Use v6.0 or empty for v3.1"
}

If ("dotnet” -NotContains $FunctionRuntime)
{
    Throw "$FunctionRuntime is not a valid Runtime. This script only supports dotnet"
}

#################################################################################################
# Get Function App contents to pass to deployment
#################################################################################################

$RunCsxPath = Resolve-Path $FunctionFilesPath/run.csx
$ProjPath = Resolve-Path $FunctionFilesPath/function.proj

# Read bytes from files
$RunCsxBytes = [System.IO.File]::ReadAllBytes($RunCsxPath);
$ProjBytes = [System.IO.File]::ReadAllBytes($ProjPath);

# convert contents to base64 string, which will be decoded in the ARM template to ensure all the characters are interpreted correctly
$RunCsxContent = [System.Convert]::ToBase64String($RunCsxBytes);
$ProjContent = [System.Convert]::ToBase64String($ProjBytes);

#################################################################################################
# Set other variables required to deploy ARM template
#################################################################################################

## remove any characters that aren't letters or numbers, and then validate
$storageAccountName = "$($ResourceGroup.ToLower())sa"
$storageAccountName = [regex]::Replace($storageAccountName, "[^a-z0-9]", "")
if (-not ($storageAccountName -match "^[a-z0-9][a-z0-9]{1,22}[a-z0-9]$"))
{
    throw "Storage account name derrived from resource group has illegal characters: $storageAccountName"
}

######################################################################################################
# Get-ResourceGroup - Finds or creates the resource group to be used by the
# deployment.
######################################################################################################

$rgExists = az group exists --name $ResourceGroup
if ($rgExists -eq "False")
{
    Write-Host "`nCreating resource group $ResourceGroup in $Region"
    az group create --name $ResourceGroup --location $Region --output none
}

#######################################################################################################
# Invoke-Deployment - Uses the .\.json template to
# create the necessary resources to run E2E tests.
#######################################################################################################

# Create a unique deployment name
$randomSuffix = -join ((65..90) + (97..122) | Get-Random -Count 5 | ForEach-Object { [char]$_ })
$deploymentName = "ServerlessSecurityTest-$randomSuffix"

# Deploy
Write-Host @"
    `n
    Starting deployment which may take a while.

    Track progress at https://ms.portal.azure.com/#@microsoft.onmicrosoft.com/resource/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/deployments

    Depployment Id: $deploymentName
"@

az deployment group create `
    --resource-group $ResourceGroup `
    --name $deploymentName `
    --output none `
    --only-show-errors `
    --template-file "$PSScriptRoot\test.json" `
    --parameters `
    StorageAccountName=$storageAccountName `
    RunCsxContent=$RunCsxContent `
    ProjContent=$ProjContent `
    FunctionRuntime=$FunctionRuntime `
    NetFrameWorkVersion=$NetFrameWorkVersion `
    Use32BitWorker=$Use32BitWorker

if ($LastExitCode -ne 0)
{
    throw "Error running resource group deployment."
}

Write-Host "`nYour infrastructure is ready in subscription ($SubscriptionId), resource group ($ResourceGroup)."