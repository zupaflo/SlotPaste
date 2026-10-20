#requires -Version 5.1

<################################################################################
 SlotPaste – kleine Windows-Tray-Anwendung für wiederverwendbare Einfügungen

 Unterstützte Slot-Typen:
   Text  – Text wird in das aktive Fenster eingefügt.
   Bild  – Bild wird als Bild in das aktive Fenster eingefügt.
   Datei – Datei wird als Windows-Dateiablage eingefügt. Das eignet sich auch
           für Videos: Der Videopfad wird in die Zwischenablage gelegt.

 Die globale Tastenkombination legt den Slot-Inhalt in die normale Zwischenablage.
 Mit Strg+V kann der Inhalt anschließend selbst eingefügt werden.
#################################################################################>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Einen nicht erreichbaren Netzwerkpfad aus PSModulePath entfernen, bevor
# Windows PowerShell Standardbefehle wie Join-Path automatisch laden muss.
$localModulePaths = @()
$systemModules = [System.IO.Path]::Combine($env:WINDIR, 'System32', 'WindowsPowerShell', 'v1.0', 'Modules')
$programModules = [System.IO.Path]::Combine($env:ProgramFiles, 'WindowsPowerShell', 'Modules')
if ([System.IO.Directory]::Exists($systemModules)) { $localModulePaths += $systemModules }
if ([System.IO.Directory]::Exists($programModules)) { $localModulePaths += $programModules }
if ($localModulePaths.Count -gt 0) {
    $env:PSModulePath = $localModulePaths -join ';'
    [Environment]::SetEnvironmentVariable('PSModulePath', $env:PSModulePath, 'Process')
}

$script:AppName = 'SlotPaste'
$script:SlotCount = 9
$script:DataDirectory = Join-Path ([Environment]::GetFolderPath('ApplicationData')) $script:AppName
$script:AssetsDirectory = Join-Path $script:DataDirectory 'assets'
$script:ConfigPath = Join-Path $script:DataDirectory 'slots.json'
$script:StartupValueName = 'SlotPaste'
$script:StartupSubKey = 'Software\Microsoft\Windows\CurrentVersion\Run'
$script:EditorForm = $null
$script:RowUi = @{}
$script:AllowClose = $false
$script:Slots = @()
$script:ConfigurationLoaded = $false
$script:ConfigurationNotice = $null
$script:HotkeyWindow = $null
$script:TrayIcon = $null
$script:ApplicationMenu = $null

# RegisterHotKey modifier flags.
$script:ModAlt = 0x0001
$script:ModControl = 0x0002
$script:ModShift = 0x0004
$script:ModWin = 0x0008

