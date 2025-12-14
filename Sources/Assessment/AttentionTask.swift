import Foundation
import AudioToolbox

/// Attention Task implementation.
/// Tests attention through 4 sequential phases:
/// 1. Digit Span Forward (5 digits)
/// 2. Digit Span Backward (2 digits)
/// 3. Letter Tapping (30 letters, tap on A's)
/// 4. Serial 7s (subtract 7 from 100, 5 iterations)
class AttentionTask: Task {
    let id: UUID
    let title: String = "Attention Task"
    let instructions: TaskInstructions = .text("This is an attention task with multiple phases. Please follow the instructions carefully.")
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
        case digitSpanForward
        case digitSpanBackward
        case letterTapping
        case serial7s
    }
    
    private var currentPhase: Phase = .digitSpanForward
    private var isCancelled = false
    
    // Phase 1: Digit Span Forward
    private var forwardDigits: [Int] = []
    
    // Phase 2: Digit Span Backward
    private var backwardDigits: [Int] = []
    
    // Phase 3: Letter Tapping
    private var letterSequence: [String] = []
    private var expectedAPositions: [Int] = []
    private var tapTimestamps: [Date] = []
    private var tapLetterIndices: [Int] = []
    private var letterStartTime: Date?
    private var letterTimings: [(index: Int, startTime: Date, endTime: Date)] = []
    
    // Phase 4: Serial 7s
    private let serial7sStart = 100
    private let serial7sExpected = [93, 86, 79, 72, 65]
    private var serial7sAnswers: [Int?] = []
    
    // Constants
    private let digitPauseDuration: TimeInterval = 0.8
    private let letterPauseDuration: TimeInterval = 0.6
    private let recordingDuration: TimeInterval = 10.0
    private let transcriptionPollInterval: TimeInterval = 0.5
    private let transcriptionMaxWaitTime: TimeInterval = 30.0
    
    // Tap callback for letter tapping phase
    var onTapDetected: ((Date) -> Void)?
    
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
        
        print("🎯 AttentionTask: Initialized with ID: \(id)")
        print("   - DataController instance: \(ObjectIdentifier(dataController as AnyObject))")
    }
    
    func start() async throws {
        print("🎯 AttentionTask: Starting task (id: \(id))")
        isCancelled = false
        
        // Get sessionId from the first response if available
        if let firstResponse = try? await getCurrentResponse() {
            sessionId = firstResponse.sessionId
            print("✅ AttentionTask: Retrieved sessionId from existing response: \(sessionId?.uuidString ?? "nil")")
        }
        
        // Clear transcript
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                taskRunnerInstance.currentWord = nil
                taskRunnerInstance.transcript = []
            }
        }
        
        // Intro explanation
        let introText = "Welcome to the attention task. This test has four parts. I will guide you through each part with spoken instructions. Please listen carefully and follow the directions. Let's begin."
        
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                taskRunnerInstance.transcript.append(
                    TranscriptItem(text: introText, type: .instruction, isHighlighted: true)
                )
            }
        }
        
        print("🔊 AttentionTask: Speaking intro")
        try? await audioManager.speak(introText)
        
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                if let lastIndex = taskRunnerInstance.transcript.indices.last {
                    taskRunnerInstance.transcript[lastIndex].isHighlighted = false
                }
            }
        }
        
        // Phase 1: Digit Span Forward
        try await runDigitSpanForward()
        
        if isCancelled { return }
        
        // Transition to Phase 2
        let transition1Text = "Good. Now moving to the second part."
        try? await audioManager.speak(transition1Text)
        try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000) // 1 second pause
        
        // Phase 2: Digit Span Backward
        try await runDigitSpanBackward()
        
        if isCancelled { return }
        
        // Transition to Phase 3
        let transition2Text = "Well done. Now for the third part."
        try? await audioManager.speak(transition2Text)
        try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000) // 1 second pause
        
        // Phase 3: Letter Tapping
        try await runLetterTapping()
        
        if isCancelled { return }
        
        // Transition to Phase 4
        let transition3Text = "Excellent. Now for the final part."
        try? await audioManager.speak(transition3Text)
        try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000) // 1 second pause
        
        // Phase 4: Serial 7s
        if !isCancelled {
            try await runSerial7s()
        }
        
        // Always transition to completed, even if cancelled (so results can be shown)
        if !isCancelled {
            let completionText = "Excellent work. You have completed all four parts of the attention task. Thank you for your participation."
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
            print("✅ AttentionTask: Task fully completed")
        } else {
            print("🛑 AttentionTask: Task was cancelled, transitioning to completed to show partial results")
            await taskRunner.transition(to: .completed)
        }
    }
    
    func stop() async throws {
        print("🛑 AttentionTask: stop() called, cancelling task")
        isCancelled = true
    }
    
    func captureResponse(_ response: String) async throws {
        // Not used directly - handled via DataController updates in start()
    }
    
    // MARK: - Phase Implementations
    
    private func runDigitSpanForward() async throws {
        print("\n📋 AttentionTask: Starting Phase 1 - Digit Span Forward")
        currentPhase = .digitSpanForward
        
        // Generate 5 random digits
        forwardDigits = (0..<5).map { _ in Int.random(in: 0...9) }
        print("   Generated digits: \(forwardDigits)")
        
        // Announce phase
        let phaseText = "First, I will read you 5 numbers. Please repeat them back in the same order."
        
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
        
        // Read digits
        await taskRunner.transition(to: .presenting)
        
        for (_, digit) in forwardDigits.enumerated() {
            if isCancelled { return }
            
            let digitString = String(digit)
            
            if let taskRunnerInstance = taskRunner as? TaskRunner {
                await MainActor.run {
                    taskRunnerInstance.currentWord = digitString
                    taskRunnerInstance.transcript.append(
                        TranscriptItem(text: digitString, type: .digit, isHighlighted: true)
                    )
                }
            }
            
            try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000) // 0.2s for UI
            try? await audioManager.speak(digitString)
            
            if let taskRunnerInstance = taskRunner as? TaskRunner {
                await MainActor.run {
                    if let lastIndex = taskRunnerInstance.transcript.lastIndex(where: { $0.text == digitString && $0.type == .digit }) {
                        taskRunnerInstance.transcript[lastIndex].isHighlighted = false
                    }
                }
            }
            
            try? await _Concurrency.Task.sleep(nanoseconds: UInt64(digitPauseDuration * 1_000_000_000))
        }
        
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                taskRunnerInstance.currentWord = nil
            }
        }
        
        // Prompt for response
        let promptText = "Now please repeat the numbers back in the same order. You have 10 seconds. I'm listening."
        
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
                print("🛑 AttentionTask: Task cancelled during recording (check \(i + 1)/\(totalChecks))")
                break
            }
            try? await _Concurrency.Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
        }
        
        if isCancelled {
            print("🛑 AttentionTask: Task cancelled during recording, processing partial data")
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
        let (_, isCorrect) = scoreDigitSpan(transcription ?? "", expected: forwardDigits, reverse: false)
        
        // Extract digits for display (convert words like "nine" to "9")
        let extractedDigits = extractDigitsFromTranscription(transcription ?? "")
        let formattedResponse = extractedDigits.map { String($0) }.joined(separator: " ")
        
        // Update response
        if var currentResponse = response {
            currentResponse.score = isCorrect ? 1.0 : 0.0
            currentResponse.responseText = formattedResponse.isEmpty ? transcription : formattedResponse
            currentResponse.expectedWords = forwardDigits.map { String($0) }
            currentResponse.correctWords = isCorrect ? forwardDigits.map { String($0) } : []
            currentResponse.updatedAt = Date()
            
            try? await dataController.updateItemResponse(currentResponse)
            print("✅ AttentionTask: Phase 1 scored - \(isCorrect ? "Correct" : "Incorrect") (score: \(currentResponse.score ?? 0))")
        }
    }
    
    private func runDigitSpanBackward() async throws {
        print("\n📋 AttentionTask: Starting Phase 2 - Digit Span Backward")
        currentPhase = .digitSpanBackward
        
        // Generate 2 random digits
        backwardDigits = (0..<2).map { _ in Int.random(in: 0...9) }
        print("   Generated digits: \(backwardDigits)")
        
        // Announce phase
        let phaseText = "Now I will read you 2 numbers. Please repeat them back in reverse order."
        
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
        
        // Read digits
        await taskRunner.transition(to: .presenting)
        
        for (_, digit) in backwardDigits.enumerated() {
            if isCancelled { return }
            
            let digitString = String(digit)
            
            if let taskRunnerInstance = taskRunner as? TaskRunner {
                await MainActor.run {
                    taskRunnerInstance.currentWord = digitString
                    taskRunnerInstance.transcript.append(
                        TranscriptItem(text: digitString, type: .digit, isHighlighted: true)
                    )
                }
            }
            
            try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
            try? await audioManager.speak(digitString)
            
            if let taskRunnerInstance = taskRunner as? TaskRunner {
                await MainActor.run {
                    if let lastIndex = taskRunnerInstance.transcript.lastIndex(where: { $0.text == digitString && $0.type == .digit }) {
                        taskRunnerInstance.transcript[lastIndex].isHighlighted = false
                    }
                }
            }
            
            try? await _Concurrency.Task.sleep(nanoseconds: UInt64(digitPauseDuration * 1_000_000_000))
        }
        
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                taskRunnerInstance.currentWord = nil
            }
        }
        
        // Prompt for response
        let promptText = "Now please repeat the numbers back in reverse order. You have 10 seconds. I'm listening."
        
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
                print("🛑 AttentionTask: Task cancelled during recording (check \(i + 1)/\(totalChecks))")
                break
            }
            try? await _Concurrency.Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
        }
        
        if isCancelled {
            print("🛑 AttentionTask: Task cancelled during recording, processing partial data")
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
        let (_, isCorrect) = scoreDigitSpan(transcription ?? "", expected: backwardDigits, reverse: true)
        
        // The expected response is the reversed sequence
        let expectedResponse = backwardDigits.reversed().map { String($0) }
        
        // Extract digits for display (convert words like "nine" to "9")
        let extractedDigits = extractDigitsFromTranscription(transcription ?? "")
        let formattedResponse = extractedDigits.map { String($0) }.joined(separator: " ")
        
        // Update response
        if var currentResponse = response {
            currentResponse.score = isCorrect ? 1.0 : 0.0
            currentResponse.responseText = formattedResponse.isEmpty ? transcription : formattedResponse
            currentResponse.expectedWords = expectedResponse
            currentResponse.correctWords = isCorrect ? expectedResponse : []
            currentResponse.updatedAt = Date()
            
            try? await dataController.updateItemResponse(currentResponse)
            print("✅ AttentionTask: Phase 2 scored - \(isCorrect ? "Correct" : "Incorrect") (score: \(currentResponse.score ?? 0))")
        }
    }
    
    private func runLetterTapping() async throws {
        print("\n📋 AttentionTask: Starting Phase 3 - Letter Tapping")
        currentPhase = .letterTapping
        
        // Generate 30 random letters with 5-15 A's
        let numAs = Int.random(in: 5...15)
        var letters = Array(repeating: "A", count: numAs)
        let otherLetters = ["B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"]
        let remaining = 30 - numAs
        letters.append(contentsOf: (0..<remaining).map { _ in otherLetters.randomElement()! })
        letterSequence = letters.shuffled()
        
        // Track A positions
        expectedAPositions = letterSequence.enumerated().compactMap { $0.element == "A" ? $0.offset : nil }
        print("   Generated \(letterSequence.count) letters with \(expectedAPositions.count) A's at positions: \(expectedAPositions)")
        
        // Clear tap data
        tapTimestamps = []
        tapLetterIndices = []
        
        // Announce phase
        let phaseText = "For this part, I will read you a list of 30 letters. Please tap anywhere on the screen every time you hear the letter A. Tap only when you hear the letter A. Are you ready? Here we go."
        
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
        
        // Brief pause before starting
        try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Read letters
        await taskRunner.transition(to: .presenting)
        
        letterStartTime = Date()
        letterTimings = []
        
        // First pass: Read all letters and record their start times
        var letterStartTimes: [Date] = []
        
        for letter in letterSequence {
            if isCancelled { return }
            
            let letterStart = Date()
            letterStartTimes.append(letterStart)
            
            if let taskRunnerInstance = taskRunner as? TaskRunner {
                await MainActor.run {
                    taskRunnerInstance.currentWord = letter
                    taskRunnerInstance.transcript.append(
                        TranscriptItem(text: letter, type: .letter, isHighlighted: true)
                    )
                }
            }
            
            try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
            // Format to read just the letter name (not "Capital A")
            // Use the letter with a period to make TTS read it as a letter name, not "Capital [letter]"
            // The period helps TTS interpret it as a standalone letter
            try? await audioManager.speak("\(letter).")
            
            if let taskRunnerInstance = taskRunner as? TaskRunner {
                await MainActor.run {
                    if let lastIndex = taskRunnerInstance.transcript.lastIndex(where: { $0.text == letter && $0.type == .letter }) {
                        taskRunnerInstance.transcript[lastIndex].isHighlighted = false
                    }
                }
            }
            
            try? await _Concurrency.Task.sleep(nanoseconds: UInt64(letterPauseDuration * 1_000_000_000))
        }
        
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                taskRunnerInstance.currentWord = nil
            }
        }
        
        // Wait a bit for any final taps (allow taps up to 1 second after last letter)
        try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)
        
        // Now match taps to letters: each letter's window extends from its start until just before the next letter starts
        for (idx, letterStart) in letterStartTimes.enumerated() {
            // Window extends from this letter's start until just before next letter starts
            // For the last letter, extend window by letterPauseDuration + 1 second
            let windowEnd: Date
            if idx < letterStartTimes.count - 1 {
                // Window extends until just before next letter starts
                windowEnd = letterStartTimes[idx + 1]
            } else {
                // Last letter: extend window by pause duration + 1 second for final taps
                windowEnd = letterStart.addingTimeInterval(letterPauseDuration + 1.0)
            }
            
            letterTimings.append((index: idx, startTime: letterStart, endTime: windowEnd))
            
            // Match taps that occurred during this letter's window
            for tapTime in tapTimestamps {
                if tapTime >= letterStart && tapTime < windowEnd {
                    if !tapLetterIndices.contains(idx) {
                        tapLetterIndices.append(idx)
                    }
                }
            }
        }
        
        // Score letter tapping
        let errors = calculateLetterTappingErrors()
        let score = errors <= 2 ? 1.0 : 0.0
        
        print("✅ AttentionTask: Phase 3 scored - \(errors) errors (score: \(score))")
        
        // Get sessionId from previous response if not already stored
        if sessionId == nil {
            if let response = try? await getCurrentResponse() {
                sessionId = response.sessionId
            }
        }
        
        // Create response for letter tapping (no audio recording needed)
        // Store tapped positions in correctWords (positions where user actually tapped)
        // Expected A positions can be calculated from letterSequence in expectedWords
        if let sessionId = sessionId {
            let response = ItemResponse(
                sessionId: sessionId,
                taskId: id,
                responseText: "Letter tapping phase",
                score: score,
                correctWords: tapLetterIndices.map { String($0) }, // Store actual tapped positions
                expectedWords: letterSequence
            )
            _ = try? await dataController.createItemResponse(response)
        } else {
            print("⚠️ AttentionTask: No sessionId available for letter tapping response")
        }
    }
    
    private func runSerial7s() async throws {
        print("\n📋 AttentionTask: Starting Phase 4 - Serial 7s")
        currentPhase = .serial7s
        
        serial7sAnswers = []
        
        // Announce phase
        let phaseText = "For this final part, you will subtract 7 from 100, then continue subtracting 7 from each answer."
        
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
        
        // Single prompt for all subtractions
        let promptText = "Start with 100. What is 100 minus 7? Then continue subtracting 7 from each answer. Say all five answers out loud. You have 42 seconds. I'm listening."
        
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                taskRunnerInstance.transcript.append(
                    TranscriptItem(text: promptText, type: .calculationPrompt, isHighlighted: true)
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
        
        // Record all 5 answers in one continuous recording
        await taskRunner.transition(to: .recording)
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
        
        // Wait for all 5 answers (total ~50 seconds: 10s for first, 8s each for remaining 4)
        let totalWaitTime: TimeInterval = 10.0 + (8.0 * 4) // 42 seconds total
        try? await _Concurrency.Task.sleep(nanoseconds: UInt64(totalWaitTime * 1_000_000_000))
        
        if isCancelled { return }
        
        // Play end beep
        try? await audioManager.playBeep(soundID: SystemSoundID(1054)) // End beep (different pitch)
        
        // Evaluate
        await taskRunner.transition(to: .evaluating)
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
        
        let response = try? await getCurrentResponse()
        let audioClipId = response?.audioClipId
        
        let transcription = try? await waitForTranscription(audioClipId: audioClipId, maxWaitSeconds: transcriptionMaxWaitTime)
        let (score, correctCount) = scoreSerial7s(transcription ?? "")
        
        // Update response
        if var currentResponse = response {
            currentResponse.score = score
            currentResponse.responseText = transcription
            currentResponse.expectedWords = serial7sExpected.map { String($0) }
            currentResponse.updatedAt = Date()
            
            try? await dataController.updateItemResponse(currentResponse)
            print("✅ AttentionTask: Phase 4 scored - \(correctCount)/5 correct (score: \(score))")
        }
    }
    
    // MARK: - Helper Methods
    
    func recordTap(timestamp: Date) {
        print("👆 AttentionTask: Tap detected at \(timestamp)")
        // Only record taps during letter tapping phase
        if currentPhase == .letterTapping {
            tapTimestamps.append(timestamp)
            onTapDetected?(timestamp)
        }
    }
    
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
    
    /// Extracts digits from transcription, converting number words to digits
    private func extractDigitsFromTranscription(_ transcription: String) -> [Int] {
        let normalized = transcription.lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        var extractedDigits: [Int] = []
        let words = normalized.split(separator: " ")
        
        for word in words {
            // Try to parse as number word
            if let digit = parseNumberWord(String(word)) {
                extractedDigits.append(digit)
            } else if let digit = Int(String(word)) {
                extractedDigits.append(digit)
            }
        }
        
        return extractedDigits
    }
    
    private func scoreDigitSpan(_ transcription: String, expected: [Int], reverse: Bool) -> (score: Double, isCorrect: Bool) {
        let extractedDigits = extractDigitsFromTranscription(transcription)
        
        let expectedSequence = reverse ? expected.reversed() : expected
        let isCorrect = extractedDigits == expectedSequence
        
        return (isCorrect ? 1.0 : 0.0, isCorrect)
    }
    
    private func parseNumberWord(_ word: String) -> Int? {
        let numberWords: [String: Int] = [
            "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4,
            "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9
        ]
        return numberWords[word.lowercased()]
    }
    
    private func calculateLetterTappingErrors() -> Int {
        // Use tapLetterIndices which were matched during letter reading
        var errors = 0
        
        // Count missing A's (expected but not tapped)
        for aPosition in expectedAPositions {
            if !tapLetterIndices.contains(aPosition) {
                errors += 1
            }
        }
        
        // Count incorrect taps (tapped but not an A)
        for tapIndex in tapLetterIndices {
            if !expectedAPositions.contains(tapIndex) {
                errors += 1
            }
        }
        
        return errors
    }
    
    private func scoreSerial7s(_ transcription: String) -> (score: Double, correctCount: Int) {
        let normalized = transcription.lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Extract numbers from transcription
        var extractedNumbers: [Int] = []
        let words = normalized.split(separator: " ")
        
        for word in words {
            if let number = parseNumber(String(word)) {
                extractedNumbers.append(number)
            }
        }
        
        // Match extracted numbers to expected sequence
        var correctCount = 0
        for (index, expected) in serial7sExpected.enumerated() {
            if index < extractedNumbers.count && extractedNumbers[index] == expected {
                correctCount += 1
            }
        }
        
        // Score: 3 (4-5 correct), 2 (2-3 correct), 1 (1 correct), 0 (0 correct)
        let score: Double
        if correctCount >= 4 {
            score = 3.0
        } else if correctCount >= 2 {
            score = 2.0
        } else if correctCount >= 1 {
            score = 1.0
        } else {
            score = 0.0
        }
        
        return (score, correctCount)
    }
    
    private func parseNumber(_ word: String) -> Int? {
        // Try direct integer parsing
        if let number = Int(word) {
            return number
        }
        
        // Try number word parsing (for numbers like "ninety-three")
        let numberWords: [String: Int] = [
            "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4,
            "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
            "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
            "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
            "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
            "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
        ]
        
        // Simple parsing for compound numbers (e.g., "ninety-three")
        let parts = word.split(separator: "-")
        if parts.count == 2 {
            if let tens = numberWords[String(parts[0])], let ones = numberWords[String(parts[1])] {
                return tens + ones
            }
        }
        
        return numberWords[word.lowercased()]
    }
}


