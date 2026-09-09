import SwiftUI

struct FileBrowserChrome: ViewModifier {
    let box: StorageBox
    @Bindable var browser: BrowserModel
    let ui: FileBrowserUI

    @Environment(AppModel.self) private var appModel

    func body(content: Content) -> some View {
        content
            .dropDestination(for: URL.self) { urls, _ in
                browser.upload(urls)
                return true
            } isTargeted: { targeted in
                if ui.isDropTargeted != targeted { ui.isDropTargeted = targeted }
            }
            .overlay {
                if ui.isDropTargeted { DropTargetOverlay() }
            }
            .overlay(alignment: .top) {
                FileBrowserTopChrome(browser: browser)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: 54)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        FileBrowserBottomChrome(browser: browser)
                    }
                    .clipped()
            }
            .navigationTitle(box.resolvedName)
            .navigationSubtitle(browser.path.isRoot ? box.host : browser.path.name)
            .toolbar {
                FileBrowserToolbar(box: box, browser: browser, appModel: appModel, ui: ui)
            }
    }
}

struct FileBrowserToolbar: ToolbarContent {
    let box: StorageBox
    @Bindable var browser: BrowserModel
    let appModel: AppModel
    let ui: FileBrowserUI

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button(appModel.showsSidebar ? "Hide Sidebar" : "Show Sidebar", systemImage: "sidebar.leading") {
                appModel.showsSidebar.toggle()
            }
            .help(appModel.showsSidebar ? "Hide Sidebar (⌃⌘S)" : "Show Sidebar (⌃⌘S)")

            Button("Back", systemImage: "chevron.left") { browser.goBack() }
                .disabled(!browser.canGoBack)
                .help("Back (⌘[)")
            Button("Forward", systemImage: "chevron.right") { browser.goForward() }
                .disabled(!browser.canGoForward)
                .help("Forward (⌘])")
            Button("Parent Folder", systemImage: "chevron.up") { browser.goUp() }
                .disabled(!browser.canGoUp)
                .help("Enclosing Folder (⌘↑)")
        }

        ToolbarItem {
            Picker("View", selection: Binding(
                get: { browser.listingLayout },
                set: { browser.setLayout($0) }
            )) {
                ForEach(ListingLayout.allCases) { layout in
                    Image(systemName: layout.symbolName).tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .help("View")
        }

        ToolbarItemGroup {
            Button("New Folder", systemImage: "folder.badge.plus") { ui.showingNewFolder = true }
                .help("New Folder (⇧⌘N)")
            Button("Upload", systemImage: "square.and.arrow.up") {
                let urls = DownloadFolderStore.promptForUploadFiles()
                if !urls.isEmpty { browser.upload(urls) }
            }
            .help("Upload Files or Folders (⌘U)")
            Button("Download", systemImage: "square.and.arrow.down") {
                guard let folder = appModel.resolveDownloadFolder() else { return }
                browser.download(browser.selectedItems, to: folder)
            }
            .disabled(!browser.selectedItems.contains { !$0.isDirectory })
            .help("Download (⌘S)")
            Button("Delete", systemImage: "trash") { ui.deleteTargets = browser.selectedItems }
                .disabled(browser.selection.isEmpty)
                .help("Delete (⌘⌫)")
        }

        ToolbarItem {
            FileBrowserSearchField(text: $browser.searchText, isFocused: Bindable(ui).searchFocused)
        }

        ToolbarItem {
            FileBrowserOptionsMenu(box: box, browser: browser, appModel: appModel)
        }

        ToolbarItem {
            Button {
                appModel.showsTransfersInspector.toggle()
            } label: {
                Label(
                    "Transfers",
                    systemImage: appModel.showsTransfersInspector ? "list.bullet.rectangle.fill" : "list.bullet.rectangle"
                )
            }
            .help(appModel.showsTransfersInspector ? "Hide Transfers" : "Show Transfers")
        }
    }
}

