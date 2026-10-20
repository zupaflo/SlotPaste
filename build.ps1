#requires -Version 5.1

param(
    [switch]$SelfContained
)

$ErrorActionPreference = 'Stop'
$localModulePaths = @()
$systemModules = [System.IO.Path]::Combine($env:WINDIR, 'System32', 'WindowsPowerShell', 'v1.0', 'Modules')
$programModules = [System.IO.Path]::Combine($env:ProgramFiles, 'WindowsPowerShell', 'Modules')
if ([System.IO.Directory]::Exists($systemModules)) { $localModulePaths += $systemModules }
if ([System.IO.Directory]::Exists($programModules)) { $localModulePaths += $programModules }
if ($localModulePaths.Count -gt 0) {
    $env:PSModulePath = $localModulePaths -join ';'
    [Environment]::SetEnvironmentVariable('PSModulePath', $env:PSModulePath, 'Process')
}
$projectPath = Join-Path $PSScriptRoot 'launcher\SlotPaste.Launcher.csproj'
$publishDirectory = Join-Path $PSScriptRoot 'launcher\publish'
$outputPath = Join-Path $PSScriptRoot 'SlotPaste.exe'
$dotnetCliHome = Join-Path $PSScriptRoot '.dotnet-home'
$nugetConfig = Join-Path $PSScriptRoot 'NuGet.Config'
$packagesDirectory = Join-Path $PSScriptRoot '.nuget-packages'
$nugetAppData = Join-Path $PSScriptRoot '.nuget-appdata'

if (-not (Test-Path -LiteralPath $projectPath)) {
    throw "Launcher-Projekt nicht gefunden: $projectPath"
}

if (-not (Get-Command dotnet.exe -ErrorAction SilentlyContinue)) {
    throw 'Das .NET 8 SDK wurde nicht gefunden. Installiere es mit: winget install Microsoft.DotNet.SDK.8'
}

[void][System.IO.Directory]::CreateDirectory($dotnetCliHome)
[void][System.IO.Directory]::CreateDirectory($nugetAppData)
$env:DOTNET_CLI_HOME = $dotnetCliHome
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
$env:APPDATA = $nugetAppData

if (Test-Path -LiteralPath $publishDirectory) {
    Remove-Item -LiteralPath $publishDirectory -Recurse -Force
}

[void][System.IO.Directory]::CreateDirectory($packagesDirectory)
& dotnet.exe restore $projectPath `
    --runtime win-x64 `
    --configfile $nugetConfig `
    --packages $packagesDirectory `
    --nologo

if ($LASTEXITCODE -ne 0) {
    throw "dotnet restore ist mit Code $LASTEXITCODE fehlgeschlagen."
}

$publishArguments = @(
    '--configuration', 'Release',
    '--runtime', 'win-x64',
    '--self-contained', ($(if ($SelfContained) { 'true' } else { 'false' })),
    '--output', $publishDirectory,
    '--no-restore',
    '--nologo',
    '-p:PublishSingleFile=true'
)
if ($SelfContained) {
    $publishArguments += '-p:IncludeNativeLibrariesForSelfExtract=true'
} else {
    $publishArguments += '-p:IncludeNativeLibrariesForSelfExtract=false'
}

& dotnet.exe publish $projectPath @publishArguments

if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish ist mit Code $LASTEXITCODE fehlgeschlagen."
}

$builtExe = Join-Path $publishDirectory 'SlotPaste.exe'
if (-not (Test-Path -LiteralPath $builtExe)) {
    throw "Die erwartete Datei wurde nicht erzeugt: $builtExe"
}

Copy-Item -LiteralPath $builtExe -Destination $outputPath -Force
Write-Host "SlotPaste.exe wurde erstellt: $outputPath" -ForegroundColor Green
