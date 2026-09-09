import AppKit
import SwiftUI

struct FolderSkeletonView: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Name")
                Spacer()
                Text("Size").frame(width: 80, alignment: .trailing)
                Text("Modified").frame(width: 140, alignment: .trailing)
                Text("Kind").frame(width: 100, alignment: .trailing)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 7)

            Divider()

            ForEach(0..<10, id: \.self) { index in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: 16, height: 16)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: barWidth(for: index), height: 10)
                    Spacer()
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: 48, height: 8)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: 96, height: 8)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: 64, height: 8)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                Divider().padding(.leading, 46)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading folder")
    }

    private func barWidth(for index: Int) -> CGFloat {
        let widths: [CGFloat] = [168, 124, 196, 88, 152, 176, 108, 140, 200, 92]
        return widths[index % widths.count]
    }
}

struct BrowserStatusBar: View {
    let summary: String
    let quotaSummary: String?
    let hiddenItemCount: Int
    let isBusy: Bool

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .opacity(isBusy ? 1 : 0)
            Text(summary)
                .foregroundStyle(.secondary)
            Spacer()
            if hiddenItemCount > 0 {
                Text("\(hiddenItemCount) hidden")
                    .foregroundStyle(.tertiary)
            }
            if let quotaSummary {
                Text(quotaSummary)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
    }
}

struct FileIconGrid: View {
    let items: [RemoteItem]
    let box: StorageBox
    let query: String
    let relativeDates: Bool
    @Binding var selection: Set<RemoteItem.ID>
    let backend: (any StorageBackend)?
    let onOpen: (RemoteItem) -> Void
    let onPreview: (RemoteItem) -> Void

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 128), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { item in
                    icon(for: item)
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onKeyPress(.space) {
            if let file = items.first(where: { selection.contains($0.id) && !$0.isDirectory }) {
                onPreview(file)
                return .handled
            }
            return .ignored
        }
    }

    private func icon(for item: RemoteItem) -> some View {
        let isSelected = selection.contains(item.id)
        return VStack(spacing: 6) {
            Image(systemName: item.symbolName)
                .font(.system(size: 32, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(item.isDirectory ? box.tint.color : Color.secondary)
                .frame(width: 56, height: 44)
            Text(item.highlightedName(matching: query))
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 96)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .frame(width: 104, height: 96)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(count: 2) { onOpen(item) }
        .onTapGesture { select(item) }
        .contextMenu {
            if item.isDirectory {
                Button("Open") { onOpen(item) }
            } else {
                Button("Quick Look") { onPreview(item) }
            }
        }
        .draggableRemoteFile(item, backend: backend)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(item.formattedModified(relative: relativeDates))
    }

    private func select(_ item: RemoteItem) {
        if NSEvent.modifierFlags.contains(.shift), let anchor = selection.first,
           let from = items.firstIndex(where: { $0.id == anchor }),
           let to = items.firstIndex(where: { $0.id == item.id }) {
            let range = items[min(from, to)...max(from, to)]
            selection = Set(range.map(\.id))
        } else if NSEvent.modifierFlags.contains(.command) {
            if selection.contains(item.id) {
                selection.remove(item.id)
            } else {
                selection.insert(item.id)
            }
        } else {
            selection = [item.id]
        }
    }
}

struct FileItemActions {
    var open: (RemoteItem) -> Void = { _ in }
    var preview: (RemoteItem) -> Void = { _ in }
    var getInfo: ([RemoteItem]) -> Void = { _ in }
    var rename: (RemoteItem) -> Void = { _ in }
    var duplicate: (RemoteItem) -> Void = { _ in }
    var download: ([RemoteItem]) -> Void = { _ in }
    var downloadAndOpen: (RemoteItem) -> Void = { _ in }
    var delete: ([RemoteItem]) -> Void = { _ in }
    var reveal: (RemoteItem) -> Void = { _ in }
    var toggleFavorite: (RemoteItem) -> Void = { _ in }
    var isFavorite: (RemoteItem) -> Bool = { _ in false }
    var newFolder: () -> Void = {}
    var upload: () -> Void = {}
    var refresh: () -> Void = {}
    var copyName: (RemoteItem) -> Void = { _ in }
    var copyPath: (RemoteItem) -> Void = { _ in }
    var isDeepSearch = false
}

struct FileTableView: View {
    let items: [RemoteItem]
    let box: StorageBox
    let query: String
    let relativeDates: Bool
    let showLocation: Bool
    @Binding var selection: Set<RemoteItem.ID>
    @Binding var sortOrder: [KeyPathComparator<RemoteItem>]
    let backend: (any StorageBackend)?
    let canQuickLook: Bool
    let actions: FileItemActions

    var body: some View {
        Table(items, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { item in
                FileNameCell(item: item, tint: box.tint.color, query: query, backend: backend)
            }
            .width(min: 140, ideal: 280)

            TableColumn("Size", value: \.sortSize) { item in
                Text(item.formattedSize)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 64, ideal: 88)

            TableColumn("Modified", value: \.sortDate) { item in
                Text(item.formattedModified(relative: relativeDates))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 96, ideal: 150)

            TableColumn("Kind", value: \.kindDescription) { item in
                Text(item.kindDescription)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 72, ideal: 110)

            TableColumn("Where") { item in
                Text(showLocation ? item.enclosingFolder : "—")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 160)
        }
        .tableStyle(.inset)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onKeyPress(.space) {
            guard canQuickLook else { return .ignored }
            if let file = items.first(where: { selection.contains($0.id) && !$0.isDirectory }) {
                actions.preview(file)
                return .handled
            }
            return .ignored
        }
        .contextMenu(forSelectionType: RemoteItem.ID.self) { ids in
            FileSelectionMenu(items: items.filter { ids.contains($0.id) }, actions: actions)
        } primaryAction: { ids in
            if let first = ids.first, let item = items.first(where: { $0.id == first }) {
                actions.open(item)
            }
        }
    }
}

private struct FileNameCell: View {
    let item: RemoteItem
    let tint: Color
    let query: String
    let backend: (any StorageBackend)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.symbolName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(item.isDirectory ? tint : Color.secondary)
                .frame(width: 18)
            Text(item.highlightedName(matching: query))
                .lineLimit(1)
        }
        .draggableRemoteFile(item, backend: backend)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name)
        .accessibilityValue(item.isDirectory ? "Folder" : item.kindDescription)
    }
}

