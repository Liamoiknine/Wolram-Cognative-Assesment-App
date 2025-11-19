import Foundation

/// Represents an assessment session for a patient.
/// Core Data-compatible model with stable UUID identity.
struct Session: Identifiable, Codable, Equatable {
    let id: UUID
    var patientId: UUID
    var startTime: Date
    var endTime: Date?
    var status: SessionStatus
    var createdAt: Date
    var updatedAt: Date
    
    init(id: UUID = UUID(), patientId: UUID, startTime: Date = Date(), endTime: Date? = nil, status: SessionStatus = .inProgress, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.patientId = patientId
        self.startTime = startTime
        self.endTime = endTime
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum SessionStatus: String, Codable {
    case inProgress
    case completed
    case cancelled
}

