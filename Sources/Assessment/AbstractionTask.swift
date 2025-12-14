import Foundation
import AudioToolbox

/// Abstraction Task implementation.
/// Tests abstraction through 2 trials where the user must identify the category that unites two words.
/// Trial 1: "Train and bicycle" → "Vehicles" or "Transportation"
/// Trial 2: "Banana and orange" → "Fruits"
class AbstractionTask: Task {
    let id: UUID
    let title: String = "Abstraction Task"
    let instructions: TaskInstructions = .text("This is an abstraction task. I will read you two words, and you need to respond with the category that unites them.")
    let expectedInputType: TaskInputType = .audio
    let timingRequirements: TimingRequirements? = nil
    let scoringMetadata: [String: Any]? = nil
    
    private let audioManager: AudioManagerProtocol
    private let taskRunner: TaskRunnerProtocol
    private let dataController: DataControllerProtocol
    
    // Session tracking
    private var sessionId: UUID?
    
    // Trial data
    struct Trial {
        let word1: String
        let word2: String
        let expectedCategories: [String] // Acceptable category responses
    }
    
    private let trials = [
        Trial(
            word1: "Train",
            word2: "bicycle",
            expectedCategories: ["vehicles", "vehicle", "transportation", "transport", "transportation vehicles", "modes of transportation"]
        ),
        Trial(
            word1: "Banana",
            word2: "orange",
            expectedCategories: ["fruits", "fruit", "food", "foods"]
        )
    ]
    
    private var isCancelled = false
    
    // Constants
    private let recordingDuration: TimeInterval = 15.0 // 15 seconds per trial
    private let transcriptionPollInterval: TimeInterval = 0.5
    private let transcriptionMaxWaitTime: TimeInterval = 30.0
    
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
        
