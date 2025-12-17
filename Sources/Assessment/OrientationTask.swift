import Foundation
import AudioToolbox

/// Orientation Task implementation.
/// Tests orientation through 6 sequential questions:
/// 1. Date (expected: "14")
/// 2. Month (expected: "December")
/// 3. Year (expected: "2025")
/// 4. Day of week (expected: "Sunday")
/// 5. Place (expected: "hospital")
/// 6. City (expected: "St. Louis")
/// Each correct answer is worth 1 point for a maximum of 6 points.
class OrientationTask: Task {
    let id: UUID
    let title: String = "Orientation Task"
    let instructions: TaskInstructions = .text("This is an orientation task. I will ask you 6 questions about the current date, time, and location. Please answer each question clearly.")
    let expectedInputType: TaskInputType = .audio
    let timingRequirements: TimingRequirements? = nil
    let scoringMetadata: [String: Any]? = nil
    
    private let audioManager: AudioManagerProtocol
    private let taskRunner: TaskRunnerProtocol
    private let dataController: DataControllerProtocol
    
    // Session tracking
    private var sessionId: UUID?
    
    // Question tracking
    enum QuestionType {
        case date
        case month
        case year
        case day
        case place
        case city
    }
    
    private struct Question {
        let type: QuestionType
        let questionText: String
        let expectedAnswer: String
        let alternatives: [String] // Acceptable alternative answers
    }
    
    private let questions: [Question] = [
        Question(
            type: .date,
            questionText: "What is the current date?",
            expectedAnswer: "14",
            alternatives: ["14th", "fourteen", "the 14th", "the fourteenth"]
        ),
        Question(
            type: .month,
            questionText: "What month is it?",
            expectedAnswer: "December",
            alternatives: ["Dec", "dec", "december"]
        ),
        Question(
            type: .year,
            questionText: "What year is it?",
            expectedAnswer: "2025",
            alternatives: ["twenty twenty-five", "twenty twenty five", "two thousand twenty five", "two thousand and twenty five"]
        ),
        Question(
            type: .day,
            questionText: "What day of the week is it?",
            expectedAnswer: "Sunday",
            alternatives: ["Sun", "sun", "sunday"]
        ),
        Question(
            type: .place,
            questionText: "What place are you in?",
            expectedAnswer: "hospital",
            alternatives: ["the hospital", "a hospital", "Hospital", "HOSPITAL"]
        ),
        Question(
            type: .city,
            questionText: "What city are you in?",
            expectedAnswer: "St. Louis",
            alternatives: ["Saint Louis", "St Louis", "St. louis", "saint louis", "st louis", "st. louis"]
        )
    ]
    
    private var currentQuestionIndex: Int = 0
    private var isCancelled = false
    
    // Constants
    private let recordingDuration: TimeInterval = 5.0
    private let transcriptionPollInterval: TimeInterval = 0.5
    private let transcriptionMaxWaitTime: TimeInterval = 3.0
    
    init(
        id: UUID = UUID(),
        audioManager: AudioManagerProtocol,
        taskRunner: TaskRunnerProtocol,
        dataController: DataControllerProtocol
    ) {
        self.id = id
        self.audioManager = audioManager
        self.taskRunner = taskRunner
        self.dataController = dataController
        
        print("🎯 OrientationTask: Initialized with ID: \(id)")
        print("   - DataController instance: \(ObjectIdentifier(dataController as AnyObject))")
    }
    
