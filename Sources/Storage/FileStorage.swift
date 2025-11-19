import Foundation

/// Default implementation of FileStorageProtocol using FileManager.
/// Provides abstracted file operations with a configurable base directory.
class FileStorage: FileStorageProtocol {
    let baseDirectory: String
    private let fileManager: FileManager
    
    init(baseDirectory: String? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        
        if let baseDirectory = baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            // Default to Documents directory if not specified
            let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.baseDirectory = documentsPath.path
        }
    }
    
    func createDirectory(at path: String) async throws {
        let fullPath = self.path(for: path)
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    try self.fileManager.createDirectory(atPath: fullPath, withIntermediateDirectories: true, attributes: nil)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func save(data: Data, to path: String) async throws {
        let fullPath = self.path(for: path)
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    // Create parent directory if needed
                    let parentDir = (fullPath as NSString).deletingLastPathComponent
                    if !self.fileManager.fileExists(atPath: parentDir) {
                        try self.fileManager.createDirectory(atPath: parentDir, withIntermediateDirectories: true, attributes: nil)
                    }
                    
                    try data.write(to: URL(fileURLWithPath: fullPath), options: .atomic)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func load(from path: String) async throws -> Data {
        let fullPath = self.path(for: path)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let data = try Data(contentsOf: URL(fileURLWithPath: fullPath))
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func path(for identifier: String) -> String {
        return (baseDirectory as NSString).appendingPathComponent(identifier)
    }
    
    func remove(at path: String) async throws {
        let fullPath = self.path(for: path)
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    if self.fileManager.fileExists(atPath: fullPath) {
                        try self.fileManager.removeItem(atPath: fullPath)
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func cleanupTempFiles(olderThan age: TimeInterval) async throws {
        let tempDir = path(for: "temp")
        guard fileManager.fileExists(atPath: tempDir) else { return }
        
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let files = try self.fileManager.contentsOfDirectory(atPath: tempDir)
                    let cutoffDate = Date().addingTimeInterval(-age)
                    
                    for file in files {
                        let filePath = (tempDir as NSString).appendingPathComponent(file)
                        if let attributes = try? self.fileManager.attributesOfItem(atPath: filePath),
                           let modificationDate = attributes[.modificationDate] as? Date,
                           modificationDate < cutoffDate {
                            try? self.fileManager.removeItem(atPath: filePath)
                        }
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