try {
    [void][System.IO.Directory]::CreateDirectory($script:DataDirectory)
    [void][System.IO.Directory]::CreateDirectory($script:AssetsDirectory)
    $writeTestPath = [System.IO.Path]::Combine($script:DataDirectory, ".slotpaste-write-test-$PID.tmp")
    [System.IO.File]::WriteAllText($writeTestPath, 'SlotPaste')
    [System.IO.File]::Delete($writeTestPath)
} catch {
    $script:DataDirectory = Join-Path $PSScriptRoot 'data'
    $script:AssetsDirectory = Join-Path $script:DataDirectory 'assets'
    $script:ConfigPath = Join-Path $script:DataDirectory 'slots.json'
    [void][System.IO.Directory]::CreateDirectory($script:DataDirectory)
    [void][System.IO.Directory]::CreateDirectory($script:AssetsDirectory)
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security
[void][System.Windows.Forms.Application]::EnableVisualStyles()
[void][System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

# Einheitliches, modernes UI-Design.
$script:UiFontFamily = 'Segoe UI'

function New-UiFont {
    param(
        [float]$Size = 9,
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular
    )
    return New-Object System.Drawing.Font($script:UiFontFamily, $Size, $Style)
}

function Set-RoundedControlRegion {
    param(
        [System.Windows.Forms.Control]$Control,
        [int]$Radius = 28
    )

    if ($null -eq $Control -or $Control.IsDisposed -or $Control.Width -le 0 -or $Control.Height -le 0) { return }
    $diameter = [int][Math]::Min($Radius * 2, [Math]::Min($Control.Width, $Control.Height))
    if ($diameter -le 1) { return }
    $right = $Control.Width - $diameter
    $bottom = $Control.Height - $diameter
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    [void]$path.AddArc(0, 0, $diameter, $diameter, 180, 90)
    [void]$path.AddArc($right, 0, $diameter, $diameter, 270, 90)
    [void]$path.AddArc($right, $bottom, $diameter, $diameter, 0, 90)
    [void]$path.AddArc(0, $bottom, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    $oldRegion = $Control.Region
    $Control.Region = New-Object System.Drawing.Region($path)
    $path.Dispose()
    if ($null -ne $oldRegion) { $oldRegion.Dispose() }
}

function Style-RoundedButton {
    param(
        [System.Windows.Forms.Button]$Button,
        [switch]$Destructive
    )

    $Button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $Button.UseVisualStyleBackColor = $false
    $Button.Font = if ($Destructive) { New-UiFont -Size 12 -Style ([System.Drawing.FontStyle]::Bold) } else { New-UiFont -Size 10 -Style ([System.Drawing.FontStyle]::Regular) }
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $Button.Padding = New-Object System.Windows.Forms.Padding(12, 0, 12, 0)
    $Button.FlatAppearance.BorderSize = 0
    if ($Destructive) {
        $Button.BackColor = [System.Drawing.Color]::FromArgb(220, 53, 69)
        $Button.ForeColor = [System.Drawing.Color]::White
        $Button.HoverBackColor = [System.Drawing.Color]::FromArgb(190, 40, 55)
        $Button.PressedBackColor = [System.Drawing.Color]::FromArgb(160, 30, 43)
    } else {
        $Button.BackColor = [System.Drawing.Color]::Black
        $Button.ForeColor = [System.Drawing.Color]::White
        $Button.HoverBackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)
        $Button.PressedBackColor = [System.Drawing.Color]::FromArgb(75, 75, 75)
    }
}

if (-not ([System.Management.Automation.PSTypeName]'SlotPaste.NativeHotkeyWindow').Type) {
    Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace SlotPaste {
    public static class TaskbarIdentity {
        public const string AppId = "SlotPaste.Desktop";

        public static void Initialize() {
            Marshal.ThrowExceptionForHR(SetCurrentProcessExplicitAppUserModelID(AppId));
        }

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
    }

    public sealed class HotkeyEventArgs : EventArgs {
        public int Id { get; private set; }
        public HotkeyEventArgs(int id) { Id = id; }
    }

    public sealed class NativeHotkeyWindow : NativeWindow, IDisposable {
        private bool disposed;

        public event EventHandler<HotkeyEventArgs> HotkeyPressed;

        public NativeHotkeyWindow() {
            CreateHandle(new CreateParams());
        }

        public bool Register(int id, uint modifiers, uint virtualKey) {
            return RegisterHotKey(Handle, id, modifiers, virtualKey);
        }

        public bool Unregister(int id) {
            return UnregisterHotKey(Handle, id);
        }

        protected override void WndProc(ref Message message) {
            if (message.Msg == 0x0312) {
                EventHandler<HotkeyEventArgs> handler = HotkeyPressed;
                if (handler != null) {
                    handler(this, new HotkeyEventArgs(message.WParam.ToInt32()));
                }
            }
            base.WndProc(ref message);
        }

        public void Dispose() {
            if (disposed) return;
            disposed = true;
            DestroyHandle();
            GC.SuppressFinalize(this);
        }

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    }

    public sealed class RoundedButton : Button {
        public Color HoverBackColor { get; set; }
        public Color PressedBackColor { get; set; }
        private bool hovered;
        private bool pressed;

        public RoundedButton() {
            SetStyle(
                ControlStyles.UserPaint |
                ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.ResizeRedraw,
                true);
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            TabStop = true;
            HoverBackColor = Color.Empty;
            PressedBackColor = Color.Empty;
        }

        protected override void OnPaint(PaintEventArgs e) {
            Color surfaceColor = Parent != null ? Parent.BackColor : Color.White;
            e.Graphics.Clear(surfaceColor);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            e.Graphics.CompositingQuality = System.Drawing.Drawing2D.CompositingQuality.HighQuality;
            e.Graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;

            Rectangle bounds = new Rectangle(0, 0, Math.Max(1, Width - 1), Math.Max(1, Height - 1));
            int diameter = Math.Min(56, Math.Min(bounds.Width, bounds.Height));
            using (GraphicsPath path = CreateRoundedPath(bounds, diameter))
            using (SolidBrush brush = new SolidBrush(GetFillColor())) {
                e.Graphics.FillPath(brush, path);
            }

            TextFormatFlags flags = TextFormatFlags.HorizontalCenter |
                                    TextFormatFlags.VerticalCenter |
                                    TextFormatFlags.EndEllipsis |
                                    TextFormatFlags.NoPadding;
            TextRenderer.DrawText(e.Graphics, Text, Font, bounds, ForeColor, flags);
        }

        protected override void OnMouseEnter(EventArgs e) {
            hovered = true;
            Invalidate();
            base.OnMouseEnter(e);
        }

        protected override void OnMouseLeave(EventArgs e) {
            hovered = false;
            pressed = false;
            Invalidate();
            base.OnMouseLeave(e);
        }

        protected override void OnMouseDown(MouseEventArgs e) {
            pressed = true;
            Invalidate();
            base.OnMouseDown(e);
        }

        protected override void OnMouseUp(MouseEventArgs e) {
            pressed = false;
            Invalidate();
            base.OnMouseUp(e);
        }

        protected override void OnEnabledChanged(EventArgs e) {
            Invalidate();
            base.OnEnabledChanged(e);
        }

        private Color GetFillColor() {
            if (!Enabled) return ControlPaint.Light(BackColor);
            if (pressed && !PressedBackColor.IsEmpty) return PressedBackColor;
            if (hovered && !HoverBackColor.IsEmpty) return HoverBackColor;
            return BackColor;
        }

        private static GraphicsPath CreateRoundedPath(Rectangle bounds, int diameter) {
            int right = bounds.Right - diameter;
            int bottom = bounds.Bottom - diameter;
            GraphicsPath path = new GraphicsPath();
            path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
            path.AddArc(right, bounds.Top, diameter, diameter, 270, 90);
            path.AddArc(right, bottom, diameter, diameter, 0, 90);
            path.AddArc(bounds.Left, bottom, diameter, diameter, 90, 90);
            path.CloseFigure();
            return path;
        }
    }
}
'@ -ReferencedAssemblies @('System.Windows.Forms.dll', 'System.Drawing.dll')
}

function New-DefaultSlot {
    param([int]$Id)

    $numberKey = [int]([System.Windows.Forms.Keys]::D0 + $Id)
    return [pscustomobject]@{
        Id                = $Id
        Name              = "Slot $Id"
        Kind              = 'Empty'
        Value             = ''
        ShortcutModifiers = ($script:ModControl -bor $script:ModAlt)
        ShortcutKey       = $numberKey
    }
}

function ConvertTo-SlotObject {
    param($RawSlot, [int]$Id)

    $default = New-DefaultSlot -Id $Id
    if ($null -eq $RawSlot) {
        return $default
    }

    $name = if ($null -ne $RawSlot.Name -and "$($RawSlot.Name)".Trim()) { "$($RawSlot.Name)" } else { $default.Name }
    $kind = if ($null -ne $RawSlot.Kind) { "$($RawSlot.Kind)" } else { 'Empty' }
    if ($kind -notin @('Empty', 'Text', 'Image', 'File')) { $kind = 'Empty' }
    $value = if ($null -ne $RawSlot.Value) { "$($RawSlot.Value)" } else { '' }

    $modifiers = $default.ShortcutModifiers
    $key = $default.ShortcutKey
    try { if ($null -ne $RawSlot.ShortcutModifiers) { $modifiers = [int]$RawSlot.ShortcutModifiers } } catch { }
    try { if ($null -ne $RawSlot.ShortcutKey) { $key = [int]$RawSlot.ShortcutKey } } catch { }

    return [pscustomobject]@{
        Id                = $Id
        Name              = $name
        Kind              = $kind
        Value             = $value
        ShortcutModifiers = $modifiers
        ShortcutKey       = $key
    }
}

function Protect-ConfigurationJson {
    param([Parameter(Mandatory = $true)][string]$Json)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Json)
    try {
        $protectedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
            $bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        return ([pscustomobject]@{
            Format = 'SlotPaste.DPAPI'
            Version = 1
            Scope = 'CurrentUser'
            Payload = [Convert]::ToBase64String($protectedBytes)
        } | ConvertTo-Json -Depth 4)
    } finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Unprotect-ConfigurationJson {
    param([Parameter(Mandatory = $true)]$Envelope)

    if ($Envelope.Format -ne 'SlotPaste.DPAPI' -or $Envelope.Version -ne 1 -or $Envelope.Scope -ne 'CurrentUser') {
        throw 'Unbekanntes Verschlüsselungsformat.'
    }
    $protectedBytes = [Convert]::FromBase64String([string]$Envelope.Payload)
    $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $protectedBytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    try {
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    } finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Write-ProtectedConfigurationFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Json
    )

    # Verschlüsseln, bevor eine Datei angelegt wird. Auch temporäre Dateien
    # enthalten ausschließlich verschlüsselte Daten; kein Klartext-Backup.
    $encryptedJson = Protect-ConfigurationJson -Json $Json
    $temporaryPath = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($temporaryPath, $encryptedJson, $utf8)
        if ([System.IO.File]::Exists($Path)) {
            [System.IO.File]::Replace($temporaryPath, $Path, [System.Management.Automation.Language.NullString]::Value)
        } else {
            [System.IO.File]::Move($temporaryPath, $Path)
        }
    } finally {
        if ([System.IO.File]::Exists($temporaryPath)) {
            [System.IO.File]::Delete($temporaryPath)
        }
    }
}

