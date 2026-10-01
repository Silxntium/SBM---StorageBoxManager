import SwiftUI
import UniformTypeIdentifiers

struct FileBrowserPresentations: ViewModifier {
    let box: StorageBox
    @Bindable var browser: BrowserModel
    let ui: FileBrowserUI

    @Environment(AppModel.self) private var appModel

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.browserActions, FileBrowserActions.commands(box: box, browser: browser, ui: ui, appModel: appModel))
            .onDeleteKey {
                if !browser.selectedItems.isEmpty { ui.deleteTargets = browser.selectedItems }
            }
            .onCopyKey {
                copyToPasteboard(browser.selectedItems.map(\.name).joined(separator: "\n"))
            }
            .modifier(UploadPicker(browser: browser, ui: ui))
            .onChange(of: browser.path) { _, _ in ui.isSelecting = false }
            .onChange(of: browser.searchText) { _, _ in browser.scheduleSearch() }
            .onChange(of: browser.searchScope) { _, _ in browser.scheduleSearch() }
            .onChange(of: browser.kindFilter) { _, _ in browser.scheduleSearch() }
            .onChange(of: browser.sortOrder) { _, new in browser.adoptSortOrder(new) }
            .sheet(isPresented: Bindable(ui).showingNewFolder) {
                NameEntrySheet(title: "New Folder", prompt: "Folder name", initialText: "", confirmLabel: "Create") {
                    browser.createFolder(named: $0)
                }
            }
            .sheet(isPresented: Bindable(ui).showingGoToFolder) {
                GoToFolderSheet(currentPath: browser.path.displayPath) { browser.goToFolder(typed: $0) }
            }
            .sheet(item: Bindable(ui).renameTarget) { item in
                NameEntrySheet(title: "Rename", prompt: "New name", initialText: item.name, confirmLabel: "Rename") {
                    browser.rename(item, to: $0)
                }
            }
            .sheet(item: conflictPresented) { prompt in
                ConflictSheet(
                    prompt: prompt,
                    onSkip: { browser.resolveConflictPrompt(.skip, applyToAll: $0) },
                    onKeepBoth: { browser.resolveConflictPrompt(.keepBoth, applyToAll: $0) },
                    onReplace: { browser.resolveConflictPrompt(.replace, applyToAll: $0) }
                )
            }
            .sheet(isPresented: infoPresented) {
                GetInfoSheet(items: ui.infoItems, relativeDates: browser.usesRelativeDates)
            }
            .confirmationDialog(
                deleteTitle,
                isPresented: deletePresented,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    browser.delete(ui.deleteTargets)
                    ui.deleteTargets = []
                }
                Button("Cancel", role: .cancel) { ui.deleteTargets = [] }
            } message: {
                Text(deleteMessage)
            }
            .alert(browser.alert?.title ?? "", isPresented: alertPresented) {
                Button("OK", role: .cancel) { browser.alert = nil }
            } message: {
                Text(browser.alert?.message ?? "")
            }
    }

    private var conflictPresented: Binding<ConflictPrompt?> {
        Binding(
            get: { browser.conflictPrompt },
            set: { newValue in
                if newValue == nil {
                    browser.dismissConflictIfNeeded()
                } else {
                    browser.conflictPrompt = newValue
                }
            }
        )
    }

    private var infoPresented: Binding<Bool> {
        Binding(get: { !ui.infoItems.isEmpty }, set: { if !$0 { ui.infoItems = [] } })
    }

    private var deletePresented: Binding<Bool> {
        Binding(get: { !ui.deleteTargets.isEmpty }, set: { if !$0 { ui.deleteTargets = [] } })
    }

    private var alertPresented: Binding<Bool> {
        Binding(get: { browser.alert != nil }, set: { if !$0 { browser.alert = nil } })
    }

    private var deleteTitle: String {
        ui.deleteTargets.count == 1
            ? "Delete \"\(ui.deleteTargets[0].name)\"?"
            : "Delete \(ui.deleteTargets.count) items?"
    }

    private var deleteMessage: String {
        ui.deleteTargets.contains(where: \.isDirectory)
            ? "Folders are deleted along with everything inside them. This can't be undone."
            : "This can't be undone."
    }
}

// macOS can ask for files and folders in one open panel and gets the URLs back right away.
// iOS has to present a document picker, so the request becomes state the view reacts to.
@MainActor
func beginUpload(browser: BrowserModel, ui: FileBrowserUI, kind: UploadPickerKind = .files) {
    #if os(macOS)
    let urls = DownloadFolderStore.promptForUploadFiles()
    if !urls.isEmpty { browser.upload(urls) }
    #else
    ui.uploadPicker = kind
    #endif
}

