import Foundation

// MARK: - Client → Backend Messages

struct AudioChunk: Codable {
    let audio: String  // base64 encoded PCM
    let sampleRate: Int
    let format: String  // "pcm_16bit_mono"
}

struct ClientEvent: Codable {
    let action: String  // "start_task", "end_session", or "audio_complete"
}

struct ClientMessage: Codable {
    let type: String  // "audio_chunk" or "event"
    let data: ClientMessageData
    
    enum ClientMessageData: Codable {
        case audioChunk(AudioChunk)
        case event(ClientEvent)
        
        enum CodingKeys: String, CodingKey {
            case audio, sampleRate = "sample_rate", format, action
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            if container.contains(.audio) {
                let audio = try container.decode(String.self, forKey: .audio)
                let sampleRate = try container.decode(Int.self, forKey: .sampleRate)
                let format = try container.decode(String.self, forKey: .format)
                self = .audioChunk(AudioChunk(audio: audio, sampleRate: sampleRate, format: format))
            } else if container.contains(.action) {
                let action = try container.decode(String.self, forKey: .action)
                self = .event(ClientEvent(action: action))
            } else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown message type"))
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            
            switch self {
            case .audioChunk(let chunk):
                try container.encode(chunk.audio, forKey: .audio)
                try container.encode(chunk.sampleRate, forKey: .sampleRate)
                try container.encode(chunk.format, forKey: .format)
            case .event(let event):
                try container.encode(event.action, forKey: .action)
            }
        }
    }
}

// MARK: - Backend → Client Messages

struct TTSMessage: Codable {
    let audio: String  // base64-encoded audio bytes
    let trialNumber: Int?  // Trial number (0 for instruction, 1-2 for trials)
    
    enum CodingKeys: String, CodingKey {
        case audio, trialNumber = "trial_number"
    }
    
    var audioData: Data? {
        return Data(base64Encoded: audio)
    }
}

struct TaskStateMessage: Codable {
    let state: String  // "listening", "complete"
    let trialNumber: Int?
    let message: String?
    
    enum CodingKeys: String, CodingKey {
        case state, trialNumber = "trial_number", message
    }
}

struct DebugMessage: Codable {
    let message: String
}

struct WordDisplayMessage: Codable {
    let word: String
    let trialNumber: Int
    let wordIndex: Int
    
    enum CodingKeys: String, CodingKey {
        case word, trialNumber = "trial_number", wordIndex = "word_index"
    }
}

struct StateTransition: Codable {
    let phase: String  // "instruction_display", "instruction_playing", etc.
    let trialNumber: Int?
    let message: String?
    
    enum CodingKeys: String, CodingKey {
        case phase, trialNumber = "trial_number", message
    }
}

struct EvaluationResult: Codable {
    let trialNumber: Int
    // Abstraction task fields (optional for Working Memory)
    let word1: String?
    let word2: String?
    let category: String?
    // Working Memory task fields (optional for Abstraction)
    let words: [String]?
    let correctWords: [String]?
    let score: Double?
    // Common fields
    let transcript: String
    let isCorrect: Bool
    let confidence: Double
    let notes: String
    
    enum CodingKeys: String, CodingKey {
        case trialNumber = "trial_number"
        case word1, word2, transcript, category
        case words, correctWords = "correct_words", score
        case isCorrect = "is_correct"
        case confidence, notes
    }
}

struct ServerMessage: Codable {
    let type: String  // "tts_text", "tts_audio", "task_state", "debug"
    let data: ServerMessageData
    
    enum CodingKeys: String, CodingKey {
        case type, data
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "all_results":
            // Decode as array directly
            let resultsArray = try container.decode([EvaluationResult].self, forKey: .data)
            self.type = type
            self.data = .allResults(resultsArray)
            return
        default:
            break
        }
        
        // Decode data based on type (for non-array types)
        let dataContainer = try container.nestedContainer(keyedBy: DynamicCodingKeys.self, forKey: .data)
        
