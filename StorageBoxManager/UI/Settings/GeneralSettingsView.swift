import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage("foldersFirst") private var foldersFirst = true
    @AppStorage("relativeDates") private var relativeDates = true

    #if os(macOS)
    @State private var folderURL = DownloadFolderStore.resolve()
    #else
    @Environment(\.dismiss) private var dismiss
    #endif

    var body: some View {
        Form {
            Section {
                downloadLocation
            } footer: {
                #if os(macOS)
                Text("Files you download from a box land in this folder. You can change it at any time.")
                #else
                Text("Downloads land in this app's folder. Open the Files app and look under \"On My iPhone › Storage Boxes\" to get at them from anywhere else.")
                #endif
            }

            Section {
                Toggle("Keep folders on top", isOn: $foldersFirst)
                Toggle("Use relative dates", isOn: $relativeDates)
            } header: {
                Text("Browser")
            } footer: {
                #if os(macOS)
                Text("These are defaults for new windows. A browser that's already open keeps the last choice you made there.")
                #else
                Text("These are defaults for boxes you open next. A browser that's already open keeps the last choice you made there.")
                #endif
            }
        }
        .formStyle(.grouped)
        .sheetFrame(width: 520, height: 280)
        #if !os(macOS)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        #endif
    }

    @ViewBuilder
    private var downloadLocation: some View {
        #if os(macOS)
        LabeledContent("Save downloads to") {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                    .symbolRenderingMode(.hierarchical)
                Text(folderURL?.path(percentEncoded: false) ?? "Ask each time")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(folderURL == nil ? .secondary : .primary)
                Button("Choose…") { chooseFolder() }
            }
        }
        #else
        // iOS apps can only write into their own container, so there is nothing to choose
        LabeledContent("Save downloads to") {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                    .symbolRenderingMode(.hierarchical)
                Text("Storage Boxes")
                    .foregroundStyle(.secondary)
            }
        }
        #endif
    }

    #if os(macOS)
    private func chooseFolder() {
        if let url = DownloadFolderStore.promptForFolder() {
            folderURL = url
        }
    }
    #endif
}

#Preview {
    GeneralSettingsView()
}
