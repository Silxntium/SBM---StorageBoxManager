import SwiftUI

struct MainWindow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        layout
            .sheet(item: $model.boxEditor) { editor in
                switch editor {
                case .new:
                    BoxEditorSheet(box: nil)
                case .existing(let id):
                    BoxEditorSheet(box: model.store.boxes.first { $0.id == id })
                }
            }
            .modifier(CompactPresentations())
            .onChange(of: model.transfers.transfers.count) { oldCount, newCount in
                if newCount > oldCount, model.transfers.transfers.last?.kind != .preview {
                    model.showsTransfersInspector = true
                }
            }
    }

    @ViewBuilder
    private var layout: some View {
        #if os(macOS)
        macLayout
        #else
        // collapses to a push navigation on iPhone and stays a sidebar on iPad
        NavigationSplitView {
            BoxSidebar()
        } detail: {
            detailColumn
        }
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private var macLayout: some View {
        HStack(spacing: 0) {
            if model.showsSidebar {
                NavigationStack {
                    BoxSidebar()
                }
                .frame(width: 248)
                .frame(maxHeight: .infinity)

                Divider()
            }

            NavigationStack {
                detailColumn
            }
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)

            if model.showsTransfersInspector {
                Divider()
                TransfersPanel()
                    .frame(width: 320)
            }
        }
    }
    #endif

    @ViewBuilder
    private var detailColumn: some View {
        if let box = model.selectedBox {
            FileBrowser(box: box)
                .id(box.id)
        } else {
            NoBoxSelectedView()
        }
    }
}

// On macOS the transfers list is a side panel, settings live in the Settings scene, and Quick Look
// floats in its own window. None of those exist on iOS, so all three become sheets.
private struct CompactPresentations: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        #if os(macOS)
        content
        #else
        @Bindable var model = model

        content
            .sheet(isPresented: $model.showsTransfersInspector) {
                TransfersPanel()
            }
            .sheet(isPresented: $model.showsSettings) {
                NavigationStack {
                    GeneralSettingsView()
                }
            }
            .sheet(item: $model.previewRequest) { request in
                QuickLookSheet(request: request)
            }
        #endif
    }
}

private struct NoBoxSelectedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label(
                model.store.boxes.isEmpty ? "No Box Set Up Yet" : "No Box Selected",
                systemImage: model.store.boxes.isEmpty ? "externaldrive.badge.plus" : "sidebar.leading"
            )
        } description: {
            Text(
                model.store.boxes.isEmpty
                    ? "Add a storage box and give it a name you'll recognize."
                    : "Choose a box in the sidebar to browse its files."
            )
        } actions: {
            if model.store.boxes.isEmpty {
                Button("Add Box") {
                    model.boxEditor = .new
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

#Preview {
    MainWindow()
        .environment(AppModel())
        .frame(width: 1100, height: 700)
}
