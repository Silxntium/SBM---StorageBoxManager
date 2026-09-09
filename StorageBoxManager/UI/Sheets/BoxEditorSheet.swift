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
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, host, username, password
    }

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
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        BoxIconView(symbolName: symbolName, tint: tint, size: 56)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)

                    TextField("Name", text: $displayName, prompt: Text("e.g. Photos"))
                        .focused($focusedField, equals: .name)

                    LabeledContent("Icon") {
                        symbolGrid
                    }

                    LabeledContent("Color") {
                        tintPicker
                    }
                } header: {
                    Text("Display")
                } footer: {
                    Text("This name is only used in this app — the server keeps its own hostname.")
                }

                Section {
                    TextField("Server", text: $host, prompt: Text("u123456.your-storagebox.de"))
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .host)
                        .onChange(of: host) { _, new in
                            let normalized = AppModel.normalizeHost(new)
                            if normalized != new { host = normalized }
                            if username.isEmpty {
                                username = AppModel.suggestedUsername(forHost: normalized)
                            }
                        }

                    TextField("Username", text: $username, prompt: Text("u123456"))
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)

                    SecureField(
                        "Password",
                        text: $password,
                        prompt: Text(isEditing ? "Leave blank to keep current" : "Password")
                    )
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                } header: {
                    Text("Connection")
                } footer: {
                    testStatusView
                }

                Section {
                    Button {
                        runTest()
                    } label: {
                        if test == .running {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Testing…")
                            }
                        } else {
                            Label("Test Connection", systemImage: "bolt.horizontal")
                        }
                    }
                    .disabled(!canSave || test == .running)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Box" : "Add Box")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSave)
                }
            }
        }
        .frame(minWidth: 460, idealWidth: 500, minHeight: 520)
        .onAppear {
            loadExisting()
            focusedField = isEditing ? .name : .host
        }
        .alert("Couldn't Save", isPresented: saveErrorPresented) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private var saveErrorPresented: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )
    }

    private var symbolGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
            ForEach(StorageBox.symbolChoices, id: \.self) { name in
                Button {
                    symbolName = name
                } label: {
                    Image(systemName: name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(symbolName == name ? tint.color : .secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            symbolName == name ? tint.color.opacity(0.18) : Color.secondary.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .help(name)
                .accessibilityLabel(name)
                .accessibilityAddTraits(symbolName == name ? .isSelected : [])
            }
        }
        .frame(maxWidth: 220)
    }

    private var tintPicker: some View {
        HStack(spacing: 8) {
            ForEach(BoxTint.allCases) { option in
                Button {
                    tint = option
                } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(0.9), lineWidth: tint == option ? 1.5 : 0)
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(.primary.opacity(tint == option ? 0.55 : 0.15), lineWidth: tint == option ? 2 : 1)
                                .padding(-3)
                        }
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
                .help(option.label)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(tint == option ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private var testStatusView: some View {
        switch test {
        case .idle:
            EmptyView()
        case .running:
            Text("Checking the server…")
        case .succeeded:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .lineLimit(3)
                .help(message)
        }
    }

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
                if password.isEmpty {
                    let carried = try KeychainStore.password(host: box.host, account: box.username) ?? ""
                    if !carried.isEmpty {
                        try KeychainStore.setPassword(carried, host: host, account: username)
                    }
                }
                try? KeychainStore.deletePassword(host: box.host, account: box.username)
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

#Preview("Add") {
    BoxEditorSheet(box: nil)
        .environment(AppModel())
}
