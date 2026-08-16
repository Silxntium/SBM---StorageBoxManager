import SwiftUI

struct FileBrowser: View {
    let box: StorageBox

    @Environment(AppModel.self) private var appModel
    @State private var browser: BrowserModel?
    @State private var showingNewFolder = false
    @State private var renameTarget: RemoteItem?
    @State private var deleteTargets: [RemoteItem] = []
    @State private var isDropTargeted = false

    var body: some View {
        Group {
            if let browser {
                content(browser)
            } else {
                Color.clear
            }
        }
        .task(id: box.id) {
            // Rebuilt per box so a changed password or hostname takes effect immediately.
            browser = BrowserModel(box: box, model: appModel)
            browser?.reload(force: false)
        }
    }

    @ViewBuilder
    private func content(_ browser: BrowserModel) -> some View {
        @Bindable var browser = browser

        VStack(spacing: 0) {
            BreadcrumbBar(path: browser.path) { browser.navigate(to: $0) }
            Divider()
            listing(browser)
                .dropDestination(for: URL.self) { urls, _ in
                    browser.upload(urls)
                    return true
                } isTargeted: { isDropTargeted = $0 }
            TransfersPanel()
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle(box.resolvedName)
        .navigationSubtitle(browser.path.displayPath)
        .toolbar { toolbar(browser) }
        .sheet(isPresented: $showingNewFolder) {
            NameEntrySheet(
                title: "Neuer Ordner",
                prompt: "Name des Ordners",
                initialText: "",
                confirmLabel: "Anlegen"
            ) { browser.createFolder(named: $0) }
        }
        .sheet(item: $renameTarget) { item in
            NameEntrySheet(
                title: "„\(item.name)“ umbenennen",
                prompt: "Neuer Name",
                initialText: item.name,
                confirmLabel: "Umbenennen"
            ) { browser.rename(item, to: $0) }
        }
        .confirmationDialog(
            deleteTargets.count == 1
                ? "„\(deleteTargets[0].name)“ löschen?"
                : "\(deleteTargets.count) Objekte löschen?",
            isPresented: Binding(
                get: { !deleteTargets.isEmpty },
                set: { if !$0 { deleteTargets = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                browser.delete(deleteTargets)
                deleteTargets = []
            }
            Button("Abbrechen", role: .cancel) { deleteTargets = [] }
        } message: {
            Text(deleteTargets.contains(where: \.isDirectory)
                 ? "Ordner werden mit ihrem gesamten Inhalt gelöscht. Das lässt sich nicht rückgängig machen."
                 : "Das lässt sich nicht rückgängig machen.")
        }
        .alert(item: $browser.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }

    @ViewBuilder
    private func listing(_ browser: BrowserModel) -> some View {
        @Bindable var browser = browser

        switch browser.state {
        case .idle:
            loadingView(browser)

        // Only while there is nothing to show yet — a refresh keeps the current list on
        // screen instead of replacing it with a spinner.
        case .loading where browser.items.isEmpty:
            loadingView(browser)

        case .failed(let message):
            ContentUnavailableView {
                Label("Ordner konnte nicht geladen werden", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Erneut versuchen") { browser.refresh() }
            }

        default:
            if browser.sortedItems.isEmpty {
                ContentUnavailableView(
                    browser.hiddenItemCount > 0 ? "Nichts Sichtbares hier" : "Dieser Ordner ist leer",
                    systemImage: "folder",
                    description: Text(
                        browser.hiddenItemCount > 0
                            ? "\(browser.hiddenItemCount) versteckte Objekte. Mit ⌘⇧. einblenden."
                            : "Zieh Dateien hierher, um sie hochzuladen."
                    )
                )
            } else {
                fileTable(browser)
            }
        }
    }

    private func loadingView(_ browser: BrowserModel) -> some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Lade \(browser.path.displayPath)…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fileTable(_ browser: BrowserModel) -> some View {
        @Bindable var browser = browser

        return Table(browser.sortedItems, selection: $browser.selection, sortOrder: $browser.sortOrder) {
            TableColumn("Name", value: \.name) { item in
                HStack(spacing: 6) {
                    Image(systemName: item.symbolName)
                        .foregroundStyle(item.isDirectory ? box.tint.color : Color.secondary)
                        .frame(width: 16)
                    Text(item.name).lineLimit(1)
                }
                .draggableRemoteFile(item, backend: browser.storageBackend)
            }
            .width(min: 200, ideal: 340)

            TableColumn("Größe", value: \.sortSize) { item in
                Text(item.formattedSize)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 80, ideal: 100)

            TableColumn("Geändert", value: \.sortDate) { item in
                Text(item.formattedModified)
                    .foregroundStyle(.secondary)
            }
            .width(min: 130, ideal: 170)

            TableColumn("Art", value: \.kindDescription) { item in
                Text(item.kindDescription)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 90, ideal: 130)
        }
        // primaryAction is the double-click, which is what opens a folder.
        .contextMenu(forSelectionType: RemoteItem.ID.self) { ids in
            contextMenu(browser, ids: ids)
        } primaryAction: { ids in
            if let first = ids.first, let item = browser.visibleItems.first(where: { $0.id == first }) {
                browser.open(item)
            }
        }
    }

    @ViewBuilder
    private func contextMenu(_ browser: BrowserModel, ids: Set<RemoteItem.ID>) -> some View {
        let targets = browser.visibleItems.filter { ids.contains($0.id) }

        if targets.count == 1, let item = targets.first {
            if item.isDirectory {
                Button("Öffnen") { browser.open(item) }
            }
            Button("Umbenennen…") { renameTarget = item }
            Divider()
        }
        if targets.contains(where: { !$0.isDirectory }) {
            Button("Herunterladen") { download(browser, targets) }
        }
        if !targets.isEmpty {
            Button("Löschen…", role: .destructive) { deleteTargets = targets }
            Divider()
        }
        Button("Neuer Ordner…") { showingNewFolder = true }
        Button("Dateien hochladen…") { upload(browser) }
        Button("Aktualisieren") { browser.refresh() }
    }

    private func upload(_ browser: BrowserModel) {
        let urls = DownloadFolderStore.promptForUploadFiles()
        guard !urls.isEmpty else { return }
        browser.upload(urls)
    }

    private func download(_ browser: BrowserModel, _ targets: [RemoteItem]) {
        guard !targets.isEmpty, let folder = appModel.resolveDownloadFolder() else { return }
        browser.download(targets, to: folder)
    }

    @ToolbarContentBuilder
    private func toolbar(_ browser: BrowserModel) -> some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                browser.goUp()
            } label: {
                Label("Übergeordneter Ordner", systemImage: "chevron.up")
            }
            .disabled(!browser.canGoUp)
            .keyboardShortcut(.upArrow, modifiers: .command)
        }

        ToolbarItemGroup {
            Button {
                showingNewFolder = true
            } label: {
                Label("Neuer Ordner", systemImage: "folder.badge.plus")
            }

            Button {
                upload(browser)
            } label: {
                Label("Hochladen", systemImage: "arrow.up.doc")
            }

            Button {
                download(browser, browser.selectedItems)
            } label: {
                Label("Herunterladen", systemImage: "arrow.down.doc")
            }
            .disabled(!browser.selectedItems.contains { !$0.isDirectory })

            Button {
                deleteTargets = browser.selectedItems
            } label: {
                Label("Löschen", systemImage: "trash")
            }
            .disabled(browser.selection.isEmpty)

            Button {
                browser.showsHiddenFiles.toggle()
            } label: {
                Label(
                    browser.showsHiddenFiles ? "Versteckte Dateien ausblenden" : "Versteckte Dateien einblenden",
                    systemImage: browser.showsHiddenFiles ? "eye" : "eye.slash"
                )
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .help(browser.showsHiddenFiles
                  ? "Versteckte Dateien ausblenden (⌘⇧.)"
                  : "\(browser.hiddenItemCount) versteckte Objekte einblenden (⌘⇧.)")

            Button {
                browser.refresh()
            } label: {
                Label("Aktualisieren", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
        }
    }
}

/// Clickable path from the box root down to the current folder.
private struct BreadcrumbBar: View {
    let path: RemotePath
    let onSelect: (RemotePath) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(Array(path.breadcrumbTrail.enumerated()), id: \.element) { index, crumb in
                    if index > 0 {
                        Image(systemName: "chevron.compact.right")
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        onSelect(crumb)
                    } label: {
                        Text(crumb.isRoot ? "Wurzel" : crumb.name)
                            .fontWeight(crumb == path ? .semibold : .regular)
                    }
                    .buttonStyle(.accessoryBar)
                    .disabled(crumb == path)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.never)
        .defaultScrollAnchor(.trailing)
    }
}
