$rootDir = Split-Path -Parent $PSScriptRoot
$buildOutput = Join-Path $rootDir "buildoutput"
$packFeedTarget = "$rootDir\slsec\feed"
$hostFolder = "$rootDir/../azure-function-host"

function CleanBuild()
{
    Get-ChildItem .\ -include bin,obj -Recurse | ForEach-Object ($_) { Remove-Item $_.FullName -Force -Recurse }
}

function BuildRuntime([string] $targetRid, [bool] $isSelfContained) {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $publishTarget = "$buildOutput/publish/$targetRid"

    $pluginExPath   = "$PSScriptRoot/../Plugins/src/TestPlugins/PluginExample/PluginExample.csproj"
    $plIntPath      = "$PSScriptRoot/../Plugins/src/TestPlugins/PluginInterceptorTest/PluginInterceptorTest.csproj"
    $vulScanPlPath  = "$PSScriptRoot/../Plugins/src/VulnerabilityCollectorPlugin/VulnerabilityPlugin.csproj"
    $plMgrPath      = "$PSScriptRoot/../Platform/src/PluginMgr/PluginMgr.csproj"
    $grpcSvcPath    = "$PSScriptRoot/../Platform/src/GrpcServices/GrpcServices.csproj"
    $slsecHostPath  = "$PSScriptRoot/../Platform/src/ServerlessSecurityHost/ServerlessSecurityHost.csproj"


    if (-not (Test-Path $pluginExPath))
    {
        throw "Project path '$pluginExPath' does not exist."
    }
    elseif  (-not (Test-Path $plIntPath))
    {
        throw "Project path '$plIntPath' does not exist."
    }
    elseif  (-not (Test-Path $vulScanPlPath))
    {
        throw "Project path '$vulScanPlPath' does not exist."
    }
    elseif  (-not (Test-Path $plMgrPath))
    {
        throw "Project path '$plMgrPath' does not exist."
    }
    elseif  (-not (Test-Path $grpcSvcPath))
    {
        throw "Project path '$grpcSvcPath' does not exist."
    }
    elseif  (-not (Test-Path $slsecHostPath))
    {
        throw "Project path '$slsecHostPath' does not exist."
    }

    $cmd1 = "build", "$pluginExPath", "-r", "$targetRid", "--self-contained", "$isSelfContained", "/p:BuildNumber=$buildNumber", "/p:PackageOutputPath=$packFeedTarget", "-c", "Release"
    $cmd2 = "build", "$plIntPath", "-r", "$targetRid", "--self-contained", "$isSelfContained", "/p:BuildNumber=$buildNumber", "/p:PackageOutputPath=$packFeedTarget", "-c", "Release"
    $cmd3 = "build", "$vulScanPlPath", "-r", "$targetRid", "--self-contained", "$isSelfContained", "/p:BuildNumber=$buildNumber", "/p:PackageOutputPath=$packFeedTarget", "-c", "Release" , "--interactive"
    $cmd4 = "build", "$plMgrPath", "-r", "$targetRid", "--self-contained", "$isSelfContained", "/p:BuildNumber=$buildNumber", "/p:PackageOutputPath=$packFeedTarget", "-c", "Release"
    $cmd5 = "build", "$grpcSvcPath", "-r", "$targetRid", "--self-contained", "$isSelfContained", "/p:BuildNumber=$buildNumber", "/p:PackageOutputPath=$packFeedTarget", "-c", "Release"
    $cmd6 = "build", "$slsecHostPath", "-r", "$targetRid", "--self-contained", "$isSelfContained", "/p:BuildNumber=$buildNumber", "/p:PackageOutputPath=$packFeedTarget", "-c", "Release"

    Write-Output "======================================"
    Write-Output "Building $targetRid"
    Write-Output "  Self-Contained:    $isSelfContained"
    Write-Output "  Output Directory:  $packFeedTarget"
    Write-Output ""
    
    & dotnet $cmd1
    & dotnet $cmd2
    & dotnet $cmd3
    & dotnet $cmd4
    & dotnet $cmd5
    & dotnet $cmd6

    if ($LASTEXITCODE -ne 0)
    {
        Write-Output ""
        Write-Output "Try Executing By Passing PAT Token"
        Write-Output ""
        exit $LASTEXITCODE
    }

    Write-Output ""
    Write-Output "Done building $targetRid. Elapsed: $($stopwatch.Elapsed)"
    Write-Output "======================================"
    Write-Output ""
}