function Protect-LegacyConfigurationFiles {
    # Frühere Versionen konnten Klartext-Backups und eine temporäre Datei
    # hinterlassen. Diese ebenfalls verschlüsseln, ohne ihren Inhalt zu löschen.
    $legacyPaths = @([System.IO.Directory]::GetFiles($script:DataDirectory, 'slots.json.corrupt-*.bak'))
    $legacyTemporaryPath = "$($script:ConfigPath).tmp"
    if ([System.IO.File]::Exists($legacyTemporaryPath)) { $legacyPaths += $legacyTemporaryPath }
    foreach ($path in $legacyPaths) {
        $json = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        $alreadyProtected = $false
        try {
            $parsed = $json | ConvertFrom-Json
            $properties = @($parsed.PSObject.Properties | ForEach-Object { $_.Name })
            $alreadyProtected = ($properties -contains 'Format' -and $parsed.Format -eq 'SlotPaste.DPAPI')
        } catch { }
        if (-not $alreadyProtected -and -not [string]::IsNullOrEmpty($json)) {
            Write-ProtectedConfigurationFile -Path $path -Json $json
        }
    }
}

function Save-Configuration {
    if (-not $script:ConfigurationLoaded) {
        throw 'Die Konfiguration wurde nicht erfolgreich geladen und darf nicht überschrieben werden.'
    }
    $slotArray = New-Object object[] $script:SlotCount
    for ($index = 0; $index -lt $script:SlotCount; $index++) {
        $slotArray[$index] = $script:Slots[$index]
    }
    # In Windows PowerShell muss ein Array über die Pipeline serialisiert
    # werden. Andernfalls entsteht ein Objekt mit den Feldern "value" und
    # "Count", das beim nächsten Start nicht als Slot-Liste geladen wird.
    $json = $slotArray | ConvertTo-Json -Depth 4
    Write-ProtectedConfigurationFile -Path $script:ConfigPath -Json $json
}

function Test-ConfigurationCorrupt {
    param([object[]]$Items)

    if ($null -eq $Items -or $Items.Count -ne $script:SlotCount) { return $false }
    $firstName = [string]$Items[0].Name
    $firstValue = [string]$Items[0].Value
    if ($firstName.Length -lt 4096 -or $firstValue.Length -lt 4096) { return $false }

    for ($index = 1; $index -lt $Items.Count; $index++) {
        if ([string]$Items[$index].Name -ne $firstName -or [string]$Items[$index].Value -ne $firstValue) {
            return $false
        }
    }
    return $true
}

function Load-Configuration {
    $script:ConfigurationLoaded = $false
    $raw = @()
    $recovered = $false
    $legacy = $false
    if ([System.IO.File]::Exists($script:ConfigPath)) {
        try {
            $json = [System.IO.File]::ReadAllText($script:ConfigPath, [System.Text.Encoding]::UTF8)
            $parsedConfiguration = $json | ConvertFrom-Json
            $propertyNames = @($parsedConfiguration.PSObject.Properties | ForEach-Object { $_.Name })
            if ($propertyNames -contains 'Format') {
                $json = Unprotect-ConfigurationJson -Envelope $parsedConfiguration
                $parsedConfiguration = $json | ConvertFrom-Json
            } else {
                $legacy = $true
            }
            $propertyNames = @($parsedConfiguration.PSObject.Properties | ForEach-Object { $_.Name })
            if ($propertyNames -contains 'value' -and $propertyNames -contains 'Count') {
                $parsedConfiguration = $parsedConfiguration.value
            }
            if ($null -eq $parsedConfiguration -or $parsedConfiguration -isnot [Array]) {
                throw 'Die gespeicherte Slot-Liste ist ungültig.'
            }
            foreach ($entry in $parsedConfiguration) {
                $raw += $entry
            }
            if (Test-ConfigurationCorrupt -Items $raw) {
                $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                $backupPath = "$($script:ConfigPath).corrupt-$stamp.bak"
                Write-ProtectedConfigurationFile -Path $backupPath -Json $json
                $script:ConfigurationNotice = "Eine beschädigte alte Konfiguration wurde gesichert: $backupPath"
                $raw = @()
                $recovered = $true
            }
        } catch {
            $message = "Die Slot-Datei konnte nicht gelesen oder mit deinem Windows-Benutzerkonto entschlüsselt werden: $($script:ConfigPath). Die vorhandene Datei bleibt erhalten."
            throw (New-Object System.InvalidOperationException($message, $_.Exception))
        }
    }

    $result = New-Object object[] $script:SlotCount
    for ($id = 1; $id -le $script:SlotCount; $id++) {
        $rawSlot = $null
        foreach ($candidate in $raw) {
            if ($null -ne $candidate -and [int]$candidate.Id -eq $id) {
                $rawSlot = $candidate
                break
            }
        }
        $result[$id - 1] = ConvertTo-SlotObject -RawSlot $rawSlot -Id $id
    }
    $script:Slots = $result
    Protect-LegacyConfigurationFiles
    if ($legacy -or $recovered -or -not [System.IO.File]::Exists($script:ConfigPath)) {
        # Erst nach erfolgreicher Migration dürfen spätere Speicheraufrufe
        # (auch beim Beenden) die vorhandene Datei ersetzen.
        $json = $result | ConvertTo-Json -Depth 4
        Write-ProtectedConfigurationFile -Path $script:ConfigPath -Json $json
    }
    $script:ConfigurationLoaded = $true
}

function Get-Slot {
    param([int]$Id)
    foreach ($slot in $script:Slots) {
        if ($null -ne $slot -and [int]$slot.Id -eq $Id) {
            return $slot
        }
    }
    return $null
}

function Get-KeyName {
    param([int]$KeyCode)

    $name = ([System.Windows.Forms.Keys]$KeyCode).ToString()
    switch ($name) {
        'D0' { return '0' }
        'D1' { return '1' }
        'D2' { return '2' }
        'D3' { return '3' }
        'D4' { return '4' }
        'D5' { return '5' }
        'D6' { return '6' }
        'D7' { return '7' }
        'D8' { return '8' }
        'D9' { return '9' }
        'Oemcomma' { return ',' }
        'OemPeriod' { return '.' }
        'OemMinus' { return '-' }
        'Oemplus' { return '+' }
        default { return $name }
    }
}

