import Foundation

/// Protocol for file storage operations.
/// Abstracts file system access to enable testing and future Core Data integration.
protocol FileStorageProtocol {
    /// Creates a directory at the specified path if it doesn't exist.
    func createDirectory(at path: String) async throws
    
    /// Saves data to a file at the specified path.
    func save(data: Data, to path: String) async throws
    
    /// Retrieves data from a file at the specified path.
    func load(from path: String) async throws -> Data
    
    /// Returns the full path for a given relative path identifier.
    func path(for identifier: String) -> String
    
    /// Removes a file at the specified path.
    func remove(at path: String) async throws
    
    /// Cleans up temporary files older than the specified age.
    func cleanupTempFiles(olderThan age: TimeInterval) async throws
    
    /// Returns the base directory path.
    var baseDirectory: String { get }
}

