# SlotPaste

SlotPaste ist ein kleines Windows-Tray-Tool für Inhalte, die regelmäßig eingefügt werden müssen. Es kann Text, Bilder und Dateien speichern. Dateien können auch Videos sein.

## Starten

1. Den gesamten Quellcode-Ordner in einen festen Ordner kopieren. Benötigt wird Windows mit Windows PowerShell 5.1 und grafischer Desktop-Sitzung.
2. `SlotPaste.ps1` über Windows PowerShell starten (siehe unten). Eine selbst gebaute `SlotPaste.exe` kann bei installierter .NET-8-Desktop-Runtime per Doppelklick gestartet werden.
3. Für Autostart und den ersten Start `install.ps1` mit PowerShell ausführen. Das richtet den Autostart ein und startet SlotPaste sofort.
4. Das Programm erscheint als kleines Symbol im Infobereich unten rechts. Ein Doppelklick öffnet die Slot-Verwaltung.

Falls Windows das Ausführen von Skripten blockiert, kann das Installationsskript einmal so gestartet werden:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Direkter Start ohne Build und ohne zusätzliche .NET-Installation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File .\SlotPaste.ps1
```

## Bedienung

- Standard-Tastenkombinationen: `Strg + Alt + 1` bis `Strg + Alt + 9`.
- In der Slot-Verwaltung kann jede Tastenkombination geändert werden.
- `Text...` speichert Signaturen, Sätze, Links oder andere Textbausteine.
- `Auswählen...` speichert ein Bild oder den Pfad zu einer beliebigen Datei.
- Über das Tray-Menü kann die aktuelle Windows-Zwischenablage direkt in einen Slot übernommen werden.
- Die Tastenkombination kopiert den Slot-Inhalt in die normale Zwischenablage. Mit `Strg + V` wird er anschließend selbst eingefügt.
- In der Slot-Verwaltung entscheidet die Checkbox `Mit Windows starten`, ob SlotPaste automatisch gestartet wird.
- Die Tastenkombination jedes Slots kann über die jeweilige Schaltfläche individuell aufgenommen werden. Die Voreinstellungen sind `Strg + Alt + 1` bis `Strg + Alt + 9`.
- Slots, Texte, Dateien, Namen und Tastenkürzel werden dauerhaft gespeichert und bleiben nach dem Beenden sowie nach einem Windows-Neustart erhalten.

Bei einem Video wird der Dateipfad als Windows-Dateiablage eingefügt. Das verhält sich wie das Ziehen der Videodatei aus dem Explorer und funktioniert in Programmen, die Dateien per Einfügen oder Drag-and-drop annehmen.

## Datenablage

Die Slot-Konfiguration liegt unter `%APPDATA%\SlotPaste\slots.json`. Die gesamte Konfiguration einschließlich Texte, Slot-Namen, Dateipfade und Tastenkürzel wird mit Windows DPAPI für das aktuelle Windows-Benutzerkonto verschlüsselt. Ein separates Passwort ist nicht erforderlich. Auch temporäre Speicherdateien enthalten nur verschlüsselte Daten. Falls AppData nicht beschreibbar ist, verwendet SlotPaste den Unterordner `data` neben dem Skript mit derselben Verschlüsselung.

Vorhandene unverschlüsselte Konfigurationen sowie alte `slots.json.corrupt-*.bak`-Sicherungen und `slots.json.tmp` werden beim ersten Start der neuen Version automatisch verschlüsselt. Alte Sicherungen bleiben inhaltlich erhalten. Kann eine Datei nicht entschlüsselt oder gelesen werden, startet SlotPaste mit einer Fehlermeldung und überschreibt die Slot-Datei nicht mit leeren Slots.

Eine kopierte Slot-Datei lässt sich ohne den zugehörigen Windows-Kontoschutz nicht lesen. Programme, die bereits unter diesem Benutzerkonto laufen, können DPAPI ebenfalls verwenden. Bei einem Umzug auf ein anderes Windows-Konto oder einen anderen Rechner reicht das Kopieren von `slots.json` allein daher nicht aus. Frühere externe Sicherungskopien werden durch die Umstellung nicht nachträglich geschützt.

Bilder, die aus der Zwischenablage übernommen werden, liegen weiterhin unverschlüsselt unter `%APPDATA%\SlotPaste\assets`; ausgewählte Originaldateien bleiben ebenfalls unverändert. Beim Einfügen liegt der gewählte Text wie bisher in der normalen Windows-Zwischenablage.

Zum Entfernen des Autostarts `uninstall.ps1` ausführen. Das Programm selbst muss vorher beendet werden.

## Neu bauen

Voraussetzung ist das .NET 8 SDK für Windows (über `winget install Microsoft.DotNet.SDK.8` installierbar). Für das erstmalige Wiederherstellen der Build-Pakete ist Internetzugang zu NuGet erforderlich. Alle Befehle im Projektordner ausführen:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build-installer.ps1
```

Das Installer-Skript baut die App selbst mit; ein vorheriger Aufruf von `build.ps1` ist dafür nicht erforderlich.

`build.ps1` erstellt standardmäßig eine kleine Windows-Single-File-EXE. Dafür muss die .NET-8-Desktop-Runtime auf dem Zielrechner installiert sein. Für eine vollständig selbstständige, aber deutlich größere EXE kann `build.ps1 -SelfContained` verwendet werden. Das Programmbild liegt als `SlotPaste.png` und als Windows-Symbol `SlotPaste.ico` im Projektordner.

Die vorhandenen Prüfungen lassen sich mit Windows PowerShell ausführen. Sie prüfen die verschlüsselte Speicherung und die Windows-App-Identität, ohne die eigene Slot-Konfiguration zu verändern:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-EncryptedStorage.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-TaskbarIdentity.ps1
```

## Verteilen

`build-installer.ps1` erstellt `SlotPaste-Setup.exe`. Diese einzelne Setup-Datei kann an andere Benutzer verteilt werden. Sie installiert SlotPaste pro Benutzer ohne Administratorrechte, legt eine Startmenü-Verknüpfung an, richtet die Deinstallation ein und startet SlotPaste direkt. Die Installationsdatei ist größer, weil sie ihre eigene .NET-Laufzeit enthält; die installierte Startmenü-Verknüpfung verwendet die integrierte Windows-PowerShell und benötigt keine vorherige .NET-Installation.

## GitHub-Repository

Ins Repository gehören Quellcode, Skripte, Tests, `NuGet.Config`, `SlotPaste.png`, `SlotPaste.ico` und diese Anleitung. Fertige EXE-Dateien können separat als GitHub-Release angeboten werden; sie sind kein Bestandteil des Quellcode-Repositories.

Die `.gitignore` schließt erzeugte Build-Dateien, Paket-Caches, Grafikentwürfe sowie die lokalen Ordner `data` und `.slotpaste-runtime` aus. Diese beiden Ordner können persönliche Slot-Daten enthalten und dürfen nicht veröffentlicht werden. Sie sind für einen frischen Start nicht erforderlich und werden bei Bedarf automatisch angelegt. Die regulären Nutzerdaten unter `%APPDATA%\SlotPaste` liegen außerhalb des Projekts.

Für die Veröffentlichung Git verwenden, damit die `.gitignore` berücksichtigt wird. Beim manuellen Hochladen im Browser oder Erstellen eines ZIP-Archivs müssen ausgeschlossene Dateien ausdrücklich weggelassen werden.
