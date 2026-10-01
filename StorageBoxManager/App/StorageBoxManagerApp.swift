import SwiftUI

@main
struct StorageBoxManagerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environment(model)
                .focusedSceneValue(\.appModel, model)
                .modifier(WindowSizing())
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 720)
        #endif
        .commands {
            AppCommands()
        }

        // iOS has no Settings scene - the same view is a sheet off the browser's More menu
        #if os(macOS)
        Settings {
            GeneralSettingsView()
        }
        #endif
    }
}

private struct WindowSizing: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content.frame(minWidth: 840, minHeight: 520)
        #else
        content
        #endif
    }
}
