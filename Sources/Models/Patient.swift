import Foundation

/// Represents a patient in the cognitive assessment system.
/// Core Data-compatible model with stable UUID identity.
struct Patient: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var dateOfBirth: Date?
    var createdAt: Date
    var updatedAt: Date
    
    init(id: UUID = UUID(), name: String, dateOfBirth: Date? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.dateOfBirth = dateOfBirth
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

