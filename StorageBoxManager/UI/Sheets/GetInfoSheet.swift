import AppKit
import SwiftUI

struct GetInfoSheet: View {
    let items: [RemoteItem]
    let relativeDates: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if items.count == 1, let item = items.first {
                    singleItem(item)
                } else {
                    multipleItems
                }
            }
            .formStyle(.grouped)
            .navigationTitle(items.count == 1 ? "Info" : "\(items.count) Items")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 360, idealWidth: 400, minHeight: 320)
    }

    @ViewBuilder
    private func singleItem(_ item: RemoteItem) -> some View {
        Section {
            LabeledContent("Name", value: item.name)
            LabeledContent("Kind", value: item.kindDescription)
            LabeledContent("Size", value: item.formattedSize)
            LabeledContent("Modified", value: item.formattedModified(relative: relativeDates))
            LabeledContent("Where", value: item.path.parent?.displayPath ?? "/")
        }

        Section("Path") {
            Text(item.path.displayPath)
                .textSelection(.enabled)
                .font(.body.monospaced())
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.path.displayPath, forType: .string)
            }
        }

        if let type = item.contentType, !type.isEmpty {
            Section("Server") {
                LabeledContent("Type", value: type)
                if let etag = item.etag, !etag.isEmpty {
                    LabeledContent("ETag", value: etag)
                }
            }
        }
    }

    private var multipleItems: some View {
        Section {
            LabeledContent("Items", value: "\(items.count)")
            LabeledContent("Folders", value: "\(items.filter(\.isDirectory).count)")
            LabeledContent("Files", value: "\(items.filter { !$0.isDirectory }.count)")
            LabeledContent(
                "Size",
                value: items.compactMap(\.size).reduce(0, +).formatted(.byteCount(style: .file))
            )
        }
    }
}

struct GoToFolderSheet: View {
    let currentPath: String
    let onGo: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Path", text: $text, prompt: Text("/Photos/2024"))
                        .focused($fieldFocused)
                        .onSubmit(go)
                } footer: {
                    Text("Enter a path starting from the root of this box, like /Documents/Scans.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Go to Folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Go", action: go)
                        .keyboardShortcut(.defaultAction)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(width: 420, height: 190)
        .onAppear {
            text = currentPath
            fieldFocused = true
        }
    }

    private func go() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onGo(trimmed)
        dismiss()
    }
}
