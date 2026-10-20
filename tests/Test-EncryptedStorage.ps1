#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:PSModulePath = [System.IO.Path]::Combine($env:WINDIR, 'System32', 'WindowsPowerShell', 'v1.0', 'Modules')
Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.Windows.Forms

# Die echten Speicherfunktionen laden, ohne Tray, Autostart oder Nutzerdaten
# anzufassen. Mit Windows PowerShell 5.1 und der echten Windows-DPAPI testen.
$sourcePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'SlotPaste.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw 'SlotPaste.ps1 enthält Syntaxfehler.' }
$functionNames = @('New-DefaultSlot', 'ConvertTo-SlotObject', 'Protect-ConfigurationJson',
    'Unprotect-ConfigurationJson', 'Write-ProtectedConfigurationFile',
    'Protect-LegacyConfigurationFiles', 'Save-Configuration', 'Test-ConfigurationCorrupt', 'Load-Configuration')
foreach ($definition in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    if ($definition.Name -in $functionNames) { . ([scriptblock]::Create($definition.Extent.Text)) }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-LoadRejected {
    $before = [System.IO.File]::ReadAllBytes($script:ConfigPath)
    $rejected = $false
    try { Load-Configuration } catch { $rejected = $true }
    Assert-True $rejected 'Ungültige oder nicht entschlüsselbare Daten wurden akzeptiert.'
    Assert-True (-not $script:ConfigurationLoaded) 'Speichern blieb nach einem Ladefehler erlaubt.'
    $saveRejected = $false
    try { Save-Configuration } catch { $saveRejected = $true }
    Assert-True $saveRejected 'Speichern konnte ungelesene Daten überschreiben.'
    $after = [System.IO.File]::ReadAllBytes($script:ConfigPath)
    Assert-True ([Convert]::ToBase64String($before) -ceq [Convert]::ToBase64String($after)) 'Ein Ladefehler veränderte die vorhandene Datei.'
}

$script:SlotCount = 9
$script:ModControl = 2
$script:ModAlt = 1
$script:ConfigurationLoaded = $false
$script:ConfigurationNotice = $null
$script:DataDirectory = Join-Path $PSScriptRoot ('storage-' + [Guid]::NewGuid().ToString('N'))
$script:ConfigPath = Join-Path $script:DataDirectory 'slots.json'
[void][System.IO.Directory]::CreateDirectory($script:DataDirectory)
try {
    Load-Configuration
    Assert-True ($script:Slots.Count -eq 9) 'Neue Konfiguration hat nicht neun Slots.'
    $emptyEnvelope = [System.IO.File]::ReadAllText($script:ConfigPath) | ConvertFrom-Json
    Assert-True ($emptyEnvelope.Format -eq 'SlotPaste.DPAPI') 'Neue Konfiguration ist nicht verschlüsselt.'

    $text = "Geheimer Prüftext äöü ß 日本語 🚀`r`nZeile zwei`n" + ('x' * 20000)
    $script:Slots[0].Kind = 'Text'
    $script:Slots[0].Name = 'Vertraulicher Slotname'
    $script:Slots[0].Value = $text
    $script:Slots[0].ShortcutModifiers = 6
    $script:Slots[0].ShortcutKey = 75
    $script:Slots[1].Kind = 'File'
    $script:Slots[1].Value = 'C:\Privat\geheim.pdf'
    $script:Slots[2].Kind = 'Image'
    $script:Slots[2].Value = 'C:\Privat\bild.png'
    $legacyJson = $script:Slots | ConvertTo-Json -Depth 4
    Save-Configuration
    $diskJson = [System.IO.File]::ReadAllText($script:ConfigPath)
    Assert-True (-not $diskJson.Contains('Geheimer') -and -not $diskJson.Contains('Vertraulicher') -and -not $diskJson.Contains('Privat')) 'Klartext landete auf dem Datenträger.'
    $script:Slots = @()
    Load-Configuration
    Assert-True ($script:Slots[0].Value -ceq $text) 'Unicode oder mehrzeiliger Text wurde verändert.'
    Assert-True ($script:Slots[0].Name -ceq 'Vertraulicher Slotname') 'Name wurde verändert.'
    Assert-True ($script:Slots[0].ShortcutModifiers -eq 6 -and $script:Slots[0].ShortcutKey -eq 75) 'Tastenkürzel wurde verändert.'
    Assert-True ($script:Slots[1].Value -ceq 'C:\Privat\geheim.pdf' -and $script:Slots[2].Kind -eq 'Image') 'Datei- oder Bild-Slots wurden verändert.'
    Assert-True ($script:Slots[8].Kind -eq 'Empty' -and $script:Slots[8].Value -eq '') 'Leere Slots wurden verändert.'

    # Alte Klartextdatei, beschädigtes Backup und verwaiste temporäre Datei.
    [System.IO.File]::WriteAllText($script:ConfigPath, $legacyJson, [System.Text.Encoding]::UTF8)
    $backupPath = "$($script:ConfigPath).corrupt-test.bak"
    $oldTemporaryPath = "$($script:ConfigPath).tmp"
    [System.IO.File]::WriteAllText($backupPath, 'altes beschädigtes Backup: geheimer Inhalt')
    [System.IO.File]::WriteAllText($oldTemporaryPath, $legacyJson)
    Load-Configuration
    Assert-True ($script:Slots[0].Value -ceq $text) 'Klartextmigration verlor den Slot-Inhalt.'
    foreach ($path in @($script:ConfigPath, $backupPath, $oldTemporaryPath)) {
        $envelope = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json
        Assert-True ($envelope.Format -eq 'SlotPaste.DPAPI') 'Eine alte Datei blieb unverschlüsselt.'
    }
    $backupEnvelope = [System.IO.File]::ReadAllText($backupPath) | ConvertFrom-Json
    Assert-True ((Unprotect-ConfigurationJson $backupEnvelope) -ceq 'altes beschädigtes Backup: geheimer Inhalt') 'Backup-Inhalt ging bei der Migration verloren.'

    # Das historische JSON-Wrapperformat bleibt lesbar.
    $wrapper = '{"value":' + $legacyJson + ',"Count":9}'
    [System.IO.File]::WriteAllText($script:ConfigPath, $wrapper)
    Load-Configuration
    Assert-True ($script:Slots[0].Value -ceq $text) 'Historisches Wrapperformat wurde nicht migriert.'

    $validEncryptedJson = [System.IO.File]::ReadAllText($script:ConfigPath)
    $tamperedEnvelope = $validEncryptedJson | ConvertFrom-Json
    $ciphertext = [Convert]::FromBase64String($tamperedEnvelope.Payload)
    $ciphertext[$ciphertext.Length - 1] = $ciphertext[$ciphertext.Length - 1] -bxor 1
    $tamperedEnvelope.Payload = [Convert]::ToBase64String($ciphertext)
    [System.IO.File]::WriteAllText($script:ConfigPath, ($tamperedEnvelope | ConvertTo-Json))
    Assert-LoadRejected
    $tamperedEnvelope = $validEncryptedJson | ConvertFrom-Json
    $tamperedEnvelope.Version = 99
    [System.IO.File]::WriteAllText($script:ConfigPath, ($tamperedEnvelope | ConvertTo-Json))
    Assert-LoadRejected
    [System.IO.File]::WriteAllText($script:ConfigPath, '{kaputte JSON-Datei')
    Assert-LoadRejected

    # Entschlüsselung mit falschem Schlüsselkontext muss ebenfalls fehlschlagen.
    $foreignEnvelope = $validEncryptedJson | ConvertFrom-Json
    $foreignEnvelope.Payload = [Convert]::ToBase64String([System.Security.Cryptography.ProtectedData]::Protect(
        [System.Text.Encoding]::UTF8.GetBytes($legacyJson), [byte[]]@(1, 2, 3), [System.Security.Cryptography.DataProtectionScope]::CurrentUser))
    [System.IO.File]::WriteAllText($script:ConfigPath, ($foreignEnvelope | ConvertTo-Json))
    Assert-LoadRejected

    [System.IO.File]::WriteAllText($script:ConfigPath, $validEncryptedJson)
    Load-Configuration
    $beforeLockedSave = [System.IO.File]::ReadAllText($script:ConfigPath)
    $lock = [System.IO.File]::Open($script:ConfigPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $saveFailed = $false
    try { try { Save-Configuration } catch { $saveFailed = $true } } finally { $lock.Dispose() }
    Assert-True $saveFailed 'Speichertest mit gesperrter Datei schlug unerwartet nicht fehl.'
    Assert-True ([System.IO.File]::ReadAllText($script:ConfigPath) -ceq $beforeLockedSave) 'Fehlgeschlagenes Speichern änderte die Konfiguration.'
    Assert-True ([System.IO.Directory]::GetFiles($script:DataDirectory, 'slots.json.*.tmp').Length -eq 0) 'Temporäre Speicherdatei blieb liegen.'

    # Historische Korruptionsbehandlung erstellt ausschließlich geschützte Backups.
    $brokenSlots = $legacyJson | ConvertFrom-Json
    foreach ($slot in $brokenSlots) { $slot.Name = 'n' * 4096; $slot.Value = 'v' * 4096 }
    [System.IO.File]::WriteAllText($script:ConfigPath, ($brokenSlots | ConvertTo-Json -Depth 4))
    Load-Configuration
    Assert-True ($script:Slots[0].Kind -eq 'Empty') 'Historische beschädigte Konfiguration wurde nicht wiederhergestellt.'
    foreach ($path in [System.IO.Directory]::GetFiles($script:DataDirectory, 'slots.json.corrupt-*.bak')) {
        $envelope = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json
        Assert-True ($envelope.Format -eq 'SlotPaste.DPAPI') 'Wiederherstellung erzeugte ein Klartextbackup.'
    }
    Write-Output 'OK: DPAPI, Neustart, Unicode, Slot-Typen, Migration, Backups, Manipulation und Schreibfehler.'
} catch {
    Write-Output $_.ScriptStackTrace
    if ($null -ne $_.Exception.InnerException) { Write-Output $_.Exception.InnerException.Message }
    throw
} finally {
    # Nur das nachweislich eigene Testverzeichnis innerhalb dieses Ordners löschen.
    $testRoot = [System.IO.Path]::GetFullPath($script:DataDirectory)
    $allowedRoot = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'
    if (-not $testRoot.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Ungültiger Testpfad.' }
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
