import Foundation

/// Represents an audio recording clip.
/// Core Data-compatible model with stable UUID identity.
struct AudioClip: Identifiable, Codable, Equatable {
    let id: UUID
    var filePath: String
    var duration: TimeInterval
    var createdAt: Date
    var transcription: String?
    var updatedAt: Date
    
    init(id: UUID = UUID(), filePath: String, duration: TimeInterval = 0, createdAt: Date = Date(), transcription: String? = nil, updatedAt: Date = Date()) {
        self.id = id
        self.filePath = filePath
        self.duration = duration
        self.createdAt = createdAt
        self.transcription = transcription
        self.updatedAt = updatedAt
    }
}