        switch type {
        case "tts_text", "tts_audio":
            let audio = try dataContainer.decode(String.self, forKey: DynamicCodingKeys(stringValue: "audio")!)
            let trialNumber = try? dataContainer.decodeIfPresent(Int.self, forKey: DynamicCodingKeys(stringValue: "trial_number")!)
            self.type = type
            self.data = .tts(TTSMessage(audio: audio, trialNumber: trialNumber))
        case "task_state":
            let state = try dataContainer.decode(String.self, forKey: DynamicCodingKeys(stringValue: "state")!)
            let trialNumber = try? dataContainer.decodeIfPresent(Int.self, forKey: DynamicCodingKeys(stringValue: "trial_number")!)
            let message = try? dataContainer.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "message")!)
            self.type = type
            self.data = .taskState(TaskStateMessage(state: state, trialNumber: trialNumber, message: message))
        case "debug":
            let message = try dataContainer.decode(String.self, forKey: DynamicCodingKeys(stringValue: "message")!)
            self.type = type
            self.data = .debug(DebugMessage(message: message))
        case "evaluation_result":
            let trialNumber = try dataContainer.decode(Int.self, forKey: DynamicCodingKeys(stringValue: "trial_number")!)
            let word1 = try? dataContainer.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "word1")!)
            let word2 = try? dataContainer.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "word2")!)
            let transcript = try dataContainer.decode(String.self, forKey: DynamicCodingKeys(stringValue: "transcript")!)
            let category = try? dataContainer.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "category")!)
            let words = try? dataContainer.decodeIfPresent([String].self, forKey: DynamicCodingKeys(stringValue: "words")!)
            let correctWords = try? dataContainer.decodeIfPresent([String].self, forKey: DynamicCodingKeys(stringValue: "correct_words")!)
            let score = try? dataContainer.decodeIfPresent(Double.self, forKey: DynamicCodingKeys(stringValue: "score")!)
            let isCorrect = try dataContainer.decode(Bool.self, forKey: DynamicCodingKeys(stringValue: "is_correct")!)
            let confidence = try dataContainer.decode(Double.self, forKey: DynamicCodingKeys(stringValue: "confidence")!)
            let notes = try dataContainer.decode(String.self, forKey: DynamicCodingKeys(stringValue: "notes")!)
            self.type = type
            self.data = .evaluationResult(EvaluationResult(
                trialNumber: trialNumber,
                word1: word1,
                word2: word2,
                category: category,
                words: words,
                correctWords: correctWords,
                score: score,
                transcript: transcript,
                isCorrect: isCorrect,
                confidence: confidence,
                notes: notes
            ))
        case "word_display":
            let word = try dataContainer.decode(String.self, forKey: DynamicCodingKeys(stringValue: "word")!)
            let trialNumber = try dataContainer.decode(Int.self, forKey: DynamicCodingKeys(stringValue: "trial_number")!)
            let wordIndex = try dataContainer.decode(Int.self, forKey: DynamicCodingKeys(stringValue: "word_index")!)
            self.type = type
            self.data = .wordDisplay(WordDisplayMessage(word: word, trialNumber: trialNumber, wordIndex: wordIndex))
        case "state_transition":
            let phase = try dataContainer.decode(String.self, forKey: DynamicCodingKeys(stringValue: "phase")!)
            let trialNumber = try? dataContainer.decodeIfPresent(Int.self, forKey: DynamicCodingKeys(stringValue: "trial_number")!)
            let message = try? dataContainer.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "message")!)
            self.type = type
            self.data = .stateTransition(StateTransition(phase: phase, trialNumber: trialNumber, message: message))
        default:
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown message type: \(type)"))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        
        var dataContainer = container.nestedContainer(keyedBy: DynamicCodingKeys.self, forKey: .data)
        
        switch data {
        case .tts(let tts):
            try dataContainer.encode(tts.audio, forKey: DynamicCodingKeys(stringValue: "audio")!)
            if let trialNumber = tts.trialNumber {
                try dataContainer.encode(trialNumber, forKey: DynamicCodingKeys(stringValue: "trial_number")!)
            }
        case .taskState(let state):
            try dataContainer.encode(state.state, forKey: DynamicCodingKeys(stringValue: "state")!)
            if let trialNumber = state.trialNumber {
                try dataContainer.encode(trialNumber, forKey: DynamicCodingKeys(stringValue: "trial_number")!)
            }
            if let message = state.message {
                try dataContainer.encode(message, forKey: DynamicCodingKeys(stringValue: "message")!)
            }
        case .debug(let debug):
            try dataContainer.encode(debug.message, forKey: DynamicCodingKeys(stringValue: "message")!)
        case .evaluationResult(let result):
            try dataContainer.encode(result.trialNumber, forKey: DynamicCodingKeys(stringValue: "trial_number")!)
            if let word1 = result.word1 {
                try dataContainer.encode(word1, forKey: DynamicCodingKeys(stringValue: "word1")!)
            }
            if let word2 = result.word2 {
                try dataContainer.encode(word2, forKey: DynamicCodingKeys(stringValue: "word2")!)
            }
            try dataContainer.encode(result.transcript, forKey: DynamicCodingKeys(stringValue: "transcript")!)
            if let category = result.category {
                try dataContainer.encode(category, forKey: DynamicCodingKeys(stringValue: "category")!)
            }
            if let words = result.words {
                try dataContainer.encode(words, forKey: DynamicCodingKeys(stringValue: "words")!)
            }
            if let correctWords = result.correctWords {
                try dataContainer.encode(correctWords, forKey: DynamicCodingKeys(stringValue: "correct_words")!)
            }
            if let score = result.score {
                try dataContainer.encode(score, forKey: DynamicCodingKeys(stringValue: "score")!)
            }
            try dataContainer.encode(result.isCorrect, forKey: DynamicCodingKeys(stringValue: "is_correct")!)
            try dataContainer.encode(result.confidence, forKey: DynamicCodingKeys(stringValue: "confidence")!)
            try dataContainer.encode(result.notes, forKey: DynamicCodingKeys(stringValue: "notes")!)
        case .wordDisplay(let wordDisplay):
            try dataContainer.encode(wordDisplay.word, forKey: DynamicCodingKeys(stringValue: "word")!)
            try dataContainer.encode(wordDisplay.trialNumber, forKey: DynamicCodingKeys(stringValue: "trial_number")!)
            try dataContainer.encode(wordDisplay.wordIndex, forKey: DynamicCodingKeys(stringValue: "word_index")!)
        case .stateTransition(let transition):
            try dataContainer.encode(transition.phase, forKey: DynamicCodingKeys(stringValue: "phase")!)
            if let trialNumber = transition.trialNumber {
                try dataContainer.encode(trialNumber, forKey: DynamicCodingKeys(stringValue: "trial_number")!)
            }
            if let message = transition.message {
                try dataContainer.encode(message, forKey: DynamicCodingKeys(stringValue: "message")!)
            }
        case .allResults(let results):
            // Encode as array
            var resultsContainer = container.nestedUnkeyedContainer(forKey: .data)
            for result in results {
                var resultContainer = resultsContainer.nestedContainer(keyedBy: DynamicCodingKeys.self)
                try resultContainer.encode(result.trialNumber, forKey: DynamicCodingKeys(stringValue: "trial_number")!)
                if let word1 = result.word1 {
                    try resultContainer.encode(word1, forKey: DynamicCodingKeys(stringValue: "word1")!)
                }
                if let word2 = result.word2 {
                    try resultContainer.encode(word2, forKey: DynamicCodingKeys(stringValue: "word2")!)
                }
                try resultContainer.encode(result.transcript, forKey: DynamicCodingKeys(stringValue: "transcript")!)
                if let category = result.category {
                    try resultContainer.encode(category, forKey: DynamicCodingKeys(stringValue: "category")!)
                }
                if let words = result.words {
                    try resultContainer.encode(words, forKey: DynamicCodingKeys(stringValue: "words")!)
                }
                if let correctWords = result.correctWords {
                    try resultContainer.encode(correctWords, forKey: DynamicCodingKeys(stringValue: "correct_words")!)
                }
                if let score = result.score {
                    try resultContainer.encode(score, forKey: DynamicCodingKeys(stringValue: "score")!)
                }
                try resultContainer.encode(result.isCorrect, forKey: DynamicCodingKeys(stringValue: "is_correct")!)
                try resultContainer.encode(result.confidence, forKey: DynamicCodingKeys(stringValue: "confidence")!)
                try resultContainer.encode(result.notes, forKey: DynamicCodingKeys(stringValue: "notes")!)
            }
        }
    }
    
    enum ServerMessageData {
        case tts(TTSMessage)
        case taskState(TaskStateMessage)
        case debug(DebugMessage)
        case evaluationResult(EvaluationResult)
        case wordDisplay(WordDisplayMessage)
        case stateTransition(StateTransition)
        case allResults([EvaluationResult])
    }
    
    struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        init?(stringValue: String) {
            self.stringValue = stringValue
        }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }
}

// MARK: - Task State Enum

enum TaskState: String {
    case listening
    case complete
}

