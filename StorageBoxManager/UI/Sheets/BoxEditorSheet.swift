import SwiftUI

struct BoxEditorSheet: View {
    let box: StorageBox?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var host = ""
    @State private var username = ""
    @State private var password = ""
    @State private var tint: BoxTint = .blue
    @State private var symbolName = "externaldrive.fill"
    @State private var test: TestState = .idle
    @State private var saveError: String?

    private enum TestState: Equatable {
        case idle
        case running
        case succeeded
        case failed(String)
    }

    private var isEditing: Bool { box != nil }

    private var canSave: Bool {
        !host.isEmpty && !username.isEmpty && (isEditing || !password.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $displayName, prompt: Text("e.g. Photos"))
                    LabeledContent("Appearance") {
                        HStack(spacing: 12) {
                            symbolPicker
                            tintPicker
                        }
                    }
                } header: {
                    Text("Display")
                } footer: {
                    Text("This name is only used in this app — the server keeps its own hostname.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Connection") {
                    TextField("Server", text: $host, prompt: Text("u123456.your-storagebox.de"))
                        .onChange(of: host) { _, new in
                            let normalized = AppModel.normalizeHost(new)
                            if normalized != new { host = normalized }
                            if username.isEmpty {
                                username = AppModel.suggestedUsername(forHost: normalized)
                            }
                        }
                    TextField("Username", text: $username, prompt: Text("u123456"))
                    SecureField(
                        "Password",
                        text: $password,
                        prompt: Text(isEditing ? "leave unchanged" : "Password")
                    )
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack(spacing: 12) {
                testStatusView
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Test Connection") { runTest() }
                    .disabled(!canSave || test == .running)
                Button(isEditing ? "Save" : "Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(width: 520)
        .onAppear(perform: loadExisting)
        .alert("Couldn't Save", isPresented: .constant(saveError != nil)) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - Pieces

    private var symbolPicker: some View {
        Picker("Icon", selection: $symbolName) {
            ForEach(StorageBox.symbolChoices, id: \.self) { name in
                Image(systemName: name).tag(name)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 70)
    }

    private var tintPicker: some View {
        HStack(spacing: 6) {
            ForEach(BoxTint.allCases) { option in
                Circle()
                    .fill(option.color)
                    .frame(width: 16, height: 16)
                    .overlay {
                        Circle()
                            .strokeBorder(.primary, lineWidth: tint == option ? 2 : 0)
                    }
                    .onTapGesture { tint = option }
                    .help(option.label)
                    .accessibilityLabel(option.label)
            }
        }
    }

    @ViewBuilder
    private var testStatusView: some View {
        switch test {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Testing…").foregroundStyle(.secondary)
            }
        case .succeeded:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .lineLimit(2)
                .help(message)
        }
    }

    // MARK: - Actions

    private func loadExisting() {
        guard let box else { return }
        displayName = box.displayName
        host = box.host
        username = box.username
        tint = box.tint
        symbolName = box.symbolName
    }

    // freshly typed password, or fall back to whatever's stored if editing w/o touching the field
    private func effectivePassword() throws -> String {
        if !password.isEmpty { return password }
        guard let box else { return "" }
        return try KeychainStore.password(host: box.host, account: box.username) ?? ""
    }

    private func runTest() {
        test = .running
        let candidate = StorageBox(
            id: box?.id ?? UUID(),
            displayName: displayName,
            host: host,
            username: username,
            tint: tint,
            symbolName: symbolName
        )
        Task {
            do {
                let backend = try WebDAVBackend(box: candidate, password: try effectivePassword())
                try await backend.probe()
                test = .succeeded
            } catch {
                test = .failed(Self.message(for: error))
            }
        }
    }

    private func save() {
        let updated = StorageBox(
            id: box?.id ?? UUID(),
            displayName: displayName,
            host: host,
            username: username,
            tint: tint,
            symbolName: symbolName
        )
        do {
            if !password.isEmpty {
                try KeychainStore.setPassword(password, host: host, account: username)
            }
            // host/username changed -> that's part of the keychain key, so move the entry over
            if let box, box.host != host || box.username != username {
                try? KeychainStore.deletePassword(host: box.host, account: box.username)
                if password.isEmpty {
                    let carried = try KeychainStore.password(host: box.host, account: box.username) ?? ""
                    if !carried.isEmpty {
                        try KeychainStore.setPassword(carried, host: host, account: username)
                    }
                }
            }

            if box == nil {
                model.store.add(updated)
                model.selectedBoxID = updated.id
            } else {
                model.store.update(updated)
            }
            dismiss()
        } catch {
            saveError = Self.message(for: error)
        }
    }

    private static func message(for error: any Error) -> String {
        if let backendError = error as? BackendError {
            let suggestion = backendError.recoverySuggestion.map { " \($0)" } ?? ""
            return (backendError.errorDescription ?? "Unknown error") + suggestion
        }
        return error.localizedDescription
    }
}
