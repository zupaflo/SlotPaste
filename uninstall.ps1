#requires -Version 5.1

$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Run', $true)
if ($null -ne $key) {
    try { $key.DeleteValue('SlotPaste', $false) } finally { $key.Dispose() }
}
Write-Host 'SlotPaste wurde aus dem Windows-Autostart entfernt.' -ForegroundColor Green
