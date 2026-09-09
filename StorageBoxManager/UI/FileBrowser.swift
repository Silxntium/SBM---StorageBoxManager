import SwiftUI

struct FileBrowser: View {
    let box: StorageBox
    @Environment(AppModel.self) private var appModel

    var body: some View {
        FileBrowserPrepared(box: box, appModel: appModel)
    }
}

private struct FileBrowserPrepared: View {
    let box: StorageBox
    let appModel: AppModel
    @State private var browser: BrowserModel
    @State private var ui = FileBrowserUI()

    init(box: StorageBox, appModel: AppModel) {
        self.box = box
        self.appModel = appModel
        _browser = State(initialValue: BrowserModel(box: box, model: appModel, initialPath: appModel.pendingFolder))
    }

    var body: some View {
        FileBrowserListing(box: box, browser: browser, ui: ui)
            .modifier(FileBrowserChrome(box: box, browser: browser, ui: ui))
            .modifier(FileBrowserPresentations(box: box, browser: browser, ui: ui))
            .task(id: box.id) {
                if appModel.pendingFolder != nil {
                    appModel.pendingFolder = nil
                }
                browser.reload(force: false)
            }
            .onChange(of: appModel.pendingFolder) { _, path in
                guard let path else { return }
                appModel.pendingFolder = nil
                browser.navigate(to: path)
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }
}

@MainActor
@Observable
final class FileBrowserUI {
    var showingNewFolder = false
    var showingGoToFolder = false
    var renameTarget: RemoteItem?
    var infoItems: [RemoteItem] = []
    var deleteTargets: [RemoteItem] = []
    var isDropTargeted = false
    var searchFocused = false
}
