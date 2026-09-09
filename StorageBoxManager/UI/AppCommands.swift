import SwiftUI

struct AppCommands: Commands {
    @FocusedValue(\.appModel) private var model
    @FocusedValue(\.browserActions) private var browser

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Box…") {
                model?.boxEditor = .new
            }
            .keyboardShortcut("n")
            .disabled(model == nil)

            Button("New Folder…") {
                browser?.newFolder()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(browser == nil)
        }

        CommandGroup(after: .newItem) {
            Button("Upload…") {
                browser?.upload()
            }
            .keyboardShortcut("u")
            .disabled(browser == nil)

            Button("Download") {
                browser?.download()
            }
            .keyboardShortcut("s")
            .disabled(!(browser?.canDownload ?? false))

            Button("Download and Open") {
                browser?.downloadAndOpen()
            }
            .disabled(!(browser?.canDownload ?? false))

            Divider()

            Button("Duplicate") {
                browser?.duplicate()
            }
            .keyboardShortcut("d")
            .disabled(!(browser?.canDuplicate ?? false))

            Button("Quick Look") {
                browser?.quickLook()
            }
            .keyboardShortcut("y")
            .disabled(!(browser?.canQuickLook ?? false))

            Button("Get Info") {
                browser?.getInfo()
            }
            .keyboardShortcut("i")
            .disabled(!(browser?.canGetInfo ?? false))

            Divider()

            Button("Delete…") {
                browser?.deleteSelection()
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(!(browser?.canDelete ?? false))
        }

        CommandGroup(after: .textEditing) {
            Button("Find…") {
                browser?.focusSearch()
            }
            .keyboardShortcut("f")
            .disabled(browser == nil)

            Button("Select All") {
                browser?.selectAll()
            }
            .keyboardShortcut("a")
            .disabled(browser == nil)
        }

        CommandMenu("View") {
            Button("as List") { browser?.setLayout(.list) }
                .keyboardShortcut("1")
            Button("as Icons") { browser?.setLayout(.icons) }
                .keyboardShortcut("2")

            Divider()

            ForEach(SortField.allCases) { field in
                Button(field.title) { browser?.setSort(field) }
            }

            Divider()

            Button(browser?.foldersFirst == true ? "Mix Files and Folders" : "Keep Folders on Top") {
                browser?.toggleFoldersFirst()
            }
            Button(browser?.usesRelativeDates == true ? "Use Exact Dates" : "Use Relative Dates") {
                browser?.toggleRelativeDates()
            }
            Button(browser?.showsHiddenFiles == true ? "Hide Hidden Files" : "Show Hidden Files") {
                browser?.toggleHiddenFiles()
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])

            Divider()

            Button(model?.showsTransfersInspector == true ? "Hide Transfers" : "Show Transfers") {
                model?.showsTransfersInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(model == nil)

            Button(model?.showsSidebar == true ? "Hide Sidebar" : "Show Sidebar") {
                model?.showsSidebar.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(model == nil)
        }

        CommandMenu("Go") {
            Button("Back") { browser?.goBack() }
                .keyboardShortcut("[")
                .disabled(!(browser?.canGoBack ?? false))
            Button("Forward") { browser?.goForward() }
                .keyboardShortcut("]")
                .disabled(!(browser?.canGoForward ?? false))
            Button("Enclosing Folder") { browser?.goUp() }
                .keyboardShortcut(.upArrow)
                .disabled(!(browser?.canGoUp ?? false))
            Button("Go to Folder…") { browser?.goToFolder() }
                .keyboardShortcut("g", modifiers: [.command, .shift])

            Divider()

            Button(browser?.isFavorite == true ? "Remove from Favorites" : "Add to Favorites") {
                browser?.toggleFavorite()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(browser == nil)

            Button("Refresh") { browser?.refresh() }
                .keyboardShortcut("r")
        }
    }
}
