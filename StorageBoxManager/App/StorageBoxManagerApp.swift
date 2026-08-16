import SwiftUI

@main
struct StorageBoxManagerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environment(model)
        }
        .defaultSize(width: 1120, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