private struct FileBrowserOptionsMenu: View {
    let box: StorageBox
    @Bindable var browser: BrowserModel
    let appModel: AppModel

    var body: some View {
        Menu {
            Picker("Search", selection: $browser.searchScope) {
                ForEach(SearchScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            Picker("Kind", selection: $browser.kindFilter) {
                ForEach(KindCategory.allCases) { category in
                    Label(category.title, systemImage: category.symbolName).tag(category)
                }
            }
            Divider()
            Picker("Sort By", selection: Binding(
                get: { browser.sortField },
                set: { browser.applySort(field: $0, reversed: browser.sortReversed) }
            )) {
                ForEach(SortField.allCases) { field in
                    Text(field.title).tag(field)
                }
            }
            Button(browser.sortReversed ? "Ascending" : "Descending") {
                browser.applySort(field: browser.sortField, reversed: !browser.sortReversed)
            }
            Toggle("Folders on Top", isOn: Binding(
                get: { browser.foldersFirst },
                set: { browser.setFoldersFirst($0) }
            ))
            Toggle("Relative Dates", isOn: Binding(
                get: { browser.usesRelativeDates },
                set: { browser.setRelativeDates($0) }
            ))
            Divider()
            Button(browser.showsHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files") {
                browser.showsHiddenFiles.toggle()
            }
            Button(appModel.favorites.contains(boxID: box.id, path: browser.path) ? "Remove from Favorites" : "Add Folder to Favorites") {
                let title = browser.path.isRoot ? box.resolvedName : browser.path.name
                appModel.favorites.toggle(boxID: box.id, path: browser.path, title: title)
            }
            Button("Refresh") { browser.refresh() }
        } label: {
            Label("View Options", systemImage: "line.3.horizontal.decrease.circle")
        }
        .help("Search, sort, and view options")
    }
}

private struct FileBrowserSearchField: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    @FocusState private var fieldFocused: Bool

    var body: some View {
        TextField("Search", text: $text, prompt: Text("Search"))
            .textFieldStyle(.roundedBorder)
            .frame(width: 180)
            .focused($fieldFocused)
            .onChange(of: isFocused) { _, wanted in
                if wanted {
                    fieldFocused = true
                    isFocused = false
                }
            }
            .onChange(of: fieldFocused) { _, focused in
                if !focused { isFocused = false }
            }
            .help("Search this folder")
    }
}

private struct FileBrowserTopChrome: View {
    let browser: BrowserModel

    var body: some View {
        ProgressView()
            .progressViewStyle(.linear)
            .controlSize(.mini)
            .opacity(browser.state == .loading || browser.isDeepSearching ? 1 : 0)
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }
}

private struct FileBrowserBottomChrome: View {
    let browser: BrowserModel

    var body: some View {
        VStack(spacing: 0) {
            PathBar(path: browser.path) { browser.navigate(to: $0) }
            BrowserStatusBar(
                summary: browser.statusSummary,
                quotaSummary: browser.quota?.summary,
                hiddenItemCount: browser.hiddenItemCount,
                isBusy: browser.state == .loading || browser.isDeepSearching
            )
        }
    }
}

private struct PathBar: View {
    let path: RemotePath
    let onSelect: (RemotePath) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(Array(path.breadcrumbTrail.enumerated()), id: \.element) { index, crumb in
                    if index > 0 {
                        Image(systemName: "chevron.compact.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        onSelect(crumb)
                    } label: {
                        HStack(spacing: 5) {
                            if crumb.isRoot {
                                Image(systemName: "externaldrive")
                                    .imageScale(.small)
                            }
                            Text(crumb.isRoot ? "Root" : crumb.name)
                                .fontWeight(crumb == path ? .semibold : .regular)
                        }
                    }
                    .buttonStyle(.accessoryBar)
                    .disabled(crumb == path)
                    .help(crumb.displayPath)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct DropTargetOverlay: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.accentColor.opacity(0.08))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
            }
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title)
                        .foregroundStyle(Color.accentColor)
                    Text("Drop files or folders to upload")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(12)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