function WriteXmlToScreen ([xml]$xml)
{
    $StringWriter = New-Object System.IO.StringWriter;
    $XmlWriter = New-Object System.Xml.XmlTextWriter $StringWriter;
    $XmlWriter.Formatting = "indented";
    $xml.WriteTo($XmlWriter);
    $XmlWriter.Flush();
    $StringWriter.Flush();
    Write-Output $StringWriter.ToString();
}

function Checkout([string] $repo, [String]$branch)
{
    
    Write-Output "Checking out $branch from $repo."

    if (Test-Path -Path $hostFolder) {
        cd "$hostFolder"
        git fetch
        git checkout $branch
        git pull
    } 
    else
    {
        git clone $repo "$hostFolder"
        cd "$hostFolder"
        git fetch
        git checkout $branch
    }
    
    $NugetXML = [xml](Get-Content "NuGet.config")
    $canAddChild = $true;

    $addNodes = $NugetXML.SelectNodes("//add")

    foreach ($node in $addNodes) 
    {
        if($node.GetAttribute('key') -eq "slsec_local_feed") 
        {
            $canAddChild = $false
        }
    }

    if($canAddChild)
    {
        $childAdd = $NugetXML.CreateElement("add")
        $childAdd.SetAttribute('key', "slsec_local_feed")
        $childAdd.SetAttribute('value', $packFeedTarget)

        & $NugetXML.configuration.packageSources.AppendChild($childAdd)
        & $NugetXML.Save("$hostFolder/NuGet.config")
    }

    Start-Sleep -Seconds 5

    Write-Output "Host Code is Updated out of $branch from $repo."

    cd "$rootDir/build"
}

function PatToken([string] $token) 
{

    if(!$token) 
    {
        Write-Output ""
        Write-Output "No PAT Token Passed!!!"
        Write-Output ""
    } 
    else 
    {
        Write-Output ""
        Write-Output "PAT Token Passed!!!"
        Write-Output ""
        
        $cmd = "nuget", "add", "source", "https://msazure.pkgs.visualstudio.com/f3247cef-e371-4261-b105-33f9613c6d8e/_packaging/ServerlessSecurity/nuget/v3/index.json", "-u", "PAT", "-p", "$token", "-n", "Slsec"

        & dotnet $cmd

        Write-Output "PAT Token Added!!!"

    }
}

function BuildAzureFunctionHost() 
{
    cd "$hostFolder/build"

    Write-Output ""
    Write-Output "Building Windows Site Extension for Azure Function Host!!!"
    Write-Output ""

    ./build-extensions.ps1

    cd "$rootDir/build"
}

Write-Output ""
dotnet --info
Write-Output ""
Write-Output "Output directory: $buildOutput"
Write-Output ""

if (Test-Path $buildOutput) {
    Write-Output "  Existing build output found. Deleting."
    Remove-Item $buildOutput -Recurse -Force # -exclude "$buildOutput/azure-function-host"
}

if(Test-Path $packFeedTarget) {
    Write-Output "  Existing NuGet Feed found. Deleting."
    Remove-Item $packFeedTarget -Recurse -Force # -exclude "$buildOutput/azure-function-host"
}

if (Test-Path $hostFolder) {
    Write-Output "  Existing Azure Function Host code found. Deleting."
    Remove-Item $hostFolder -Recurse -Force
}

if (test-path -path "$env:USERPROFILE/.nuget/packages/grpcservices") {
    Write-Output "Deleting the Serverless Security old NuGets $env:USERPROFILE/.nuget/packages/grpcservices"
    Remove-Item $env:USERPROFILE/.nuget/packages/grpcservices -Recurse -Force
}

if (test-path -path "$env:USERPROFILE/.nuget/packages/grpcserviceswin-x86") {
    Write-Output "Deleting the Serverless Security old NuGets $env:USERPROFILE/.nuget/packages/grpcserviceswin-x86"
    Remove-Item $env:USERPROFILE/.nuget/packages/grpcserviceswin-x86 -Recurse -Force
}

if (test-path -path "$env:USERPROFILE/.nuget/packages/grpcserviceswin-x64") {
    Write-Output "Deleting the Serverless Security old NuGets $env:USERPROFILE/.nuget/packages/grpcserviceswin-x64"
    Remove-Item $env:USERPROFILE/.nuget/packages/grpcserviceswin-x64 -Recurse -Force
}

if (test-path -path "$env:USERPROFILE/.nuget/packages/grpcserviceslinux-x64") {
    Write-Output "Deleting the Serverless Security old NuGets $env:USERPROFILE/.nuget/packages/grpcserviceslinux-x64"
    Remove-Item $env:USERPROFILE/.nuget/packages/grpcserviceslinux-x64 -Recurse -Force
}

