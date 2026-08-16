import SwiftUI

/// The list of boxes — and the answer to the original problem: every row shows a name the
/// user chose, with the hostname demoted to a subtitle.
struct BoxSidebar: View {
    @Environment(AppModel.self) private var model

    @State private var editor: EditorTarget?
    @State private var renamingID: StorageBox.ID?
    @State private var draftName = ""
    @State private var boxPendingRemoval: StorageBox?
    @FocusState private var renameFieldFocused: Bool

    private enum EditorTarget: Identifiable {
        case new
        case existing(StorageBox)

        var id: String {
            switch self {
            case .new: "new"
            case .existing(let box): box.id.uuidString
            }
        }
    }

    var body: some View {
        @Bindable var model = model

        List(selection: $model.selectedBoxID) {
            ForEach(model.store.boxes) { box in
                row(for: box)
                    .tag(box.id)
            }
            .onMove { model.store.move(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.sidebar)
        .navigationTitle("Storage Boxen")
        .safeAreaInset(edge: .bottom) {
            Button {
                editor = .new
            } label: {
                Label("Box hinzufügen", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.accessoryBar)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .sheet(item: $editor) { target in
            switch target {
            case .new:
                BoxEditorSheet(box: nil)
            case .existing(let box):
                BoxEditorSheet(box: box)
            }
        }
        .confirmationDialog(
            "„\(boxPendingRemoval?.resolvedName ?? "")“ entfernen?",
            isPresented: Binding(
                get: { boxPendingRemoval != nil },
                set: { if !$0 { boxPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Entfernen", role: .destructive) {
                if let box = boxPendingRemoval {
                    if model.selectedBoxID == box.id { model.selectedBoxID = nil }
                    model.store.remove(box)
                }
                boxPendingRemoval = nil
            }
            Button("Abbrechen", role: .cancel) { boxPendingRemoval = nil }
        } message: {
            Text("Die Box wird nur aus dieser App entfernt. Auf dem Server wird nichts gelöscht.")
        }
    }

    @ViewBuilder
    private func row(for box: StorageBox) -> some View {
        HStack(spacing: 9) {
            Image(systemName: box.symbolName)
                .foregroundStyle(box.tint.color)
                .imageScale(.large)
                .frame(width: 20)

            if renamingID == box.id {
                TextField("Name", text: $draftName)
                    .textFieldStyle(.plain)
                    .focused($renameFieldFocused)
                    .onSubmit { commitRename(for: box) }
                    .onExitCommand { renamingID = nil }
                    // Losing focus commits too, so clicking elsewhere does not quietly
                    // discard what was typed.
                    .onChange(of: renameFieldFocused) { _, focused in
                        if !focused, renamingID == box.id { commitRename(for: box) }
                    }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(box.resolvedName)
                        .lineLimit(1)
                    Text(box.host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Umbenennen") { beginRename(box) }
            Button("Bearbeiten…") { editor = .existing(box) }
            Divider()
            Button("Entfernen…", role: .destructive) { boxPendingRemoval = box }
        }
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
