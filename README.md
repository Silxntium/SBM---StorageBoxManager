# Storage Boxes

*[Deutsch weiter unten](#storage-boxes-deutsch)*

A small macOS app for managing multiple storage boxes with custom names and browsing their
files through a proper interface instead of the Finder.

## Why

Hetzner Storage Boxes show up in the Finder under their server hostname (e.g.
`u123456.your-storagebox.de`), which can't be renamed there. This app connects directly over
WebDAV and lets you give each box a name of your own.

It's not limited to Hetzner, though — it's a plain WebDAV-over-HTTPS client (Basic auth,
standard port 443), so it should work with Nextcloud, ownCloud, or any other WebDAV provider
just as well. The wording in the app leans on Hetzner because that's what it was built for, not
because anything is hardcoded to it.

## Installation

Download the latest `StorageBoxManager.zip` from [Releases](../../releases), unzip it, and drag
the `.app` into your Applications folder. The app is signed and notarized — no Gatekeeper
warning on launch.

## Features

- Multiple boxes, each with its own name, color, and icon
- File browser with breadcrumbs, sorting, and multi-select
- Create folders, rename, delete
- Upload/download single files with progress, via drag & drop or a file picker
- Passwords live in the macOS keychain, not in the app itself

## Building

Requires Xcode 16+.

```bash
xcodebuild -project StorageBoxManager.xcodeproj -scheme StorageBoxManager -configuration Debug build
```

---

<a id="storage-boxes-deutsch"></a>

# Storage Boxes (Deutsch)

Eine kleine macOS-App, um mehrere Storage Boxen mit selbst gewählten Namen zu verwalten und
ihre Dateien über eine eigene Oberfläche zu durchsuchen, statt über den Finder.

## Warum

Hetzner Storage Boxen werden im Finder standardmäßig mit ihrem Server-Hostnamen angezeigt
(z. B. `u123456.your-storagebox.de`), was sich dort nicht ändern lässt. Diese App verbindet
sich per WebDAV direkt mit den Boxen und lässt jeder einen eigenen Namen geben.

Sie ist dabei nicht auf Hetzner beschränkt — technisch ist es ein ganz normaler WebDAV-über-
HTTPS-Client (Basic Auth, Standardport 443), sollte also genauso mit Nextcloud, ownCloud oder
anderen WebDAV-Anbietern funktionieren. Die Beschriftung in der App orientiert sich an Hetzner,
weil das der ursprüngliche Anlass war — fest verdrahtet ist nichts davon.

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
