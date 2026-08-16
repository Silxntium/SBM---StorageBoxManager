import Foundation

/// Everything the UI needs from a storage box, independent of how it is reached.
///
/// This is the seam where an SFTP implementation (Hetzner speaks SSH on port 23) can be added
/// later without the UI knowing: nothing above this protocol mentions HTTP.
protocol StorageBackend: Sendable {
    /// Cheap round-trip that proves host and credentials work. Used by the box editor.
    func probe() async throws

    /// Direct children of a directory, not recursive.
    func list(_ path: RemotePath) async throws -> [RemoteItem]

    func createDirectory(at path: RemotePath) async throws

    /// Covers both renaming and moving. Fails rather than overwriting an existing target.
    func move(from source: RemotePath, to destination: RemotePath, isDirectory: Bool) async throws

    func delete(_ path: RemotePath, isDirectory: Bool) async throws

    /// Streams a remote file to `localURL`, reporting `(bytesDone, bytesTotal)`.
    /// `bytesTotal` is `-1` while the total is still unknown.
    func download(
        _ path: RemotePath,
        to localURL: URL,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws

    func upload(
        _ localURL: URL,
        to path: RemotePath,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws
}