function Get-ShortcutText {
    param([int]$Modifiers, [int]$KeyCode)

    if ($KeyCode -le 0) { return 'Nicht gesetzt' }
    $parts = New-Object System.Collections.Generic.List[string]
    if (($Modifiers -band $script:ModControl) -ne 0) { [void]$parts.Add('Strg') }
    if (($Modifiers -band $script:ModAlt) -ne 0) { [void]$parts.Add('Alt') }
    if (($Modifiers -band $script:ModShift) -ne 0) { [void]$parts.Add('Umschalt') }
    if (($Modifiers -band $script:ModWin) -ne 0) { [void]$parts.Add('Win') }
    [void]$parts.Add((Get-KeyName -KeyCode $KeyCode))
    return ($parts -join ' + ')
}

function Show-Message {
    param([string]$Text, [string]$Title = $script:AppName, [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information)
    [void][System.Windows.Forms.MessageBox]::Show($Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $Icon)
}

function Show-Balloon {
    param([string]$Text, [string]$Title = $script:AppName, [System.Windows.Forms.ToolTipIcon]$Icon = [System.Windows.Forms.ToolTipIcon]::Info)
    if ($null -ne $script:TrayIcon) {
        $script:TrayIcon.BalloonTipTitle = $Title
        $script:TrayIcon.BalloonTipText = $Text
        $script:TrayIcon.BalloonTipIcon = $Icon
        $script:TrayIcon.ShowBalloonTip(2500)
    }
}

function Get-StartupCommand {
    $launcher = $env:SLOT_PASTE_LAUNCHER
    if (-not [string]::IsNullOrWhiteSpace($launcher) -and [System.IO.File]::Exists($launcher)) {
        return ('"{0}"' -f $launcher)
    }

    $powershell = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    if (-not $powershell) { $powershell = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source }
    if (-not $powershell) { throw 'Keine PowerShell-Ausführungsdatei gefunden.' }
    return ('"{0}" -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}"' -f $powershell, $PSCommandPath)
}

function Get-SlotPasteIcon {
    try {
        $localIcon = Join-Path $PSScriptRoot 'SlotPaste.ico'
        if ([System.IO.File]::Exists($localIcon)) {
            return New-Object System.Drawing.Icon($localIcon)
        }

        $launcher = $env:SLOT_PASTE_LAUNCHER
        if (-not [string]::IsNullOrWhiteSpace($launcher) -and [System.IO.File]::Exists($launcher)) {
            return [System.Drawing.Icon]::ExtractAssociatedIcon($launcher)
        }
    } catch { }
    return [System.Drawing.SystemIcons]::Application
}

function Get-AutostartEnabled {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:StartupSubKey, $false)
    if ($null -eq $key) { return $false }
    try { return ($null -ne $key.GetValue($script:StartupValueName, $null)) } finally { $key.Dispose() }
}

function Set-Autostart {
    param([bool]$Enabled)

    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($script:StartupSubKey)
    try {
        if ($Enabled) {
            $key.SetValue($script:StartupValueName, (Get-StartupCommand), [Microsoft.Win32.RegistryValueKind]::String)
        } else {
            $key.DeleteValue($script:StartupValueName, $false)
        }
    } finally {
        $key.Dispose()
    }
}

function Get-PreviewText {
    param($Slot)

    if ($Slot.Kind -eq 'Empty') { return 'Leer' }
    if ($Slot.Kind -eq 'Text') {
        $text = $Slot.Value -replace '\s+', ' '
        if ($text.Length -gt 58) { $text = $text.Substring(0, 58) + '...' }
        return $text
    }
    if ([string]::IsNullOrWhiteSpace($Slot.Value)) { return 'Kein Pfad gespeichert' }
    $exists = [System.IO.File]::Exists($Slot.Value)
    $prefix = if ($exists) { '' } else { 'Nicht gefunden: ' }
    return $prefix + [System.IO.Path]::GetFileName($Slot.Value)
}

function Update-EditorRow {
    param($Slot)

    if (-not $script:RowUi.ContainsKey($Slot.Id)) { return }
    $ui = $script:RowUi[$Slot.Id]
    $ui.TypeLabel.Text = switch ($Slot.Kind) {
        'Text' { 'Text' }
        'Image' { 'Bild' }
        'File' { 'Datei' }
        default { 'Leer' }
    }
    $ui.PreviewLabel.Text = Get-PreviewText -Slot $Slot
    $ui.ShortcutButton.Text = Get-ShortcutText -Modifiers $Slot.ShortcutModifiers -KeyCode $Slot.ShortcutKey
}

function Update-Editor {
    foreach ($slot in $script:Slots) {
        Update-EditorRow -Slot $slot
    }
}

function Sync-EditorFields {
    # Ein zuletzt bearbeitetes Namensfeld kann beim Beenden noch den Fokus
    # haben. Deshalb wird der sichtbare Text vor jedem Speichern übernommen.
    foreach ($slot in $script:Slots) {
        if (-not $script:RowUi.ContainsKey($slot.Id)) { continue }
        $nameBox = $script:RowUi[$slot.Id].NameBox
        if ($null -eq $nameBox -or $nameBox -isnot [System.Windows.Forms.TextBox] -or $nameBox.IsDisposed) { continue }
        $name = "$($nameBox.Text)".Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { $name = "Slot $($slot.Id)" }
        $slot.Name = $name
    }
}

function Save-ImageToSlot {
    param($Slot, [System.Drawing.Image]$Image, [string]$Extension = '.png')

    if ($null -eq $Image) { return $false }
    $target = Join-Path $script:AssetsDirectory ("slot-{0}{1}" -f $Slot.Id, $Extension)
    try {
        $Image.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
        $Slot.Kind = 'Image'
        $Slot.Value = $target
        return $true
    } catch {
        Show-Message -Text ("Das Bild konnte nicht gespeichert werden:`n{0}" -f $_.Exception.Message) -Icon Error
        return $false
    } finally {
        $Image.Dispose()
    }
}

