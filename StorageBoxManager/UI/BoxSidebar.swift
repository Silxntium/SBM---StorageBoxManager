import SwiftUI

struct BoxSidebar: View {
    @Environment(AppModel.self) private var model

    @State private var renamingID: StorageBox.ID?
    @State private var draftName = ""
    @State private var boxPendingRemoval: StorageBox?
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        @Bindable var model = model

        Group {
            if model.store.boxes.isEmpty {
                emptyState
            } else {
                boxList
            }
        }
        .navigationTitle("Boxes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Box", systemImage: "plus") {
                    model.boxEditor = .new
                }
                .help("Add a storage box")
            }
        }
        .confirmationDialog(
            "Remove \"\(boxPendingRemoval?.resolvedName ?? "")\"?",
            isPresented: Binding(
                get: { boxPendingRemoval != nil },
                set: { if !$0 { boxPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let box = boxPendingRemoval {
                    if model.selectedBoxID == box.id { model.selectedBoxID = nil }
                    model.store.remove(box)
                    model.favorites.prune(validBoxIDs: Set(model.store.boxes.map(\.id)))
                    if model.selectedBoxID == nil {
                        model.selectedBoxID = model.store.boxes.first?.id
                    }
                }
                boxPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { boxPendingRemoval = nil }
        } message: {
            Text("This only removes the box from this app. Nothing is deleted on the server.")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Boxes", systemImage: "externaldrive")
        } description: {
            Text("Add a storage box to start browsing files.")
        } actions: {
            Button("Add Box") {
                model.boxEditor = .new
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var boxList: some View {
        @Bindable var model = model

        return List(selection: $model.selectedBoxID) {
            Section("Boxes") {
                ForEach(model.store.boxes) { box in
                    row(for: box)
                        .tag(box.id)
                }
                .onMove { model.store.move(fromOffsets: $0, toOffset: $1) }
            }

            if !model.favorites.favorites.isEmpty {
                Section("Favorites") {
                    ForEach(model.favorites.favorites) { favorite in
                        favoriteRow(favorite)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .contextMenu(forSelectionType: StorageBox.ID.self) { ids in
            if ids.count == 1, let id = ids.first, let box = model.store.boxes.first(where: { $0.id == id }) {
                Button("Rename") { beginRename(box) }
                Button("Edit…") { model.boxEditor = .existing(box.id) }
                Divider()
                Button("Remove…", role: .destructive) { boxPendingRemoval = box }
            }
        }
        .onDeleteCommand {
            if let box = model.selectedBox {
                boxPendingRemoval = box
            }
        }
    }

    @ViewBuilder
    private func row(for box: StorageBox) -> some View {
        HStack(spacing: 10) {
            BoxIconView(symbolName: box.symbolName, tint: box.tint, size: 28)

            if renamingID == box.id {
                TextField("Name", text: $draftName)
                    .textFieldStyle(.plain)
                    .focused($renameFieldFocused)
                    .onSubmit { commitRename(for: box) }
                    .onExitCommand { renamingID = nil }
                    // clicking away also commits (not just enter) - don't want to silently lose the edit
                    .onChange(of: renameFieldFocused) { _, focused in
                        if !focused, renamingID == box.id { commitRename(for: box) }
                    }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(box.resolvedName)
                        .font(.body)
                        .lineLimit(1)
                    Text(box.host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Rename") { beginRename(box) }
            Button("Edit…") { model.boxEditor = .existing(box.id) }
            Divider()
            Button("Remove…", role: .destructive) { boxPendingRemoval = box }
        }
    }

    private func favoriteRow(_ favorite: FolderFavorite) -> some View {
        let box = model.store.boxes.first { $0.id == favorite.boxID }
        return Button {
            model.openFavorite(favorite)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(favorite.title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(box?.resolvedName ?? favorite.path.displayPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove from Favorites", role: .destructive) {
                model.favorites.remove(favorite)
            }
        }
        .help(favorite.path.displayPath)
    }

    private func beginRename(_ box: StorageBox) {
        draftName = box.displayName
        renamingID = box.id
        renameFieldFocused = true
    }

    private func commitRename(for box: StorageBox) {
        model.store.rename(box, to: draftName)
        renamingID = nil
    }
}
