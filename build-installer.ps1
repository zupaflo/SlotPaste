#requires -Version 5.1

param(
    [switch]$SelfContainedApp
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
$root = $PSScriptRoot
$projectPath = Join-Path $root 'installer\SlotPaste.Setup.csproj'
$publishDirectory = Join-Path $root 'installer\publish'
$outputPath = Join-Path $root 'SlotPaste-Setup.exe'
$dotnetCliHome = Join-Path $root '.dotnet-home'
$nugetConfig = Join-Path $root 'NuGet.Config'
$packagesDirectory = Join-Path $root '.nuget-packages'
$nugetAppData = Join-Path $root '.nuget-appdata'

if (-not (Get-Command dotnet.exe -ErrorAction SilentlyContinue)) {
    throw 'Das .NET 8 SDK wurde nicht gefunden.'
}

Write-Host 'Baue zuerst die aktuelle SlotPaste-App ...' -ForegroundColor Cyan
& (Join-Path $root 'build.ps1')
if ($LASTEXITCODE -ne 0) { throw "Der SlotPaste-App-Build ist mit Code $LASTEXITCODE fehlgeschlagen." }

[void][System.IO.Directory]::CreateDirectory($dotnetCliHome)
[void][System.IO.Directory]::CreateDirectory($nugetAppData)
[void][System.IO.Directory]::CreateDirectory($packagesDirectory)
$env:DOTNET_CLI_HOME = $dotnetCliHome
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
$env:APPDATA = $nugetAppData

if (Test-Path -LiteralPath $publishDirectory) {
    Remove-Item -LiteralPath $publishDirectory -Recurse -Force
}

& dotnet.exe restore $projectPath `
    --runtime win-x64 `
    --configfile $nugetConfig `
    --packages $packagesDirectory `
    --nologo
if ($LASTEXITCODE -ne 0) { throw "dotnet restore ist mit Code $LASTEXITCODE fehlgeschlagen." }

$publishArguments = @(
    '--configuration', 'Release',
    '--runtime', 'win-x64',
    '--self-contained', 'true',
    '--output', $publishDirectory,
    '--no-restore',
    '--nologo',
    '-p:PublishSingleFile=true',
    '-p:IncludeNativeLibrariesForSelfExtract=true',
    '-p:DebugType=None'
)
& dotnet.exe publish $projectPath @publishArguments
if ($LASTEXITCODE -ne 0) { throw "dotnet publish ist mit Code $LASTEXITCODE fehlgeschlagen." }

$builtInstaller = Join-Path $publishDirectory 'SlotPaste.Setup.exe'
if (-not (Test-Path -LiteralPath $builtInstaller)) {
    throw "Die erwartete Installer-Datei wurde nicht erzeugt: $builtInstaller"
}

Copy-Item -LiteralPath $builtInstaller -Destination $outputPath -Force
$sizeMb = [math]::Round((Get-Item -LiteralPath $outputPath).Length / 1MB, 1)
Write-Host "SlotPaste-Setup.exe wurde erstellt: $outputPath ($sizeMb MB)" -ForegroundColor Green