private struct UploadPicker: ViewModifier {
    let browser: BrowserModel
    @Bindable var ui: FileBrowserUI

    func body(content: Content) -> some View {
        #if os(macOS)
        content
        #else
        content.fileImporter(
            isPresented: Binding(get: { ui.uploadPicker != nil }, set: { if !$0 { ui.uploadPicker = nil } }),
            allowedContentTypes: ui.uploadPicker == .folder ? [.folder] : [.item],
            allowsMultipleSelection: true
        ) { result in
            ui.uploadPicker = nil
            switch result {
            case .success(let urls):
                if !urls.isEmpty { browser.upload(urls) }
            case .failure(let error):
                browser.alert = BrowserModel.AlertMessage(
                    title: String(localized: "Couldn't Open Files"),
                    message: error.localizedDescription
                )
            }
        }
        #endif
    }
}

enum FileBrowserActions {
    @MainActor
    static func itemActions(box: StorageBox, browser: BrowserModel, ui: FileBrowserUI, appModel: AppModel) -> FileItemActions {
        FileItemActions(
            open: { browser.open($0) },
            preview: { browser.preview($0) },
            getInfo: { ui.infoItems = $0 },
            rename: { ui.renameTarget = $0 },
            duplicate: { browser.duplicate($0) },
            download: { download(appModel, browser, $0) },
            downloadAndOpen: { download(appModel, browser, [$0], open: true) },
            delete: { ui.deleteTargets = $0 },
            reveal: { browser.reveal($0) },
            toggleFavorite: { appModel.favorites.toggle(boxID: box.id, path: $0.path, title: $0.name) },
            isFavorite: { appModel.favorites.contains(boxID: box.id, path: $0.path) },
            newFolder: { ui.showingNewFolder = true },
            upload: { beginUpload(browser: browser, ui: ui) },
            refresh: { browser.refresh() },
            copyName: { copyToPasteboard($0.name) },
            copyPath: { copyToPasteboard($0.path.displayPath) },
            isDeepSearch: browser.isDeepSearchActive
        )
    }

    @MainActor
    static func commands(box: StorageBox, browser: BrowserModel, ui: FileBrowserUI, appModel: AppModel) -> BrowserActions {
        BrowserActions(
            goUp: { browser.goUp() },
            canGoUp: browser.canGoUp,
            goBack: { browser.goBack() },
            canGoBack: browser.canGoBack,
            goForward: { browser.goForward() },
            canGoForward: browser.canGoForward,
            goToFolder: { ui.showingGoToFolder = true },
            newFolder: { ui.showingNewFolder = true },
            upload: { beginUpload(browser: browser, ui: ui) },
            download: { download(appModel, browser, browser.selectedItems) },
            downloadAndOpen: { download(appModel, browser, browser.selectedItems, open: true) },
            canDownload: browser.selectedItems.contains { !$0.isDirectory },
            deleteSelection: { if !browser.selectedItems.isEmpty { ui.deleteTargets = browser.selectedItems } },
            canDelete: !browser.selection.isEmpty,
            refresh: { browser.refresh() },
            toggleHiddenFiles: { browser.showsHiddenFiles.toggle() },
            showsHiddenFiles: browser.showsHiddenFiles,
            selectAll: { browser.selectAll() },
            getInfo: { if !browser.selectedItems.isEmpty { ui.infoItems = browser.selectedItems } },
            canGetInfo: !browser.selectedItems.isEmpty,
            quickLook: { browser.previewSelection() },
            canQuickLook: browser.canQuickLook,
            duplicate: { if let item = browser.selectedItems.first { browser.duplicate(item) } },
            canDuplicate: browser.canDuplicate,
            toggleFavorite: {
                let title = browser.path.isRoot ? box.resolvedName : browser.path.name
                appModel.favorites.toggle(boxID: box.id, path: browser.path, title: title)
            },
            isFavorite: appModel.favorites.contains(boxID: box.id, path: browser.path),
            setLayout: { browser.setLayout($0) },
            layout: browser.listingLayout,
            setSort: { browser.applySort(field: $0) },
            sortField: browser.sortField,
            toggleFoldersFirst: { browser.setFoldersFirst(!browser.foldersFirst) },
            foldersFirst: browser.foldersFirst,
            toggleRelativeDates: { browser.setRelativeDates(!browser.usesRelativeDates) },
            usesRelativeDates: browser.usesRelativeDates,
            focusSearch: { ui.searchFocused = true }
        )
    }

    @MainActor
    private static func download(_ appModel: AppModel, _ browser: BrowserModel, _ targets: [RemoteItem], open: Bool = false) {
        guard let folder = appModel.resolveDownloadFolder() else { return }
        browser.download(targets, to: folder, openWhenDone: open)
    }
}
