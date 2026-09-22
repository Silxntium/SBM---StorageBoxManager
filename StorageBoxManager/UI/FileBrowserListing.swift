import SwiftUI

struct FileBrowserListing: View {
    let box: StorageBox
    @Bindable var browser: BrowserModel
    let ui: FileBrowserUI
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ZStack {
            listing
                .accessibilityHidden(showsCover)
                .allowsHitTesting(!showsCover)

            if let message = staleFailureMessage, !showsCover {
                VStack(spacing: 0) {
                    FileBrowserStaleFailureBanner(message: message, onRetry: { browser.refresh() })
                    Spacer(minLength: 0)
                }
            }

            if showsSkeleton {
                FolderSkeletonView()
                    .background(Color.platformWindowBackground)
            } else if let message = failureMessage {
                FileBrowserFailureView(message: message, onRoot: { browser.navigate(to: .root) }, onRetry: { browser.refresh() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.platformWindowBackground)
            } else if showsSearchEmpty {
                ContentUnavailableView.search(text: emptySearchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.platformWindowBackground)
            } else if showsEmptyFolder {
                FileBrowserEmptyFolder(browser: browser, ui: ui)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.platformWindowBackground)
            }
        }
    }

    @ViewBuilder
    private var listing: some View {
        if browser.listingLayout == .icons {
            iconGrid
        } else {
            rows
        }
    }

    private var showsSkeleton: Bool {
        switch browser.state {
        case .idle: true
        case .loading: browser.items.isEmpty
        case .loaded, .failed: false
        }
    }

    private var showsCover: Bool {
        showsSkeleton || failureMessage != nil || showsSearchEmpty || showsEmptyFolder
    }

    private var failureMessage: String? {
        if case .failed(let message) = browser.state, browser.items.isEmpty {
            return message
        }
        return nil
    }

    private var staleFailureMessage: String? {
        if case .failed(let message) = browser.state, !browser.items.isEmpty {
            return message
        }
        return nil
    }

    private var showsSearchEmpty: Bool {
        browser.displayedItems.isEmpty
            && (!normalizedQuery.isEmpty || browser.kindFilter != .all || browser.isDeepSearchActive)
    }

    private var showsEmptyFolder: Bool {
        normalizedQuery.isEmpty && browser.kindFilter == .all && browser.visibleItems.isEmpty
    }

    private var emptySearchText: String {
        normalizedQuery.isEmpty ? browser.kindFilter.title : browser.searchText
    }

    private var normalizedQuery: String {
        browser.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var iconGrid: some View {
        FileIconGrid(
            items: browser.displayedItems,
            box: box,
            query: browser.searchText,
            relativeDates: browser.usesRelativeDates,
            isSelecting: ui.isSelecting,
            selection: $browser.selection,
            backend: browser.storageBackend,
            onOpen: { browser.open($0) },
            onPreview: { browser.preview($0) }
        )
    }

    @ViewBuilder
    private var rows: some View {
        #if os(macOS)
        FileTableView(
            items: browser.displayedItems,
            box: box,
            query: browser.searchText,
            relativeDates: browser.usesRelativeDates,
            showLocation: browser.isDeepSearchActive,
            selection: $browser.selection,
            sortOrder: $browser.sortOrder,
            backend: browser.storageBackend,
            canQuickLook: browser.canQuickLook,
            actions: FileBrowserActions.itemActions(box: box, browser: browser, ui: ui, appModel: appModel)
        )
        #else
        FileCompactList(
            items: browser.displayedItems,
            box: box,
            query: browser.searchText,
            relativeDates: browser.usesRelativeDates,
            showLocation: browser.isDeepSearchActive,
            isSelecting: ui.isSelecting,
            selection: $browser.selection,
            backend: browser.storageBackend,
            actions: FileBrowserActions.itemActions(box: box, browser: browser, ui: ui, appModel: appModel)
        )
        #endif
    }
}

private struct FileBrowserStaleFailureBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Try Again", action: onRetry)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct FileBrowserFailureView: View {
    let message: String
    let onRoot: () -> Void
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't Load Folder", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Go to Root", action: onRoot)
            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct FileBrowserEmptyFolder: View {
    @Bindable var browser: BrowserModel
    let ui: FileBrowserUI

    var body: some View {
        ContentUnavailableView {
            Label(
                browser.hiddenItemCount > 0 ? "Nothing Visible Here" : "This Folder Is Empty",
                systemImage: "folder"
            )
        } description: {
            Text(
                browser.hiddenItemCount > 0
                    ? hiddenItemsHint
                    : uploadHint
            )
        } actions: {
            if browser.hiddenItemCount > 0 {
                Button("Show Hidden Files") { browser.showsHiddenFiles = true }
            }
            Button("Upload…") { beginUpload(browser: browser, ui: ui) }
            Button("New Folder") { ui.showingNewFolder = true }
        }
    }

    private var hiddenItemsHint: String {
        #if os(macOS)
        String(localized: "\(browser.hiddenItemCount) hidden items. Show them with ⌘⇧.")
        #else
        String(localized: "\(browser.hiddenItemCount) hidden items. Show them from the More menu.")
        #endif
    }

    private var uploadHint: String {
        #if os(macOS)
        String(localized: "Drag files or folders here to upload them, or use Upload in the toolbar.")
        #else
        String(localized: "Upload files or folders with the + button above.")
        #endif
    }
}
