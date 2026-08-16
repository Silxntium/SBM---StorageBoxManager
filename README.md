# Storage Boxes

Eine kleine macOS-App, um mehrere Hetzner Storage Boxen mit selbst gewählten Namen zu verwalten
und ihre Dateien über eine eigene Oberfläche zu durchsuchen, hoch- und herunterzuladen.

## Warum

Hetzner Storage Boxen werden im Finder standardmäßig mit ihrem Server-Hostnamen angezeigt
(z. B. `u123456.your-storagebox.de`), was sich dort nicht ändern lässt. Diese App verbindet
sich per WebDAV direkt mit den Boxen und lässt jeder einen eigenen Namen geben.

## Installation

Unter [Releases](../../releases) die neueste `StorageBoxManager.zip` herunterladen, entpacken
und die `.app` in den Programme-Ordner ziehen. Die App ist signiert und notarisiert — startet
ohne Gatekeeper-Warnung.

## Funktionen

- Mehrere Storage Boxen mit eigenem Namen, Farbe und Symbol verwalten
- Dateibrowser mit Breadcrumbs, Sortierung und Mehrfachauswahl
- Ordner anlegen, umbenennen, löschen
- Hoch- und Herunterladen einzelner Dateien mit Fortschrittsanzeige, per Drag & Drop oder Dialog
- Passwörter liegen im macOS-Schlüsselbund, nicht in der App selbst

## Bauen

Xcode 16+ nötig.

```bash
xcodebuild -project StorageBoxManager.xcodeproj -scheme StorageBoxManager -configuration Debug build
```