private struct FileSelectionMenu: View {
    let items: [RemoteItem]
    let actions: FileItemActions

    var body: some View {
        if items.count == 1, let item = items.first {
            singleItemMenu(item)
        } else if !items.isEmpty {
            Button("Get Info") { actions.getInfo(items) }
            Divider()
        }
        if items.contains(where: { !$0.isDirectory }) {
            Button("Download") { actions.download(items) }
        }
        if !items.isEmpty {
            Button("Delete…", role: .destructive) { actions.delete(items) }
            Divider()
        }
        Button("New Folder…") { actions.newFolder() }
        Button("Upload…") { actions.upload() }
        Button("Refresh") { actions.refresh() }
    }

    @ViewBuilder
    private func singleItemMenu(_ item: RemoteItem) -> some View {
        if item.isDirectory {
            Button("Open") { actions.open(item) }
            Button(actions.isFavorite(item) ? "Remove from Favorites" : "Add to Favorites") {
                actions.toggleFavorite(item)
            }
        } else {
            Button("Quick Look") { actions.preview(item) }
            Button("Download and Open") { actions.downloadAndOpen(item) }
        }
        if actions.isDeepSearch {
            Button("Show Enclosing Folder") { actions.reveal(item) }
        }
        Button("Get Info") { actions.getInfo([item]) }
        Button("Rename…") { actions.rename(item) }
        Button("Duplicate") { actions.duplicate(item) }
        Button("Copy Name") { actions.copyName(item) }
        Button("Copy Path") { actions.copyPath(item) }
        Divider()
    }
}
