import SwiftUI

struct GeneralSettingsView: View {
    @State private var folderURL = DownloadFolderStore.resolve()
    @AppStorage("foldersFirst") private var foldersFirst = true
    @AppStorage("relativeDates") private var relativeDates = true

    var body: some View {
        Form {
            Section {
                LabeledContent("Save downloads to") {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue)
                            .symbolRenderingMode(.hierarchical)
                        Text(folderLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(folderURL == nil ? .secondary : .primary)
                        Button("Choose…") { chooseFolder() }
                    }
                }
            } footer: {
                Text("Files you download from a box land in this folder. You can change it at any time.")
            }

            Section {
                Toggle("Keep folders on top", isOn: $foldersFirst)
                Toggle("Use relative dates", isOn: $relativeDates)
            } header: {
                Text("Browser")
            } footer: {
                Text("These are defaults for new windows. A browser that's already open keeps the last choice you made there.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 280)
    }

    private var folderLabel: String {
        folderURL?.path(percentEncoded: false) ?? "Ask each time"
    }

    private func chooseFolder() {
        if let url = DownloadFolderStore.promptForFolder() {
            folderURL = url
        }
    }
}

#Preview {
    GeneralSettingsView()
}
