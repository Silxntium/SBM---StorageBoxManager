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
            .modifier(FileBrowserNavigationChrome(box: box, browser: browser, ui: ui, appModel: appModel))
    }
}

// The navigation bar is where the two platforms part ways: macOS spreads everything across a wide
// window toolbar, the iPhone has room for a title and two buttons.
private struct FileBrowserNavigationChrome: ViewModifier {
    let box: StorageBox
    @Bindable var browser: BrowserModel
    let ui: FileBrowserUI
    let appModel: AppModel

    private var compactTitle: String {
        if ui.isSelecting {
            return browser.selection.isEmpty
                ? String(localized: "Select Items")
                : String(localized: "\(browser.selection.count) selected")
        }
        return browser.path.isRoot ? box.resolvedName : browser.path.name
    }

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .navigationTitle(box.resolvedName)
            .navigationSubtitle(browser.path.isRoot ? box.host : browser.path.name)
            .toolbar {
                FileBrowserToolbar(box: box, browser: browser, appModel: appModel, ui: ui)
            }
        #else
        content
            // the box name is the screen you came from, so the title names the folder instead
            .navigationTitle(compactTitle)
            .navigationBarTitleDisplayMode(.inline)
            // inside a subfolder, back has to mean "up one level" - popping all the way out to
            // the box list from three folders deep is not what anyone reaches for
            .navigationBarBackButtonHidden(!browser.path.isRoot)
            .searchable(text: $browser.searchText, placement: .navigationBarDrawer, prompt: Text("Search"))
            .searchScopes($browser.searchScope) {
                ForEach(SearchScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .toolbar {
                FileBrowserCompactToolbar(box: box, browser: browser, appModel: appModel, ui: ui)
            }
        #endif
    }
}

#if os(macOS)

private struct FileBrowserToolbar: ToolbarContent {
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
                beginUpload(browser: browser, ui: ui)
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

#else

// Two menus: one for adding things to the folder, one for everything else. Both stay reachable
// with one thumb, which the wide macOS toolbar row would not.
private struct FileBrowserCompactToolbar: ToolbarContent {
    let box: StorageBox
    @Bindable var browser: BrowserModel
    let appModel: AppModel
    let ui: FileBrowserUI

    private var selectedFileCount: Int {
        browser.selectedItems.count { !$0.isDirectory }
    }

    var body: some ToolbarContent {
        if ui.isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") {
                    ui.isSelecting = false
                    browser.selection = []
                }
            }

            ToolbarItemGroup(placement: .bottomBar) {
                Button("Download", systemImage: "square.and.arrow.down") {
                    guard let folder = appModel.resolveDownloadFolder() else { return }
                    browser.download(browser.selectedItems, to: folder)
                    ui.isSelecting = false
                    browser.selection = []
                }
                .disabled(selectedFileCount == 0)

                Spacer()

                Button("Delete", systemImage: "trash", role: .destructive) {
                    ui.deleteTargets = browser.selectedItems
                }
                .disabled(browser.selection.isEmpty)
            }
        } else {
            if !browser.path.isRoot {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Enclosing Folder", systemImage: "chevron.left") { browser.goUp() }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("New Folder…", systemImage: "folder.badge.plus") { ui.showingNewFolder = true }
                    Divider()
                    Button("Upload Files…", systemImage: "doc") {
                        beginUpload(browser: browser, ui: ui, kind: .files)
                    }
                    Button("Upload Folder…", systemImage: "folder") {
                        beginUpload(browser: browser, ui: ui, kind: .folder)
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Select…", systemImage: "checkmark.circle") { ui.isSelecting = true }

                    Picker("View", selection: Binding(
                        get: { browser.listingLayout },
                        set: { browser.setLayout($0) }
                    )) {
                        ForEach(ListingLayout.allCases) { layout in
                            Label(layout.title, systemImage: layout.symbolName).tag(layout)
                        }
                    }
                    .pickerStyle(.inline)

                    Divider()

                    FileBrowserOptionsMenu(box: box, browser: browser, appModel: appModel)

                    Divider()

                    Button("Go to Folder…", systemImage: "arrow.turn.down.right") {
                        ui.showingGoToFolder = true
                    }
                    Button(
                        appModel.transfers.activeCount > 0
                            ? "Transfers (\(appModel.transfers.activeCount))"
                            : "Transfers",
                        systemImage: "list.bullet.rectangle"
                    ) {
                        appModel.showsTransfersInspector = true
                    }
                    Button("Settings…", systemImage: "gear") { appModel.showsSettings = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
    }
}

#endif

// Shared between the macOS toolbar popover and the iOS "more" menu.
private struct FileBrowserOptionsMenu: View {
    let box: StorageBox
    @Bindable var browser: BrowserModel
    let appModel: AppModel

    var body: some View {
        #if os(macOS)
        Menu {
            options
        } label: {
            Label("View Options", systemImage: "line.3.horizontal.decrease.circle")
        }
        .help("Search, sort, and view options")
        #else
        options
        #endif
    }

    @ViewBuilder
    private var options: some View {
        #if os(macOS)
        Picker("Search", selection: $browser.searchScope) {
            ForEach(SearchScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        #endif
        Picker("Kind", selection: $browser.kindFilter) {
            ForEach(KindCategory.allCases) { category in
                Label(category.title, systemImage: category.symbolName).tag(category)
            }
        }
        .modifier(SubmenuPickerStyle())
        Divider()
        Picker("Sort By", selection: Binding(
            get: { browser.sortField },
            set: { browser.applySort(field: $0, reversed: browser.sortReversed) }
        )) {
            ForEach(SortField.allCases) { field in
                Text(field.title).tag(field)
            }
        }
        .modifier(SubmenuPickerStyle())
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
    }
}

// Inside an iOS menu a plain Picker flattens into the menu; .menu style folds it into a
// submenu row instead, which keeps the whole thing to one screen.
private struct SubmenuPickerStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content
        #else
        content.pickerStyle(.menu)
        #endif
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
                    .modifier(PathCrumbStyle())
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

private struct PathCrumbStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content.buttonStyle(.accessoryBar)
        #else
        content
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(Color.accentColor)
        #endif
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