if (test-path -path "$env:USERPROFILE/.nuget/packages/pluginmgr") {
    Write-Output "Deleting the Serverless Security old NuGets $env:USERPROFILE/.nuget/packages/pluginmgr"
    Remove-Item $env:USERPROFILE/.nuget/packages/pluginmgr -Recurse -Force
}

if (test-path -path "$env:USERPROFILE/.nuget/packages/pluginmgrwin-x86") {
    Write-Output "Deleting the Serverless Security old NuGets $env:USERPROFILE/.nuget/packages/pluginmgrwin-x86"
    Remove-Item $env:USERPROFILE/.nuget/packages/pluginmgrwin-x86 -Recurse -Force
}

if (test-path -path "$env:USERPROFILE/.nuget/packages/pluginmgrwin-x64") {
    Write-Output "Deleting the Serverless Security old NuGets $env:USERPROFILE/.nuget/packages/pluginmgrwin-x64"
    Remove-Item $env:USERPROFILE/.nuget/packages/pluginmgrwin-x64 -Recurse -Force
}

if (test-path -path "$env:USERPROFILE/.nuget/packages/pluginmgrlinux-x64") {
    Write-Output "Deleting the Serverless Security old NuGets $env:USERPROFILE/.nuget/packages/pluginmgrlinux-x64"
    Remove-Item $env:USERPROFILE/.nuget/packages/pluginmgrlinux-x64 -Recurse -Force
}

if (test-path -path "$env:USERPROFILE/.nuget/packages/serverlesssecurity") {
    Write-Output "Deleting the Serverless Security old NuGets $env:USERPROFILE/.nuget/packages/serverlesssecurity"
    Remove-Item $env:USERPROFILE/.nuget/packages/serverlesssecurity -Recurse -Force
}

if (test-path -path "$env:USERPROFILE/.nuget/packages/serverlesssecuritywin-x86") {
    Write-Output "Deleting the Serverless Security old NuGets $env:USERPROFILE/.nuget/packages/serverlesssecuritywin-x86"
    Remove-Item $env:USERPROFILE/.nuget/packages/serverlesssecuritywin-x86 -Recurse -Force
}

if (test-path -path "$env:USERPROFILE/.nuget/packages/serverlesssecuritywin-x64") {
    Write-Output "Deleting the Serverless Security old NuGets $env:USERPROFILE/.nuget/packages/serverlesssecuritywin-x64"
    Remove-Item $env:USERPROFILE/.nuget/packages/serverlesssecuritywin-x64 -Recurse -Force
}

if (test-path -path "$env:USERPROFILE/.nuget/packages/serverlesssecuritylinux-x64") {
    Write-Output "Deleting the Serverless Security old NuGets $env:USERPROFILE/.nuget/packages/serverlesssecuritylinux-x64"
    Remove-Item $env:USERPROFILE/.nuget/packages/serverlesssecuritylinux-x64 -Recurse -Force
}

if (test-path -path "$env:USERPROFILE/.nuget/packages/vulnerabilityplugin") {
    Write-Output "Deleting the Serverless Security old NuGets $env:USERPROFILE/.nuget/packages/vulnerabilityplugin"
    Remove-Item $env:USERPROFILE/.nuget/packages/vulnerabilityplugin -Recurse -Force
}

if (test-path -path "$env:USERPROFILE/.nuget/packages/vulnerabilitypluginwin-x86") {
    Write-Output "Deleting the Serverless Security old NuGets $env:USERPROFILE/.nuget/packages/vulnerabilitypluginwin-x86"
    Remove-Item $env:USERPROFILE/.nuget/packages/vulnerabilitypluginwin-x86 -Recurse -Force
}

if (test-path -path "$env:USERPROFILE/.nuget/packages/vulnerabilitypluginwin-x64") {
    Write-Output "Deleting the Serverless Security old NuGets $env:USERPROFILE/.nuget/packages/vulnerabilitypluginwin-x64"
    Remove-Item $env:USERPROFILE/.nuget/packages/vulnerabilitypluginwin-x64 -Recurse -Force
}

if (test-path -path "$env:USERPROFILE/.nuget/packages/vulnerabilitypluginlinux-x64") {
    Write-Output "Deleting the Serverless Security old NuGets $env:USERPROFILE/.nuget/packages/vulnerabilitypluginlinux-x64"
    Remove-Item $env:USERPROFILE/.nuget/packages/vulnerabilitypluginlinux-x64 -Recurse -Force
}

PatToken $args[0]

CleanBuild
BuildRuntime "win-x86"
BuildRuntime "win-x64"
 
Checkout "https://github.com/Sourabh-MSFT/azure-functions-host.git" "SlSecBuild"

BuildAzureFunctionHost