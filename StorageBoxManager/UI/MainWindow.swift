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
                    .id(box.id) // forces a fresh view per box, otherwise switching mid-load gets weird
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
                Label("No Box Set Up Yet", systemImage: "externaldrive.badge.plus")
            } description: {
                Text("Add your storage boxes and give each one a name you'll recognize.")
            }
        } else {
            ContentUnavailableView(
                "No Box Selected",
                systemImage: "sidebar.left",
                description: Text("Choose a box on the left to see its files.")
            )
        }
    }
}