    func start() async throws {
        print("🎯 OrientationTask: Starting task (id: \(id))")
        isCancelled = false
        currentQuestionIndex = 0
        
        // Get sessionId from the first response if available
        if let firstResponse = try? await getCurrentResponse() {
            sessionId = firstResponse.sessionId
            print("✅ OrientationTask: Retrieved sessionId from existing response: \(sessionId?.uuidString ?? "nil")")
        }
        
        // Clear transcript
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                taskRunnerInstance.currentWord = nil
                taskRunnerInstance.transcript = []
            }
        }
        
        // Intro explanation
        let introText = "Welcome to the orientation task. I will ask you 6 questions about the current date, month, year, day of the week, place, and city. Please answer each question clearly. You will have 5 seconds to answer each question. Let's begin."
        
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                taskRunnerInstance.transcript.append(
                    TranscriptItem(text: introText, type: .instruction, isHighlighted: true)
                )
            }
        }
        
        print("🔊 OrientationTask: Speaking intro")
        try? await audioManager.speak(introText)
        
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                if let lastIndex = taskRunnerInstance.transcript.indices.last {
                    taskRunnerInstance.transcript[lastIndex].isHighlighted = false
                }
            }
        }
        
        // Ask each question sequentially
        for (index, question) in questions.enumerated() {
            if isCancelled { return }
            
            currentQuestionIndex = index
            try await askQuestion(question, questionNumber: index + 1, totalQuestions: questions.count)
            
            if isCancelled { return }
            
            // Brief pause between questions (except after last question)
            if index < questions.count - 1 {
                try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000) // 1 second pause
            }
        }
        
        // Completion
        if !isCancelled {
            let completionText = "Excellent work. You have completed all 6 orientation questions. Thank you for your participation."
            try? await audioManager.speak(completionText)
            
            // Add completion message to transcript
            if let taskRunnerInstance = taskRunner as? TaskRunner {
                await MainActor.run {
                    taskRunnerInstance.transcript.append(
                        TranscriptItem(text: completionText, type: .instruction, isHighlighted: true)
                    )
                }
            }
            
            // Brief pause before transitioning
            try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            await taskRunner.transition(to: .completed)
            print("✅ OrientationTask: Task fully completed")
        } else {
            print("🛑 OrientationTask: Task was cancelled, transitioning to completed to show partial results")
            await taskRunner.transition(to: .completed)
        }
    }
    
    func stop() async throws {
        print("🛑 OrientationTask: stop() called, cancelling task")
        isCancelled = true
    }
    
    func captureResponse(_ response: String) async throws {
        // Not used directly - handled via DataController updates in start()
    }
    
    // MARK: - Question Implementation
    
    private func askQuestion(_ question: Question, questionNumber: Int, totalQuestions: Int) async throws {
        print("\n📋 OrientationTask: Asking question \(questionNumber)/\(totalQuestions) - \(question.type)")
        
        // Announce question
        let questionAnnouncement = "Question \(questionNumber) of \(totalQuestions)."
        
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                taskRunnerInstance.transcript.append(
                    TranscriptItem(text: questionAnnouncement, type: .phaseAnnouncement, isHighlighted: true)
                )
            }
        }
        
        try? await audioManager.speak(questionAnnouncement)
        
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                if let lastIndex = taskRunnerInstance.transcript.indices.last {
                    taskRunnerInstance.transcript[lastIndex].isHighlighted = false
                }
            }
        }
        
        // Small pause
        try? await _Concurrency.Task.sleep(nanoseconds: 500_000_000) // 0.5 second
        
        // Ask the question
        await taskRunner.transition(to: .presenting)
        
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                taskRunnerInstance.transcript.append(
                    TranscriptItem(text: question.questionText, type: .prompt, isHighlighted: true)
                )
            }
        }
        
        try? await audioManager.speak(question.questionText)
        
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                if let lastIndex = taskRunnerInstance.transcript.indices.last {
                    taskRunnerInstance.transcript[lastIndex].isHighlighted = false
                }
            }
        }
        
        // Prompt for response
        let promptText = "You have 5 seconds to answer. I'm listening."
        
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                taskRunnerInstance.transcript.append(
                    TranscriptItem(text: promptText, type: .prompt, isHighlighted: true)
                )
            }
        }
        
        try? await audioManager.speak(promptText)
        
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                if let lastIndex = taskRunnerInstance.transcript.indices.last {
                    taskRunnerInstance.transcript[lastIndex].isHighlighted = false
                }
            }
        }
        
        // Small pause before recording starts
        try? await _Concurrency.Task.sleep(nanoseconds: 500_000_000) // 0.5 second
        
        // Play start beep
        try? await audioManager.playBeep(soundID: SystemSoundID(1057)) // Start beep
        
        // Record response
        await taskRunner.transition(to: .recording)
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
        
        // Wait for recording duration, checking for cancellation every 0.5 seconds
        let checkInterval: TimeInterval = 0.5
        let totalChecks = Int(recordingDuration / checkInterval)
        for i in 0..<totalChecks {
            if isCancelled {
                print("🛑 OrientationTask: Task cancelled during recording (check \(i + 1)/\(totalChecks))")
                break
            }
            try? await _Concurrency.Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
        }
        
        if isCancelled {
            print("🛑 OrientationTask: Task cancelled during recording, processing partial data")
            return
        }
        
        // Play end beep
        try? await audioManager.playBeep(soundID: SystemSoundID(1054)) // End beep (different pitch)
        
        // Evaluate
        await taskRunner.transition(to: .evaluating)
        
        let response = try? await getCurrentResponse()
        let audioClipId = response?.audioClipId
        
        // Wait only 3 seconds for transcription, then proceed
        let transcription = try? await waitForTranscription(audioClipId: audioClipId, maxWaitSeconds: transcriptionMaxWaitTime)
        let (score, isCorrect) = scoreAnswer(transcription ?? "", question: question)
        
        // Get sessionId if not already stored
        if sessionId == nil, let response = response {
            sessionId = response.sessionId
        }
        
        // Update response with scoring data
        if var currentResponse = response {
            currentResponse.score = score
            currentResponse.responseText = transcription
            currentResponse.expectedWords = [question.expectedAnswer]
            currentResponse.correctWords = isCorrect ? [question.expectedAnswer] : []
            currentResponse.updatedAt = Date()
            
            try? await dataController.updateItemResponse(currentResponse)
            print("✅ OrientationTask: Question \(questionNumber) scored - \(isCorrect ? "Correct" : "Incorrect") (score: \(score))")
        } else {
            print("⚠️ OrientationTask: No response available for question \(questionNumber)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func getCurrentResponse() async throws -> ItemResponse? {
        let allResponses = try await dataController.fetchAllItemResponses()
        let taskResponses = allResponses.filter { $0.taskId == self.id }
        let sortedResponses = taskResponses.sorted { $0.createdAt > $1.createdAt }
        return sortedResponses.first
    }
    
    private func waitForTranscription(audioClipId: UUID?, maxWaitSeconds: TimeInterval) async throws -> String? {
        guard let audioClipId = audioClipId else { return nil }
        
        let startTime = Date()
        var pollCount = 0
        let maxPolls = Int(maxWaitSeconds / transcriptionPollInterval) + 1
        
        while pollCount < maxPolls {
            if isCancelled { return nil }
            
            pollCount += 1
            let elapsed = Date().timeIntervalSince(startTime)
            
            if elapsed >= maxWaitSeconds { break }
            
            if let audioClip = try? await dataController.fetchAudioClip(id: audioClipId) {
                if let transcription = audioClip.transcription, !transcription.isEmpty {
                    return transcription
                }
            }
            
            try? await _Concurrency.Task.sleep(nanoseconds: UInt64(transcriptionPollInterval * 1_000_000_000))
        }
        
        return nil
    }
    
    /// Scores an orientation answer with flexible matching
    /// Returns: (score: 0.0 or 1.0, isCorrect: Bool)
    private func scoreAnswer(_ transcription: String, question: Question) -> (score: Double, isCorrect: Bool) {
        // Normalize transcription
        let normalized = transcription.lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s\\.]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check against expected answer and alternatives
        let expectedLower = question.expectedAnswer.lowercased()
        let alternativesLower = question.alternatives.map { $0.lowercased() }
        
        // Check if transcription contains the expected answer or any alternative
        let allAcceptable = [expectedLower] + alternativesLower
        
        for acceptable in allAcceptable {
            // For date, check if the number appears
            if question.type == .date {
                // Extract numbers from transcription
                let numbers = normalized.components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .joined()
                if numbers.contains("14") || normalized.contains("fourteen") || normalized.contains("14th") {
                    print("   ✅ Orientation scoring: Date match found")
                    return (1.0, true)
                }
            }
            // For year, check if the year appears
            else if question.type == .year {
                // Extract numbers from transcription
                let numbers = normalized.components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .joined()
                if numbers.contains("2025") || normalized.contains("twenty twenty five") || normalized.contains("two thousand twenty five") {
                    print("   ✅ Orientation scoring: Year match found")
                    return (1.0, true)
                }
            }
            // For other questions, check if the normalized transcription contains the acceptable answer
            else {
                // Remove common words like "the", "a", "an" for better matching
                let cleaned = normalized
                    .replacingOccurrences(of: "\\bthe\\b", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "\\ba\\b", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "\\ban\\b", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Check if cleaned transcription contains the acceptable answer
                if cleaned.contains(acceptable) || normalized.contains(acceptable) {
                    print("   ✅ Orientation scoring: Match found for '\(acceptable)'")
                    return (1.0, true)
                }
                
                // For city, also check without periods and with different spacing
                if question.type == .city {
                    let cityVariants = [
                        "st louis", "saint louis", "st. louis",
                        "stlouis", "saintlouis"
                    ]
                    for variant in cityVariants {
                        if cleaned.contains(variant) || normalized.contains(variant) {
                            print("   ✅ Orientation scoring: City variant match found")
                            return (1.0, true)
                        }
                    }
                }
            }
        }
        
        print("   ❌ Orientation scoring: No match found")
        print("      Transcription: '\(transcription)'")
        print("      Normalized: '\(normalized)'")
        print("      Expected: '\(question.expectedAnswer)'")
        return (0.0, false)
    }
}

