import Foundation
import AudioToolbox

/// Language Task implementation.
/// Tests language through 2 sequential phases:
/// 1. Sentence Repetition (2 sentences, 10 seconds each, 1 point per sentence)
/// 2. Letter Fluency (30 seconds, letter F, >10 words = 1 point)
class LanguageTask: Task {
    let id: UUID
    let title: String = "Language Task"
    let instructions: TaskInstructions = .text("This is a language task with two parts. Please follow the instructions carefully.")
    let expectedInputType: TaskInputType = .audio
    let timingRequirements: TimingRequirements? = nil
    let scoringMetadata: [String: Any]? = nil
    
    private let audioManager: AudioManagerProtocol
    private let taskRunner: TaskRunnerProtocol
    private let dataController: DataControllerProtocol
    
    // Session tracking
    private var sessionId: UUID?
    
    // Phase tracking
    enum Phase {
        case sentenceRepetition
        case fluency
    }
    
    private var currentPhase: Phase = .sentenceRepetition
    private var isCancelled = false
    
    // Sentence repetition
    private let sentences = [
        "I only know that John is the one to help today.",
        "The cat always hid under the couch when dogs were in the room."
    ]
    
    // Constants
    private let sentenceRecordingDuration: TimeInterval = 10.0
    private let fluencyRecordingDuration: TimeInterval = 30.0
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
        
