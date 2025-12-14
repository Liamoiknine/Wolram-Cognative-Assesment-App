import Foundation

/// Represents a response to a specific assessment task item.
/// Core Data-compatible model with stable UUID identity.
struct ItemResponse: Identifiable, Codable, Equatable {
    let id: UUID
    var sessionId: UUID
    var taskId: UUID
    var responseText: String?
    var timestamp: Date
    var audioClipId: UUID?
    var createdAt: Date
    var updatedAt: Date
    var score: Double?
    var correctWords: [String]?
    var expectedWords: [String]?
    
    init(id: UUID = UUID(), sessionId: UUID, taskId: UUID, responseText: String? = nil, timestamp: Date = Date(), audioClipId: UUID? = nil, createdAt: Date = Date(), updatedAt: Date = Date(), score: Double? = nil, correctWords: [String]? = nil, expectedWords: [String]? = nil) {
        self.id = id
        self.sessionId = sessionId
        self.taskId = taskId
        self.responseText = responseText
        self.timestamp = timestamp
        self.audioClipId = audioClipId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.score = score
        self.correctWords = correctWords
        self.expectedWords = expectedWords
    }
}