function Set-SlotFromClipboard {
    param($Slot)

    try {
        $data = [System.Windows.Forms.Clipboard]::GetDataObject()
        if ($null -eq $data) { throw 'Die Zwischenablage ist leer.' }

        if ($data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
            $files = [System.Windows.Forms.Clipboard]::GetFileDropList()
            if ($files.Count -gt 0) {
                $Slot.Kind = 'File'
                $Slot.Value = $files[0]
            }
        } elseif ($data.GetDataPresent([System.Windows.Forms.DataFormats]::Bitmap)) {
            if (-not (Save-ImageToSlot -Slot $Slot -Image ([System.Windows.Forms.Clipboard]::GetImage()))) { return }
        } elseif ([System.Windows.Forms.Clipboard]::ContainsText()) {
            $Slot.Kind = 'Text'
            $Slot.Value = [System.Windows.Forms.Clipboard]::GetText()
        } else {
            throw 'Dieser Zwischenablage-Inhalt wird nicht unterstützt.'
        }

        if ($Slot.Name -eq "Slot $($Slot.Id)") {
            $Slot.Name = switch ($Slot.Kind) { 'Text' { 'Text' } 'Image' { 'Bild' } 'File' { [System.IO.Path]::GetFileName($Slot.Value) } default { $Slot.Name } }
        }
        Save-Configuration
        Update-Editor
    } catch {
        Show-Message -Text ("Der Slot konnte nicht aus der Zwischenablage befüllt werden:`n{0}" -f $_.Exception.Message) -Icon Error
    }
}

function Set-SlotFromFile {
    param($Slot)

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = 'Bild, Video oder andere Datei auswählen'
    $dialog.Filter = 'Unterstützte Dateien|*.png;*.jpg;*.jpeg;*.gif;*.bmp;*.webp;*.mp4;*.mov;*.avi;*.mkv;*.webm|Alle Dateien|*.*'
    $dialog.Multiselect = $false
    try {
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $source = $dialog.FileName
        $extension = [System.IO.Path]::GetExtension($source).ToLowerInvariant()
        if ($extension -in @('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp')) {
            $target = Join-Path $script:AssetsDirectory ("slot-{0}{1}" -f $Slot.Id, $extension)
            [System.IO.File]::Copy($source, $target, $true)
            $Slot.Kind = 'Image'
            $Slot.Value = $target
        } else {
            $Slot.Kind = 'File'
            $Slot.Value = $source
        }
        if ($Slot.Name -eq "Slot $($Slot.Id)") { $Slot.Name = [System.IO.Path]::GetFileName($source) }
        Save-Configuration
        Update-Editor
    } finally {
        $dialog.Dispose()
    }
}

function Show-TextEditor {
    param($Slot)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Text für Slot $($Slot.Id)"
    $form.StartPosition = 'CenterParent'
    $form.Size = New-Object System.Drawing.Size(620, 390)
    $form.MinimumSize = New-Object System.Drawing.Size(480, 300)
    $form.ShowInTaskbar = $false
    $form.BackColor = [System.Drawing.Color]::White
    $form.ForeColor = [System.Drawing.Color]::Black
    $form.Font = New-UiFont -Size 10

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Multiline = $true
    $textBox.ScrollBars = 'Vertical'
    $textBox.AcceptsReturn = $true
    $textBox.AcceptsTab = $true
    $textBox.Dock = 'Fill'
    $textBox.BackColor = [System.Drawing.Color]::White
    $textBox.ForeColor = [System.Drawing.Color]::Black
    $textBox.Font = New-UiFont -Size 11
    $textBox.Text = if ($Slot.Kind -eq 'Text') { $Slot.Value } else { '' }

    $buttons = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttons.Dock = 'Bottom'
    $buttons.Height = 45
    $buttons.FlowDirection = 'RightToLeft'
    $buttons.Padding = New-Object System.Windows.Forms.Padding(8)
    $buttons.BackColor = [System.Drawing.Color]::White

    $save = New-Object SlotPaste.RoundedButton
    $save.Text = 'Speichern'
    $save.Width = 100
    $save.DialogResult = [System.Windows.Forms.DialogResult]::OK
    Style-RoundedButton -Button $save
    $cancel = New-Object SlotPaste.RoundedButton
    $cancel.Text = 'Abbrechen'
    $cancel.Width = 100
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    Style-RoundedButton -Button $cancel
    [void]$buttons.Controls.Add($save)
    [void]$buttons.Controls.Add($cancel)
    [void]$form.Controls.Add($textBox)
    [void]$form.Controls.Add($buttons)
    $form.AcceptButton = $save
    $form.CancelButton = $cancel

    try {
        if ($form.ShowDialog($script:EditorForm) -eq [System.Windows.Forms.DialogResult]::OK) {
            if ([string]::IsNullOrEmpty($textBox.Text)) {
                $Slot.Kind = 'Empty'
                $Slot.Value = ''
            } else {
                $Slot.Kind = 'Text'
                $Slot.Value = $textBox.Text
            }
            Save-Configuration
            Update-Editor
        }
    } finally {
        $form.Dispose()
    }
}

function Show-ShortcutEditor {
    param($Slot)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Tastenkombination für Slot $($Slot.Id)"
    $form.StartPosition = 'CenterParent'
    $form.Size = New-Object System.Drawing.Size(440, 205)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ShowInTaskbar = $false
    $form.KeyPreview = $true
    $form.BackColor = [System.Drawing.Color]::White
    $form.ForeColor = [System.Drawing.Color]::Black
    $form.Font = New-UiFont -Size 10

    $label = New-Object System.Windows.Forms.Label
    $label.Text = 'Klicke in das Feld und drücke die gewünschte Tastenkombination:'
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point(16, 18)
    $box = New-Object System.Windows.Forms.TextBox
    $box.ReadOnly = $true
    $box.TabStop = $false
    $box.Width = 390
    $box.Location = New-Object System.Drawing.Point(16, 50)
    $box.Text = Get-ShortcutText -Modifiers $Slot.ShortcutModifiers -KeyCode $Slot.ShortcutKey
    $box.BackColor = [System.Drawing.Color]::White
    $box.ForeColor = [System.Drawing.Color]::Black
    $box.Font = New-UiFont -Size 11
    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = 'Mindestens eine Zusatztaste (Strg, Alt, Umschalt oder Win) ist erforderlich.'
    $hint.AutoSize = $true
    $hint.Location = New-Object System.Drawing.Point(16, 82)
    $hint.ForeColor = [System.Drawing.Color]::Black

    $ok = New-Object SlotPaste.RoundedButton
    $ok.Text = 'Übernehmen'
    $ok.Width = 110
    $ok.Location = New-Object System.Drawing.Point(180, 120)
    Style-RoundedButton -Button $ok
    $cancel = New-Object SlotPaste.RoundedButton
    $cancel.Text = 'Abbrechen'
    $cancel.Width = 100
    $cancel.Location = New-Object System.Drawing.Point(300, 120)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    Style-RoundedButton -Button $cancel
    [void]$form.Controls.AddRange(@($label, $box, $hint, $ok, $cancel))
    $form.CancelButton = $cancel

    $captured = @{ Modifiers = $null; Key = $null }
    $form.Add_KeyDown({
        param($sender, $event)
        $key = [int]$event.KeyCode
        if ($key -in @([int][System.Windows.Forms.Keys]::ControlKey, [int][System.Windows.Forms.Keys]::ShiftKey, [int][System.Windows.Forms.Keys]::Menu, [int][System.Windows.Forms.Keys]::LWin, [int][System.Windows.Forms.Keys]::RWin)) { return }
        $mods = 0
        if ($event.Control) { $mods = $mods -bor $script:ModControl }
        if ($event.Alt) { $mods = $mods -bor $script:ModAlt }
        if ($event.Shift) { $mods = $mods -bor $script:ModShift }
        if ($event.KeyCode -eq [System.Windows.Forms.Keys]::LWin -or $event.KeyCode -eq [System.Windows.Forms.Keys]::RWin) { $mods = $mods -bor $script:ModWin }
        if ($mods -eq 0) {
            $box.Text = 'Bitte Zusatztaste verwenden'
            $captured.Modifiers = $null
            $captured.Key = $null
        } else {
            $captured.Modifiers = $mods
            $captured.Key = $key
            $box.Text = Get-ShortcutText -Modifiers $mods -KeyCode $key
        }
        $event.SuppressKeyPress = $true
        $event.Handled = $true
    })
    $ok.Add_Click({
        if ($null -eq $captured.Key) {
            Show-Message -Text 'Bitte zuerst eine Tastenkombination drücken.' -Title 'Tastenkombination'
            return
        }
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })

    $result = $null
    try {
        if ($form.ShowDialog($script:EditorForm) -eq [System.Windows.Forms.DialogResult]::OK) {
            $result = [pscustomobject]@{ Modifiers = [int]$captured.Modifiers; Key = [int]$captured.Key }
        }
    } finally {
        $form.Dispose()
    }
    return $result
}

