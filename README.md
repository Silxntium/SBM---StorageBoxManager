# Storage Boxes

*[Deutsch weiter unten](#storage-boxes-deutsch)*

A small app for managing multiple storage boxes with custom names and browsing their files
through a proper interface instead of the Finder. Runs on macOS, iPhone, and iPad from one
codebase — same boxes, same WebDAV backend, a layout that fits each screen.

## Why

Hetzner Storage Boxes show up in the Finder under their server hostname (e.g.
`u123456.your-storagebox.de`), which can't be renamed there. This app connects directly over
WebDAV and lets you give each box a name of your own.

It's not limited to Hetzner, though — it's a plain WebDAV-over-HTTPS client (Basic auth,
standard port 443), so it should work with Nextcloud, ownCloud, or any other WebDAV provider
just as well. The wording in the app leans on Hetzner because that's what it was built for, not
because anything is hardcoded to it.

## Installation

**macOS** — download the latest `StorageBoxManager.zip` from [Releases](../../releases), unzip
it, and drag the `.app` into your Applications folder. The app is signed and notarized — no
Gatekeeper warning on launch.

**iPhone / iPad** — ships through TestFlight from the same target and bundle identifier.

## Features

- Multiple boxes, each with its own name, color, and icon
- File browser with breadcrumbs, search, sorting, list/icon views, and multi-select
- Create folders, rename, delete, duplicate, Quick Look, favorites
- Upload and download files **and folders**, with progress, speed, and ETA
- Name-conflict prompts (Replace / Keep Both / Skip)
- Resume interrupted uploads and downloads when the server/local partial still exists
- Retry failed or cancelled transfers
- Storage quota in the status bar (when the server reports it)
- Passwords live in the keychain, not in the app itself

### On iPhone and iPad

The browser is one screen per box: tap a box to open it, back goes up a folder, and the
breadcrumb bar at the bottom jumps anywhere along the path. The macOS table becomes a two-line
list, multi-select lives behind "Select", and swiping a row gets at download, delete, and
rename. Uploads come from the document picker; downloads land in the app's own folder, which
shows up in Files under "On My iPhone › Storage Boxes".

One thing to know: transfers only run while the app is on screen. Switching away gives them a
few seconds of grace, enough for small files, but a large upload needs the app left open.

## Building

Requires Xcode 16+. One target builds both platforms — macOS 15+ and iOS 18+.

```bash
xcodebuild -project StorageBoxManager.xcodeproj -scheme StorageBoxManager -destination 'platform=macOS' build
```

```bash
xcodebuild -project StorageBoxManager.xcodeproj -scheme StorageBoxManager -destination 'generic/platform=iOS' build
```

---

<a id="storage-boxes-deutsch"></a>

# Storage Boxes (Deutsch)

Eine kleine App, um mehrere Storage Boxen mit selbst gewählten Namen zu verwalten und ihre
Dateien über eine eigene Oberfläche zu durchsuchen, statt über den Finder. Läuft aus einer
Codebasis auf macOS, iPhone und iPad — dieselben Boxen, dasselbe WebDAV-Backend, ein Layout,
das zum jeweiligen Bildschirm passt.

## Warum

Hetzner Storage Boxen werden im Finder standardmäßig mit ihrem Server-Hostnamen angezeigt
(z. B. `u123456.your-storagebox.de`), was sich dort nicht ändern lässt. Diese App verbindet
sich per WebDAV direkt mit den Boxen und lässt jeder einen eigenen Namen geben.

Sie ist dabei nicht auf Hetzner beschränkt — technisch ist es ein ganz normaler WebDAV-über-
HTTPS-Client (Basic Auth, Standardport 443), sollte also genauso mit Nextcloud, ownCloud oder
anderen WebDAV-Anbietern funktionieren. Die Beschriftung in der App orientiert sich an Hetzner,
weil das der ursprüngliche Anlass war — fest verdrahtet ist nichts davon.

## Installation

**macOS** — unter [Releases](../../releases) die neueste `StorageBoxManager.zip` herunterladen,
entpacken und die `.app` in den Programme-Ordner ziehen. Die App ist signiert und notarisiert —
startet ohne Gatekeeper-Warnung.

**iPhone / iPad** — kommt über TestFlight, aus demselben Target und mit derselben Bundle-ID.

## Funktionen

- Mehrere Storage Boxen mit eigenem Namen, Farbe und Symbol verwalten
- Dateibrowser mit Breadcrumbs, Suche, Sortierung, Listen-/Symbolansicht und Mehrfachauswahl
- Ordner anlegen, umbenennen, löschen, duplizieren, Quick Look, Favoriten
- Hoch- und Herunterladen von Dateien **und Ordnern**, mit Fortschritt, Geschwindigkeit und ETA
- Namenskonflikte (Ersetzen / Beide behalten / Überspringen)
- Fortsetzen unterbrochener Uploads und Downloads, wenn noch eine Teildatei vorhanden ist
- Fehlgeschlagene oder abgebrochene Transfers erneut starten
- Speicherkontingent in der Statusleiste (wenn der Server es meldet)
- Passwörter liegen im Schlüsselbund, nicht in der App selbst

### Auf iPhone und iPad

Der Browser ist ein Bildschirm pro Box: Box antippen zum Öffnen, Zurück geht einen Ordner hoch,
und die Breadcrumb-Leiste unten springt an jede Stelle des Pfads. Aus der macOS-Tabelle wird
eine zweizeilige Liste, Mehrfachauswahl steckt hinter „Select", und ein Wisch über eine Zeile
gibt Download, Löschen und Umbenennen frei. Uploads kommen aus der Dateien-Auswahl, Downloads
landen im App-eigenen Ordner, der in „Dateien" unter „Auf meinem iPhone › Storage Boxes"
auftaucht.

Eine Einschränkung: Transfers laufen nur, solange die App sichtbar ist. Beim Wegwischen bleiben
ein paar Sekunden Puffer — genug für kleine Dateien, ein großer Upload braucht die App offen.

## Bauen

Xcode 16+ nötig. Ein Target baut beide Plattformen — macOS 15+ und iOS 18+.

```bash
xcodebuild -project StorageBoxManager.xcodeproj -scheme StorageBoxManager -destination 'platform=macOS' build
```

```bash
xcodebuild -project StorageBoxManager.xcodeproj -scheme StorageBoxManager -destination 'generic/platform=iOS' build
```