        print("🎯 LanguageTask: Initialized with ID: \(id)")
        print("   - DataController instance: \(ObjectIdentifier(dataController as AnyObject))")
    }
    
    func start() async throws {
        print("🎯 LanguageTask: Starting task (id: \(id))")
        isCancelled = false
        
        // Get sessionId - we'll create it when we create the first response
        // For now, we'll get it from TaskRunner if available
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            sessionId = taskRunnerInstance.currentSessionId
            print("✅ LanguageTask: Retrieved sessionId from TaskRunner: \(sessionId?.uuidString ?? "nil")")
        }
        
        // Clear transcript
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                taskRunnerInstance.currentWord = nil
                taskRunnerInstance.transcript = []
            }
        }
        
        // Intro explanation
        let introText = "Welcome to the language task. This test has two parts. I will guide you through each part with spoken instructions. Please listen carefully and follow the directions. Let's begin."
        
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                taskRunnerInstance.transcript.append(
                    TranscriptItem(text: introText, type: .instruction, isHighlighted: true)
                )
            }
        }
        
        print("🔊 LanguageTask: Speaking intro")
        try? await audioManager.speak(introText)
        
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                if let lastIndex = taskRunnerInstance.transcript.indices.last {
                    taskRunnerInstance.transcript[lastIndex].isHighlighted = false
                }
            }
        }
        
        // Phase 1: Sentence Repetition
        try await runSentenceRepetition()
        
        if isCancelled { return }
        
        // Transition to Phase 2
        let transitionText = "Good. Now moving to the second part."
        try? await audioManager.speak(transitionText)
        try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000) // 1 second pause
        
        // Phase 2: Fluency
        try await runFluency()
        
        if isCancelled { return }
        
        // Completion
        let completionText = "Excellent work. You have completed the language task. Thank you for your participation."
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
        print("✅ LanguageTask: Task fully completed")
    }
    
    func stop() async throws {
        print("🛑 LanguageTask: stop() called, cancelling task")
        isCancelled = true
    }
    
    func captureResponse(_ response: String) async throws {
        // Not used directly - handled via DataController updates in start()
    }
    
    // MARK: - Phase Implementations
    
    private func runSentenceRepetition() async throws {
        print("\n📋 LanguageTask: Starting Phase 1 - Sentence Repetition")
        currentPhase = .sentenceRepetition
        
        // Process each sentence
        for (index, sentence) in sentences.enumerated() {
            if isCancelled { return }
            
            print("   Processing sentence \(index + 1)/\(sentences.count): \(sentence)")
            
            // Announce phase for first sentence
            if index == 0 {
                let phaseText = "First, I will read you a sentence. Please repeat it back exactly as you hear it."
                
                if let taskRunnerInstance = taskRunner as? TaskRunner {
                    await MainActor.run {
                        taskRunnerInstance.transcript.append(
                            TranscriptItem(text: phaseText, type: .phaseAnnouncement, isHighlighted: true)
                        )
                    }
                }
                
                try? await audioManager.speak(phaseText)
                
                if let taskRunnerInstance = taskRunner as? TaskRunner {
                    await MainActor.run {
                        if let lastIndex = taskRunnerInstance.transcript.indices.last {
                            taskRunnerInstance.transcript[lastIndex].isHighlighted = false
                        }
                    }
                }
            }
            
            // Read sentence
            await taskRunner.transition(to: .presenting)
            
            if let taskRunnerInstance = taskRunner as? TaskRunner {
                await MainActor.run {
                    taskRunnerInstance.currentWord = sentence
                    taskRunnerInstance.transcript.append(
                        TranscriptItem(text: sentence, type: .sentence, isHighlighted: true)
                    )
                }
            }
            
            try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000) // 0.2s for UI
            try? await audioManager.speak(sentence)
            
            if let taskRunnerInstance = taskRunner as? TaskRunner {
                await MainActor.run {
                    if let lastIndex = taskRunnerInstance.transcript.lastIndex(where: { $0.text == sentence && $0.type == .sentence }) {
                        taskRunnerInstance.transcript[lastIndex].isHighlighted = false
                    }
                    taskRunnerInstance.currentWord = nil
                }
            }
            
            // Brief pause after reading sentence
            try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            // Prompt for response
            let promptText = "Now please repeat the sentence back to me exactly. You have 10 seconds. I'm listening."
            
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
            let totalChecks = Int(sentenceRecordingDuration / checkInterval)
            for i in 0..<totalChecks {
                if isCancelled {
                    print("🛑 LanguageTask: Task cancelled during recording (check \(i + 1)/\(totalChecks))")
                    break
                }
                try? await _Concurrency.Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
            }
            
            if isCancelled {
                print("🛑 LanguageTask: Task cancelled during recording, processing partial data")
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
            let (score, isCorrect) = scoreSentence(transcription ?? "", expected: sentence)
            
            // Get sessionId if not already stored
            if sessionId == nil, let response = response {
                sessionId = response.sessionId
            }
            
            // Update response with scoring data
            if var currentResponse = response {
                let sentenceWords = sentence.split(separator: " ").map { String($0) }
                currentResponse.score = score
                currentResponse.responseText = transcription
                currentResponse.correctWords = isCorrect ? sentenceWords : []
                currentResponse.expectedWords = sentenceWords
                currentResponse.updatedAt = Date()
                
                try? await dataController.updateItemResponse(currentResponse)
                print("✅ LanguageTask: Sentence \(index + 1) scored - \(isCorrect ? "Correct" : "Incorrect") (score: \(score))")
            } else {
                print("⚠️ LanguageTask: No response available for sentence \(index + 1)")
            }
        }
    }
    
    private func runFluency() async throws {
        print("\n📋 LanguageTask: Starting Phase 2 - Letter Fluency")
        currentPhase = .fluency
        
        // Announce phase
        let phaseText = "For this part, I want you to name as many words as you can that begin with the letter F. You have 30 seconds. Ready? Begin."
        
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                taskRunnerInstance.transcript.append(
                    TranscriptItem(text: phaseText, type: .fluencyPrompt, isHighlighted: true)
                )
            }
        }
        
        try? await audioManager.speak(phaseText)
        
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
        let totalChecks = Int(fluencyRecordingDuration / checkInterval)
        for i in 0..<totalChecks {
            if isCancelled {
                print("🛑 LanguageTask: Task cancelled during recording (check \(i + 1)/\(totalChecks))")
                break
            }
            try? await _Concurrency.Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
        }
        
        if isCancelled {
            print("🛑 LanguageTask: Task cancelled during recording, processing partial data")
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
            let (score, wordCount) = scoreFluency(transcription ?? "")
            
            // Get sessionId if not already stored
            if sessionId == nil, let response = response {
                sessionId = response.sessionId
            }
            
            // Update response with scoring data
            if var currentResponse = response {
                currentResponse.score = score
                currentResponse.responseText = transcription
                currentResponse.correctWords = wordCount > 10 ? ["passed"] : ["failed"]
                currentResponse.expectedWords = ["threshold: >10 words"]
                currentResponse.updatedAt = Date()
                
                try? await dataController.updateItemResponse(currentResponse)
                print("✅ LanguageTask: Fluency scored - \(wordCount) words (score: \(score))")
            } else {
                print("⚠️ LanguageTask: No response available for fluency")
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
    
    /// Scores sentence repetition - must be exact word match
    /// Returns: (score: 0.0 or 1.0, isCorrect: Bool)
    private func scoreSentence(_ transcription: String, expected: String) -> (score: Double, isCorrect: Bool) {
        // Normalize both strings
        let normalizedTranscription = transcription.lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let normalizedExpected = expected.lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Split into words
        let transcriptionWords = normalizedTranscription.split(separator: " ").map { String($0) }
        let expectedWords = normalizedExpected.split(separator: " ").map { String($0) }
        
        // Must match exactly word-by-word in order
        if transcriptionWords.count != expectedWords.count {
            print("   ❌ Sentence scoring: Word count mismatch (\(transcriptionWords.count) vs \(expectedWords.count))")
            return (0.0, false)
        }
        
        for (index, expectedWord) in expectedWords.enumerated() {
            if index >= transcriptionWords.count || transcriptionWords[index] != expectedWord {
                print("   ❌ Sentence scoring: Word mismatch at position \(index)")
                return (0.0, false)
            }
        }
        
        print("   ✅ Sentence scoring: Exact match")
        return (1.0, true)
    }
    
    /// Scores fluency - counts words starting with F
    /// Returns: (score: 0.0 or 1.0, wordCount: Int)
    private func scoreFluency(_ transcription: String) -> (score: Double, wordCount: Int) {
        // Normalize transcription
        let normalized = transcription.lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Split into words
        let words = normalized.split(separator: " ").map { String($0) }
        
        // Filter words starting with 'f'
        let fWords = words.filter { word in
            !word.isEmpty && word.first == "f"
        }
        
        // Count unique words (basic - no proper noun/number filtering for v1)
        let uniqueWords = Set(fWords)
        let wordCount = uniqueWords.count
        
        // Score: >10 words = 1.0, ≤10 words = 0.0
        let score = wordCount > 10 ? 1.0 : 0.0
        
        print("   📊 Fluency scoring: \(wordCount) unique words starting with F (score: \(score))")
        
        return (score, wordCount)
    }
}

