import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage("foldersFirst") private var foldersFirst = true
    @AppStorage("relativeDates") private var relativeDates = true
    @AppStorage(TransferQueue.deleteSourceAfterUploadKey) private var deleteSourceAfterUpload = false
    @AppStorage(TransferQueue.moveSourceToTrashKey) private var moveSourceToTrash = true
    @AppStorage(TransferQueue.removeEmptySourceFoldersKey) private var removeEmptySourceFolders = false
    @AppStorage(TransferQueue.concurrentTransferCountKey) private var concurrentTransferCount = 3
    @AppStorage(TransferQueue.uploadConflictPolicyKey) private var uploadConflictPolicy = UploadConflictPolicy.ask.rawValue

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

            Section {
                Toggle("Delete source files after upload", isOn: $deleteSourceAfterUpload)
                #if os(macOS)
                Toggle("Move to Trash instead of deleting", isOn: $moveSourceToTrash)
                    .padding(.leading)
                    .disabled(!deleteSourceAfterUpload)
                #endif
                Toggle("Remove empty source folders", isOn: $removeEmptySourceFolders)
                    .padding(.leading)
                    .disabled(!deleteSourceAfterUpload)

                Stepper(value: $concurrentTransferCount, in: 1...6) {
                    LabeledContent("Concurrent transfers", value: concurrentTransferCount.formatted())
                }

                Picker("When a file already exists", selection: $uploadConflictPolicy) {
                    ForEach(UploadConflictPolicy.allCases) { policy in
                        Text(policy.title).tag(policy.rawValue)
                    }
                }
            } header: {
                Text("Uploads")
            } footer: {
                #if os(macOS)
                Text("Before source cleanup, the app confirms the upload succeeded, verifies the remote size, and checks that the local file did not change. Trash cleanup can be undone; permanent deletion cannot.")
                #else
                Text("Before permanent source deletion, the app confirms the upload succeeded, verifies the remote size, and checks that the local file did not change. Deletion cannot be undone.")
                #endif
            }
        }
        .formStyle(.grouped)
        .sheetFrame(width: 560, height: 560)
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
