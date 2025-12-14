import Foundation

/// Represents an item in the transcript
struct TranscriptItem: Identifiable, Equatable {
    let id: UUID
    let text: String
    let timestamp: Date
    let type: TranscriptItemType
    var isHighlighted: Bool
    
    init(id: UUID = UUID(), text: String, timestamp: Date = Date(), type: TranscriptItemType, isHighlighted: Bool = false) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.type = type
        self.isHighlighted = isHighlighted
    }
}

enum TranscriptItemType {
    case instruction
    case word
    case prompt
    case trialAnnouncement
    case phaseAnnouncement
    case digit
    case letter
    case calculationPrompt
    case sentence
    case fluencyPrompt
}

