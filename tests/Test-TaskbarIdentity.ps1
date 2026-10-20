#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$env:PSModulePath = [IO.Path]::Combine($env:WINDIR, 'System32', 'WindowsPowerShell', 'v1.0', 'Modules')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'SlotPaste.ps1'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Syntaxfehler in SlotPaste.ps1.' }
$nativeSource = $ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.StringConstantExpressionAst] -and
    $node.Value.Contains('public static class TaskbarIdentity')
}, $true) | Select-Object -First 1
if ($null -eq $nativeSource) { throw 'Taskleisten-Implementierung fehlt.' }
Add-Type -TypeDefinition $nativeSource.Value -ReferencedAssemblies System.Windows.Forms.dll,System.Drawing.dll
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class TaskbarIdentityProbe {
    [DllImport("shell32.dll")]
    public static extern int GetCurrentProcessExplicitAppUserModelID(out IntPtr appId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr SendMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
}
'@
[SlotPaste.TaskbarIdentity]::Initialize()
$pointer = [IntPtr]::Zero
try {
    [Runtime.InteropServices.Marshal]::ThrowExceptionForHR([TaskbarIdentityProbe]::GetCurrentProcessExplicitAppUserModelID([ref]$pointer))
    if ([Runtime.InteropServices.Marshal]::PtrToStringUni($pointer) -cne 'SlotPaste.Desktop') {
        throw 'Windows hat die SlotPaste-App-Identität nicht übernommen.'
    }
} finally {
    if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::FreeCoTaskMem($pointer) }
}
$form = New-Object Windows.Forms.Form
$icon = [Drawing.Icon]::new((Join-Path (Split-Path $PSScriptRoot -Parent) 'SlotPaste.ico'), 32, 32)
try {
    $form.Icon = $icon
    $form.ShowInTaskbar = $true
    $handle = $form.Handle
    foreach ($kind in @(0, 1)) {
        $windowIcon = [TaskbarIdentityProbe]::SendMessage($handle, 0x007F, [IntPtr]$kind, [IntPtr]::Zero)
        if ($windowIcon -eq [IntPtr]::Zero) { throw "Fenster-Symbol fehlt (WM_GETICON $kind)." }
    }
} finally {
    $form.Dispose()
    $icon.Dispose()
}
Write-Output 'OK: Windows erkennt SlotPaste.Desktop; kleines und großes Fenster-Symbol vorhanden.'