        print("🎯 AbstractionTask: Initialized with ID: \(id)")
        print("   - DataController instance: \(ObjectIdentifier(dataController as AnyObject))")
    }
    
    func start() async throws {
        print("🎯 AbstractionTask: Starting task (id: \(id))")
        isCancelled = false
        
        // Get sessionId - we'll create it when we create the first response
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            sessionId = taskRunnerInstance.currentSessionId
            print("✅ AbstractionTask: Retrieved sessionId from TaskRunner: \(sessionId?.uuidString ?? "nil")")
        }
        
        // Clear transcript
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                taskRunnerInstance.currentWord = nil
                taskRunnerInstance.transcript = []
            }
        }
        
        // Intro explanation
        let introText = "Welcome to the abstraction task. I will read you two words, and you need to tell me the category that unites them. For example, if I say 'apple and orange', you might say 'fruits'. You will have 15 seconds to respond for each pair. Let's begin."
        
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                taskRunnerInstance.transcript.append(
                    TranscriptItem(text: introText, type: .instruction, isHighlighted: true)
                )
            }
        }
        
        print("🔊 AbstractionTask: Speaking intro")
        try? await audioManager.speak(introText)
        
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                if let lastIndex = taskRunnerInstance.transcript.indices.last {
                    taskRunnerInstance.transcript[lastIndex].isHighlighted = false
                }
            }
        }
        
        // Brief pause before starting trials
        try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Run each trial
        for (index, trial) in trials.enumerated() {
            if isCancelled { return }
            
            print("📋 AbstractionTask: Starting Trial \(index + 1)/\(trials.count)")
            try await runTrial(trial: trial, trialNumber: index + 1)
            
            if isCancelled { return }
            
            // Brief pause between trials (except after last trial)
            if index < trials.count - 1 {
                try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000) // 1 second pause
            }
        }
        
        if isCancelled { return }
        
        // Completion
        let completionText = "Excellent work. You have completed the abstraction task. Thank you for your participation."
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
        print("✅ AbstractionTask: Task fully completed")
    }
    
    func stop() async throws {
        print("🛑 AbstractionTask: stop() called, cancelling task")
        isCancelled = true
    }
    
    func captureResponse(_ response: String) async throws {
        // Not used directly - handled via DataController updates in start()
    }
    
    // MARK: - Trial Implementation
    
    private func runTrial(trial: Trial, trialNumber: Int) async throws {
        print("\n📋 AbstractionTask: Starting Trial \(trialNumber)")
        
        // Announce trial
        let trialText = "Trial \(trialNumber)."
        
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                taskRunnerInstance.transcript.append(
                    TranscriptItem(text: trialText, type: .trialAnnouncement, isHighlighted: true)
                )
            }
        }
        
        try? await audioManager.speak(trialText)
        
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                if let lastIndex = taskRunnerInstance.transcript.indices.last {
                    taskRunnerInstance.transcript[lastIndex].isHighlighted = false
                }
            }
        }
        
        // Brief pause
        try? await _Concurrency.Task.sleep(nanoseconds: 500_000_000) // 0.5 second
        
        // Read the two words
        await taskRunner.transition(to: .presenting)
        
        let wordsText = "\(trial.word1) and \(trial.word2)."
        
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                taskRunnerInstance.currentWord = "\(trial.word1) and \(trial.word2)"
                taskRunnerInstance.transcript.append(
                    TranscriptItem(text: wordsText, type: .word, isHighlighted: true)
                )
            }
        }
        
        try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000) // 0.2s for UI
        try? await audioManager.speak(wordsText)
        
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                if let lastIndex = taskRunnerInstance.transcript.lastIndex(where: { $0.text == wordsText && $0.type == .word }) {
                    taskRunnerInstance.transcript[lastIndex].isHighlighted = false
                }
                taskRunnerInstance.currentWord = nil
            }
        }
        
        // Brief pause after reading words
        try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Prompt for response
        let promptText = "What category unites these two words? You have 15 seconds. I'm listening."
        
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
                print("🛑 AbstractionTask: Task cancelled during recording (check \(i + 1)/\(totalChecks))")
                break
            }
            try? await _Concurrency.Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
        }
        
        if isCancelled {
            print("🛑 AbstractionTask: Task cancelled during recording, processing partial data")
            return
        }
        
        // Play end beep
        try? await audioManager.playBeep(soundID: SystemSoundID(1054)) // End beep (different pitch)
        
        // Evaluate
        await taskRunner.transition(to: .evaluating)
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
        
        let response = try? await getCurrentResponse()
        let audioClipId = response?.audioClipId
        
        let transcription = try? await waitForTranscription(audioClipId: audioClipId, maxWaitSeconds: transcriptionMaxWaitTime)
        let (score, isCorrect) = scoreAbstraction(transcription ?? "", expectedCategories: trial.expectedCategories)
        
        // Get sessionId if not already stored
        if sessionId == nil, let response = response {
            sessionId = response.sessionId
        }
        
        // Update response with scoring data
        if var currentResponse = response {
            currentResponse.score = score
            currentResponse.responseText = transcription
            currentResponse.correctWords = isCorrect ? [trial.expectedCategories.first ?? ""] : []
            currentResponse.expectedWords = [trial.expectedCategories.first ?? ""]
            currentResponse.updatedAt = Date()
            
            try? await dataController.updateItemResponse(currentResponse)
            print("✅ AbstractionTask: Trial \(trialNumber) scored - \(isCorrect ? "Correct" : "Incorrect") (score: \(score))")
        } else {
            print("⚠️ AbstractionTask: No response available for trial \(trialNumber)")
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
    
    /// Scores abstraction response - checks if transcription matches any expected category
    /// Returns: (score: 0.0 or 1.0, isCorrect: Bool)
    private func scoreAbstraction(_ transcription: String, expectedCategories: [String]) -> (score: Double, isCorrect: Bool) {
        // Normalize transcription
        let normalizedTranscription = transcription.lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if transcription contains any of the expected categories
        for expectedCategory in expectedCategories {
            let normalizedExpected = expectedCategory.lowercased()
            
            // Check for exact match or if the category word appears in the transcription
            if normalizedTranscription == normalizedExpected || 
               normalizedTranscription.contains(normalizedExpected) ||
               normalizedExpected.contains(normalizedTranscription) {
                print("   ✅ Abstraction scoring: Match found - '\(transcription)' matches '\(expectedCategory)'")
                return (1.0, true)
            }
        }
        
        print("   ❌ Abstraction scoring: No match found - '\(transcription)' does not match any expected categories: \(expectedCategories)")
        return (0.0, false)
    }
}

