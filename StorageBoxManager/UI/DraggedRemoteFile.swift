import SwiftUI
import UniformTypeIdentifiers

/// Lets a remote file be dragged out to the Finder.
///
/// The file only exists on the server, so the export closure is the download: it runs when the
/// drop is accepted, writes the bytes into a temporary folder, and hands that file over. This
/// path deliberately bypasses the transfer queue — a drag has its own progress indicator in the
/// Finder, and the transfer only exists for as long as the drag does.
struct DraggedRemoteFile: Transferable {
    let item: RemoteItem
    let backend: any StorageBackend

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .data) { dragged in
            // A private folder per drag keeps the original filename intact even when the same
            // name is dragged from two boxes at once.
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
    /// Makes a row draggable when it represents a downloadable file. Folders are not draggable:
    /// exporting one would mean walking the tree, which v1 does not do.
    @ViewBuilder
    func draggableRemoteFile(_ item: RemoteItem, backend: (any StorageBackend)?) -> some View {
        if let backend, !item.isDirectory {
            draggable(DraggedRemoteFile(item: item, backend: backend))
        } else {
            self
        }
    }
}