function Register-AllHotkeys {
    $failed = New-Object System.Collections.Generic.List[string]
    foreach ($slot in $script:Slots) {
        [void]$script:HotkeyWindow.Unregister($slot.Id)
    }
    foreach ($slot in $script:Slots) {
        if ($slot.ShortcutKey -le 0) { continue }
        $registered = $script:HotkeyWindow.Register($slot.Id, [uint32]$slot.ShortcutModifiers, [uint32]$slot.ShortcutKey)
        if (-not $registered) { [void]$failed.Add(("Slot {0}: {1}" -f $slot.Id, (Get-ShortcutText -Modifiers $slot.ShortcutModifiers -KeyCode $slot.ShortcutKey))) }
    }
    if ($failed.Count -gt 0) {
        Show-Balloon -Text ("Diese Tastenkombination(en) konnten nicht registriert werden:`n" + ($failed -join ', ')) -Title 'Tastenkombination belegt' -Icon Warning
    }
}

function Invoke-Slot {
    param($Slot)

    if ($Slot.Kind -eq 'Empty') {
        Show-Balloon -Text "Slot $($Slot.Id) ist noch leer. Öffne SlotPaste, um ihn zu befüllen." -Title 'SlotPaste'
        return
    }

    try {
        switch ($Slot.Kind) {
            'Text' {
                [System.Windows.Forms.Clipboard]::SetText($Slot.Value, [System.Windows.Forms.TextDataFormat]::UnicodeText)
            }
            'Image' {
                if (-not [System.IO.File]::Exists($Slot.Value)) { throw "Bilddatei nicht gefunden: $($Slot.Value)" }
                $image = New-Object System.Drawing.Bitmap($Slot.Value)
                try { [System.Windows.Forms.Clipboard]::SetImage($image) } finally { $image.Dispose() }
            }
            'File' {
                if (-not [System.IO.File]::Exists($Slot.Value)) { throw "Datei nicht gefunden: $($Slot.Value)" }
                $files = New-Object System.Collections.Specialized.StringCollection
                [void]$files.Add($Slot.Value)
                [System.Windows.Forms.Clipboard]::SetFileDropList($files)
            }
            default { throw 'Unbekannter Slot-Typ.' }
        }

        Show-Balloon -Text "Slot $($Slot.Id) wurde in die Zwischenablage kopiert. Mit Strg + V einfügen." -Title 'SlotPaste'
    } catch {
        Show-Balloon -Text $_.Exception.Message -Title 'Kopieren fehlgeschlagen' -Icon Error
    }
}

