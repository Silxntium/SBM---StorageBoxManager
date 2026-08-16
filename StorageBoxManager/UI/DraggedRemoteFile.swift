import SwiftUI
import UniformTypeIdentifiers

// drag-out to Finder. file only exists on the server, so the "export" is really just a download
// that happens when the drop lands. doesn't go through TransferQueue on purpose - Finder shows
// its own progress for drags anyway
struct DraggedRemoteFile: Transferable {
    let item: RemoteItem
    let backend: any StorageBackend

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .data) { dragged in
            // unique folder per drag so dragging the same filename from two boxes doesn't collide
            let folder = FileManager.default.temporaryDirectory
                .appending(path: "drag-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            let destination = folder.appending(path: dragged.item.name, directoryHint: .notDirectory)
            try await dragged.backend.download(dragged.item.path, to: destination) { _, _ in }
            return SentTransferredFile(destination)
        }
    }
}

extension View {
    // folders aren't draggable - would need to walk the whole tree, not doing that yet
    @ViewBuilder
    func draggableRemoteFile(_ item: RemoteItem, backend: (any StorageBackend)?) -> some View {
        if let backend, !item.isDirectory {
            draggable(DraggedRemoteFile(item: item, backend: backend))
        } else {
            self
        }
    }
}
