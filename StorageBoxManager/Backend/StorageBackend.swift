import Foundation

// keeping this abstract so an SFTP backend could slot in later without touching the UI at all
protocol StorageBackend: Sendable {
    func probe() async throws // used by the box editor's "test connection" button
    func list(_ path: RemotePath) async throws -> [RemoteItem] // one level, not recursive
    func createDirectory(at path: RemotePath) async throws
    func move(from source: RemotePath, to destination: RemotePath, isDirectory: Bool) async throws // rename = move too
    func delete(_ path: RemotePath, isDirectory: Bool) async throws

    // bytesTotal is -1 until we know it
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