function Clear-Slot {
    param($Slot)
    $confirmation = [System.Windows.Forms.MessageBox]::Show(
        ("Möchtest du Slot {0} wirklich leeren?" -f $Slot.Id),
        'Slot leeren',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($confirmation -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    $Slot.Kind = 'Empty'
    $Slot.Value = ''
    Save-Configuration
    Update-Editor
}

function New-EditorForm {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'SlotPaste'
    $form.Icon = Get-SlotPasteIcon
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(1120, 640)
    $form.MinimumSize = New-Object System.Drawing.Size(980, 560)
    $form.FormBorderStyle = 'Sizable'
    $form.ShowInTaskbar = $true
    $form.BackColor = [System.Drawing.Color]::White
    $form.ForeColor = [System.Drawing.Color]::Black
    $form.Font = New-UiFont -Size 10

    $header = New-Object System.Windows.Forms.Label
    $header.Text = 'SlotPaste – wiederverwendbare Texte, Bilder und Dateien'
    $header.ForeColor = [System.Drawing.Color]::Black
    $header.Font = New-UiFont -Size 14 -Style ([System.Drawing.FontStyle]::Bold)
    $header.AutoSize = $true
    $header.Location = New-Object System.Drawing.Point(18, 14)

    $description = New-Object System.Windows.Forms.Label
    $description.Text = 'Speichere einen Inhalt im Slot und füge ihn später mit der angezeigten globalen Tastenkombination in das aktive Fenster ein.'
    $description.AutoSize = $true
    $description.Location = New-Object System.Drawing.Point(20, 45)
    $description.ForeColor = [System.Drawing.Color]::Black

    $table = New-Object System.Windows.Forms.TableLayoutPanel
    $table.Location = New-Object System.Drawing.Point(18, 78)
    $table.Anchor = 'Top,Bottom,Left,Right'
    $table.Size = New-Object System.Drawing.Size(1065, 460)
    $table.ColumnCount = 8
    $table.RowCount = $script:SlotCount + 1
    $table.CellBorderStyle = 'None'
    $table.BackColor = [System.Drawing.Color]::White
    $table.Padding = New-Object System.Windows.Forms.Padding(0)
    # Prozentbreiten verhindern, dass beim Maximieren die letzte Spalte den
    # gesamten übrigen Platz übernimmt und die Leeren-Buttons verzerrt.
    $columnWidths = @(6, 16, 6, 18, 25, 9, 10, 10)
    for ($i = 0; $i -lt $columnWidths.Count; $i++) { $table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, $columnWidths[$i]))) }
    $table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42)))
    for ($i = 1; $i -le $script:SlotCount; $i++) { $table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 46))) }

    $headers = @('Slot', 'Name', 'Typ', 'Tastenkombination', 'Vorschau / Pfad', 'Text', 'Bild/Datei', 'Leeren')
    for ($i = 0; $i -lt $headers.Count; $i++) {
        $h = New-Object System.Windows.Forms.Label
        $h.Text = $headers[$i]
        $h.Dock = 'Fill'
        $h.TextAlign = 'MiddleCenter'
        $h.ForeColor = [System.Drawing.Color]::Black
        $h.Font = New-UiFont -Size 10 -Style ([System.Drawing.FontStyle]::Bold)
        [void]$table.Controls.Add($h, $i, 0)
    }

    $script:RowUi = @{}
    foreach ($slot in $script:Slots) {
        $row = $slot.Id
        $slotLabel = New-Object System.Windows.Forms.Label
        $slotLabel.Text = "#$($slot.Id)"
        $slotLabel.Dock = 'Fill'
        $slotLabel.TextAlign = 'MiddleCenter'
        $slotLabel.ForeColor = [System.Drawing.Color]::Black

        $nameBox = New-Object System.Windows.Forms.TextBox
        $nameBox.Dock = 'Fill'
        $nameBox.Margin = New-Object System.Windows.Forms.Padding(5, 10, 5, 8)
        $nameBox.Text = $slot.Name
        $nameBox.BackColor = [System.Drawing.Color]::White
        $nameBox.ForeColor = [System.Drawing.Color]::Black
        $nameBox.Font = New-UiFont -Size 10
        $nameBox.Add_Leave({
            param($sender, $event)
            $target = $sender.Tag
            if ([string]::IsNullOrWhiteSpace($sender.Text)) { $sender.Text = "Slot $($target.Id)" }
            $target.Name = $sender.Text.Trim()
            Save-Configuration
        })
        $nameBox.Tag = $slot

        $typeLabel = New-Object System.Windows.Forms.Label
        $typeLabel.Dock = 'Fill'
        $typeLabel.TextAlign = 'MiddleCenter'

        $shortcutButton = New-Object SlotPaste.RoundedButton
        $shortcutButton.Dock = 'Fill'
        $shortcutButton.Margin = New-Object System.Windows.Forms.Padding(4, 8, 4, 8)
        $shortcutButton.Tag = $slot
        Style-RoundedButton -Button $shortcutButton
        $shortcutButton.Add_Click({
            param($sender, $event)
            $target = $sender.Tag
            $result = Show-ShortcutEditor -Slot $target
            if ($null -ne $result) {
                $target.ShortcutModifiers = $result.Modifiers
                $target.ShortcutKey = $result.Key
                Save-Configuration
                Register-AllHotkeys
                Update-Editor
            }
        })

        $previewLabel = New-Object System.Windows.Forms.Label
        $previewLabel.Dock = 'Fill'
        $previewLabel.TextAlign = 'MiddleLeft'
        $previewLabel.AutoEllipsis = $true
        $previewLabel.Padding = New-Object System.Windows.Forms.Padding(6, 0, 4, 0)
        $previewLabel.ForeColor = [System.Drawing.Color]::Black

        $textButton = New-Object SlotPaste.RoundedButton
        $textButton.Text = 'Text'
        $textButton.Dock = 'Fill'
        $textButton.Margin = New-Object System.Windows.Forms.Padding(4, 8, 4, 8)
        $textButton.Tag = $slot
        Style-RoundedButton -Button $textButton
        $textButton.Add_Click({ param($sender, $event) Show-TextEditor -Slot $sender.Tag })

        $fileButton = New-Object SlotPaste.RoundedButton
        $fileButton.Text = 'Auswählen'
        $fileButton.Dock = 'Fill'
        $fileButton.Margin = New-Object System.Windows.Forms.Padding(4, 8, 4, 8)
        $fileButton.Tag = $slot
        Style-RoundedButton -Button $fileButton
        $fileButton.Add_Click({ param($sender, $event) Set-SlotFromFile -Slot $sender.Tag })

        $clearButton = New-Object SlotPaste.RoundedButton
        $clearButton.Text = '✕'
        $clearButton.Dock = 'Fill'
        $clearButton.Margin = New-Object System.Windows.Forms.Padding(15, 8, 15, 8)
        $clearButton.Tag = $slot
        Style-RoundedButton -Button $clearButton -Destructive
        $clearButton.Add_Click({ param($sender, $event) Clear-Slot -Slot $sender.Tag })

        [void]$table.Controls.Add($slotLabel, 0, $row)
        [void]$table.Controls.Add($nameBox, 1, $row)
        [void]$table.Controls.Add($typeLabel, 2, $row)
        [void]$table.Controls.Add($shortcutButton, 3, $row)
        [void]$table.Controls.Add($previewLabel, 4, $row)
        [void]$table.Controls.Add($textButton, 5, $row)
        [void]$table.Controls.Add($fileButton, 6, $row)
        [void]$table.Controls.Add($clearButton, 7, $row)
        $script:RowUi[$slot.Id] = @{ TypeLabel = $typeLabel; PreviewLabel = $previewLabel; ShortcutButton = $shortcutButton; NameBox = $nameBox }
    }

    $clipboardHint = New-Object System.Windows.Forms.Label
    $clipboardHint.Text = 'Tipp: Mit der rechten Maustaste auf das Tray-Symbol kannst du jeden Slot auch direkt aus der aktuellen Zwischenablage befüllen.'
    $clipboardHint.AutoSize = $true
    $clipboardHint.Location = New-Object System.Drawing.Point(20, 575)
    $clipboardHint.Anchor = 'Bottom,Left'
    $clipboardHint.ForeColor = [System.Drawing.Color]::Black

    $startup = New-Object System.Windows.Forms.CheckBox
    $startup.Text = 'Mit Windows starten'
    $startup.AutoSize = $true
    $startup.Location = New-Object System.Drawing.Point(930, 573)
    $startup.Anchor = 'Bottom,Right'
    $startup.Checked = Get-AutostartEnabled
    $startup.ForeColor = [System.Drawing.Color]::Black
    $startup.BackColor = [System.Drawing.Color]::White
    $startup.Add_CheckedChanged({
        param($sender, $event)
        try { Set-Autostart -Enabled $sender.Checked } catch { Show-Message -Text ("Autostart konnte nicht geändert werden:`n{0}" -f $_.Exception.Message) -Icon Error }
    })

    [void]$form.Controls.Add($header)
    [void]$form.Controls.Add($description)
    [void]$form.Controls.Add($table)
    [void]$form.Controls.Add($clipboardHint)
    [void]$form.Controls.Add($startup)
    $form.Add_FormClosing({
        param($sender, $event)
        if ($script:ConfigurationLoaded) { try { Save-Configuration } catch { } }
        if (-not $script:AllowClose) {
            $event.Cancel = $true
            $sender.Hide()
        }
    })

    $null = Update-Editor
    return $form
}

