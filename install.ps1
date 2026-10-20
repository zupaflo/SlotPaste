#requires -Version 5.1

$ErrorActionPreference = 'Stop'
$exePath = Join-Path $PSScriptRoot 'SlotPaste.exe'
$scriptPath = Join-Path $PSScriptRoot 'SlotPaste.ps1'
if (-not (Test-Path -LiteralPath $exePath) -and -not (Test-Path -LiteralPath $scriptPath)) {
    throw "Weder SlotPaste.exe noch SlotPaste.ps1 wurde gefunden."
}

$powershell = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
if (-not $powershell) { $powershell = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source }
if (-not $powershell) { throw 'Keine PowerShell-Ausführungsdatei gefunden.' }

$startFile = $scriptPath
$startArguments = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $scriptPath)
$hasDesktopRuntime = $false
$dotnet = Get-Command dotnet.exe -ErrorAction SilentlyContinue
if ($dotnet) {
    $runtimes = @(& $dotnet.Source --list-runtimes 2>$null)
    $hasDesktopRuntime = ($LASTEXITCODE -eq 0 -and ($runtimes -match '^Microsoft\.WindowsDesktop\.App\s+8\.'))
}

if ((Test-Path -LiteralPath $exePath) -and $hasDesktopRuntime) {
    $startFile = $exePath
    $startArguments = @()
    $runCommand = '"{0}"' -f $exePath
} else {
    $runCommand = '"{0}" -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}"' -f $powershell, $scriptPath
    if (Test-Path -LiteralPath $exePath) {
        Write-Host 'Keine .NET-8-Desktop-Runtime gefunden; starte SlotPaste über PowerShell.' -ForegroundColor Yellow
    }
}

# Ein nicht erreichbarer Netzwerkpfad in PSModulePath kann verhindern, dass
# Windows PowerShell seine Standardmodule wie Join-Path automatisch lädt.
$localModulePaths = @(
    (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\Modules')
    (Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules')
) | Where-Object { Test-Path -LiteralPath $_ }
if ($localModulePaths.Count -gt 0) {
    $env:PSModulePath = $localModulePaths -join ';'
}

$key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\Microsoft\Windows\CurrentVersion\Run')
try {
    $key.SetValue('SlotPaste', $runCommand, [Microsoft.Win32.RegistryValueKind]::String)
} finally {
    $key.Dispose()
}

Write-Host 'SlotPaste wurde für den Windows-Autostart eingerichtet.' -ForegroundColor Green
Write-Host 'Starte jetzt SlotPaste ...'
if ($startArguments.Count -gt 0) {
    Start-Process -FilePath $startFile -WindowStyle Hidden -ArgumentList $startArguments
} else {
    Start-Process -FilePath $startFile -WindowStyle Hidden
}
