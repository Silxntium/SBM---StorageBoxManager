import SwiftUI

struct MainWindow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            BoxSidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            if let box = model.selectedBox {
                FileBrowser(box: box)
                    // A fresh browser per box: identity here is what stops one box's folder
                    // listing from bleeding into the next one's view during loading.
                    .id(box.id)
            } else {
                NoBoxSelectedView()
            }
        }
    }
}

private struct NoBoxSelectedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.store.boxes.isEmpty {
            ContentUnavailableView {
                Label("Noch keine Box eingerichtet", systemImage: "externaldrive.badge.plus")
            } description: {
                Text("Füge deine Hetzner Storage Boxen hinzu und gib jeder einen Namen, an dem du sie wiedererkennst.")
            }
        } else {
            ContentUnavailableView(
                "Keine Box ausgewählt",
                systemImage: "sidebar.left",
                description: Text("Wähle links eine Box aus, um ihre Dateien zu sehen.")
            )
        }
    }
}