function Show-Editor {
    $editorIsValid = $false
    if ($null -ne $script:EditorForm -and $script:EditorForm -is [System.Windows.Forms.Form]) {
        $editorIsValid = -not $script:EditorForm.IsDisposed
    }

    if (-not $editorIsValid) {
        $newEditor = New-EditorForm
        if ($newEditor -is [System.Array]) {
            $newEditor = @($newEditor | Where-Object { $_ -is [System.Windows.Forms.Form] } | Select-Object -First 1)[0]
        }
        $script:EditorForm = $newEditor
    }
    $script:EditorForm.Show()
    $script:EditorForm.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $script:EditorForm.Activate()
}

function New-TrayMenu {
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $open = $menu.Items.Add('SlotPaste öffnen')
    $open.Font = New-Object System.Drawing.Font($open.Font, [System.Drawing.FontStyle]::Bold)
    $open.Add_Click({ Show-Editor })
    [void]$menu.Items.Add('-')

    $slotsMenu = $menu.Items.Add('Schnell einfügen')
    foreach ($slot in $script:Slots) {
        $item = $slotsMenu.DropDownItems.Add(("{0} – {1}  [{2}]" -f $slot.Id, $slot.Name, (Get-ShortcutText -Modifiers $slot.ShortcutModifiers -KeyCode $slot.ShortcutKey)))
        $item.Tag = $slot
        $item.Add_Click({ param($sender, $event) Invoke-Slot -Slot $sender.Tag })
    }
    [void]$menu.Items.Add('-')
    $fromClipboard = $menu.Items.Add('Aktuelle Zwischenablage auf Slot...')
    $fromClipboard.Add_Click({
        $choice = New-Object System.Windows.Forms.Form
        $choice.Text = 'Slot aus Zwischenablage befüllen'
        $choice.StartPosition = 'CenterScreen'
        $choice.Size = New-Object System.Drawing.Size(360, 160)
        $choice.FormBorderStyle = 'FixedDialog'
        $choice.MaximizeBox = $false
        $choice.MinimizeBox = $false
        $choice.BackColor = [System.Drawing.Color]::White
        $choice.ForeColor = [System.Drawing.Color]::Black
        $choice.Font = New-UiFont -Size 10
        $label = New-Object System.Windows.Forms.Label
        $label.Text = 'Slotnummer:'
        $label.AutoSize = $true
        $label.Location = New-Object System.Drawing.Point(24, 28)
        $label.ForeColor = [System.Drawing.Color]::Black
        $number = New-Object System.Windows.Forms.NumericUpDown
        $number.Minimum = 1
        $number.Maximum = $script:SlotCount
        $number.Value = 1
        $number.Location = New-Object System.Drawing.Point(110, 24)
        $number.BackColor = [System.Drawing.Color]::White
        $number.ForeColor = [System.Drawing.Color]::Black
        $ok = New-Object SlotPaste.RoundedButton
        $ok.Text = 'Befüllen'
        $ok.Location = New-Object System.Drawing.Point(110, 70)
        $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
        Style-RoundedButton -Button $ok
        $cancel = New-Object SlotPaste.RoundedButton
        $cancel.Text = 'Abbrechen'
        $cancel.Location = New-Object System.Drawing.Point(200, 70)
        $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        Style-RoundedButton -Button $cancel
        [void]$choice.Controls.AddRange(@($label, $number, $ok, $cancel))
        $choice.AcceptButton = $ok
        $choice.CancelButton = $cancel
        try {
            if ($choice.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Set-SlotFromClipboard -Slot (Get-Slot -Id ([int]$number.Value)) }
        } finally { $choice.Dispose() }
    })
    $toggle = $menu.Items.Add('Mit Windows starten')
    $toggle.Checked = Get-AutostartEnabled
    $toggle.Add_Click({
        try {
            Set-Autostart -Enabled (-not $toggle.Checked)
            $toggle.Checked = -not $toggle.Checked
        } catch { Show-Message -Text ("Autostart konnte nicht geändert werden:`n{0}" -f $_.Exception.Message) -Icon Error }
    })
    [void]$menu.Items.Add('-')
    $exit = $menu.Items.Add('Beenden')
    $exit.Add_Click({
        $script:AllowClose = $true
        [System.Windows.Forms.Application]::Exit()
    })
    return $menu
}

function Start-SlotPaste {
    # Eigene Taskleisten-Gruppe statt der Identität des PowerShell-Hosts verwenden.
    [SlotPaste.TaskbarIdentity]::Initialize()
    Load-Configuration

    $script:HotkeyWindow = New-Object SlotPaste.NativeHotkeyWindow
    $script:HotkeyWindow.add_HotkeyPressed({
        param($sender, $event)
        $slot = Get-Slot -Id $event.Id
        if ($null -ne $slot) { Invoke-Slot -Slot $slot }
    })

    $script:TrayIcon = New-Object System.Windows.Forms.NotifyIcon
    $script:TrayIcon.Icon = Get-SlotPasteIcon
    $script:TrayIcon.Text = 'SlotPaste'
    $script:TrayIcon.Visible = $true
    $script:TrayIcon.ContextMenuStrip = New-TrayMenu
    $script:TrayIcon.Add_DoubleClick({ Show-Editor })

    Register-AllHotkeys
    Show-Balloon -Text 'SlotPaste läuft. Standard: Strg + Alt + 1 bis 9.' -Title 'SlotPaste gestartet'
    if (-not [string]::IsNullOrWhiteSpace($script:ConfigurationNotice)) {
        Show-Balloon -Text $script:ConfigurationNotice -Title 'Konfiguration wiederhergestellt' -Icon Warning
    }
    [System.Windows.Forms.Application]::Run()
}

try {
    Start-SlotPaste
} catch {
    Show-Message -Text ("SlotPaste konnte nicht gestartet werden:`n{0}" -f $_.Exception.Message) -Icon Error
} finally {
    if ($script:ConfigurationLoaded) { try { Save-Configuration } catch { } }
    $script:AllowClose = $true
    if ($null -ne $script:HotkeyWindow) {
        foreach ($slot in $script:Slots) { [void]$script:HotkeyWindow.Unregister($slot.Id) }
        $script:HotkeyWindow.Dispose()
    }
    if ($null -ne $script:TrayIcon) {
        $script:TrayIcon.Visible = $false
        $script:TrayIcon.Dispose()
    }
    if ($null -ne $script:EditorForm -and $script:EditorForm -is [System.Windows.Forms.Form] -and -not $script:EditorForm.IsDisposed) { $script:EditorForm.Dispose() }
}
