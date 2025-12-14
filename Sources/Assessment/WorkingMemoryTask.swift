import Foundation

/// Working Memory Task implementation.
/// Reads 5 words, records user responses for 10 seconds per trial (2 trials),
/// transcribes responses, scores them against expected words.
@available(iOS 13.0, macOS 10.15, *)
class WorkingMemoryTask: Task {
    let id: UUID
    let title: String = "Working Memory Task"
    let instructions: TaskInstructions = .text("You will hear 5 words. After hearing all words, repeat them back in the same order. You have 10 seconds to respond.")
    let expectedInputType: TaskInputType = .audio
    let timingRequirements: TimingRequirements? = TimingRequirements(maxDuration: 10.0)
    let scoringMetadata: [String: Any]? = nil
    
    private let audioManager: AudioManagerProtocol
    private let taskRunner: TaskRunnerProtocol
    private let dataController: DataControllerProtocol
    
    // Constants
    private let expectedWords = ["chair", "book", "hand", "road", "cloud"]
    private let numberOfTrials = 2
    private let recordingDuration: TimeInterval = 10.0
    private let wordPauseDuration: TimeInterval = 1.0
    private let transcriptionPollInterval: TimeInterval = 0.5
    private let transcriptionMaxWaitTime: TimeInterval = 3.0
    
    // State tracking
    private var isCancelled = false
    
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
        
        // Verify we're using the same DataController as TaskRunner
        if let taskRunnerDataController = taskRunner as? TaskRunner {
            // Cast to AnyObject for identity comparison (since DataController is a class)
            if (dataController as AnyObject) !== (taskRunnerDataController.dataController as AnyObject) {
                print("⚠️ WorkingMemoryTask: WARNING - DataController differs from TaskRunner's!")
            } else {
                print("✅ WorkingMemoryTask: Using same DataController as TaskRunner")
            }
        }
        print("🎯 WorkingMemoryTask: Initialized with ID: \(id)")
        print("   - DataController instance: \(ObjectIdentifier(dataController as AnyObject))")
    }
    
    func start() async throws {
        print("🎯 WorkingMemoryTask: Starting task (id: \(id))")
        isCancelled = false

        // Clear any previous word display and transcript
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                taskRunnerInstance.currentWord = nil
                taskRunnerInstance.transcript = []
            }
        }

        // Intro explanation
        let introText = "Hi! I'm going to read you 5 words. After I finish, please repeat them back to me in the same order. You'll have 10 seconds to respond. We'll do this two times."
        
        // Add to transcript
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                taskRunnerInstance.transcript.append(
                    TranscriptItem(text: introText, type: .instruction, isHighlighted: true)
                )
            }
        }
        
        print("🔊 WorkingMemoryTask: Speaking intro explanation")
        try? await audioManager.speak(introText)
        print("✅ WorkingMemoryTask: Intro explanation completed")
        
        // Unhighlight intro after speaking
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                if let lastIndex = taskRunnerInstance.transcript.indices.last {
                    taskRunnerInstance.transcript[lastIndex].isHighlighted = false
                }
            }
        }
        
        // Loop for 2 trials
        for trialNumber in 1...numberOfTrials {
            print("\n📋 WorkingMemoryTask: Starting Trial \(trialNumber)/\(numberOfTrials)")
            
            if isCancelled {
                print("🛑 WorkingMemoryTask: Task cancelled, stopping trial \(trialNumber)")
                break
            }
            
            // Ensure we're in presenting state for word reading
            if trialNumber == 1 {
                // For Trial 1, ensure we're in presenting state (should already be, but make sure)
                print("🔄 WorkingMemoryTask: Ensuring .presenting state for Trial 1")
                await taskRunner.transition(to: .presenting)
            } else {
                // For Trial 2, transition back to presenting and announce
                print("🔄 WorkingMemoryTask: Transitioning to .presenting state for Trial \(trialNumber)")
                await taskRunner.transition(to: .presenting)
                let trialStartText = "Great! Let's do the second round now."
                
                // Add to transcript
                if let taskRunnerInstance = taskRunner as? TaskRunner {
                    await MainActor.run {
                        taskRunnerInstance.transcript.append(
                            TranscriptItem(text: trialStartText, type: .trialAnnouncement, isHighlighted: true)
                        )
                    }
                }
                
                print("🔊 WorkingMemoryTask: Announcing Trial \(trialNumber) start")
                try? await audioManager.speak(trialStartText)
                print("✅ WorkingMemoryTask: Trial \(trialNumber) announcement completed")
                
                // Unhighlight after speaking
                if let taskRunnerInstance = taskRunner as? TaskRunner {
                    await MainActor.run {
                        if let lastIndex = taskRunnerInstance.transcript.indices.last {
                            taskRunnerInstance.transcript[lastIndex].isHighlighted = false
                        }
                    }
                }
            }
            
            // Read 5 words with pauses
            print("📖 WorkingMemoryTask: Reading \(expectedWords.count) words: \(expectedWords.joined(separator: ", "))")
            for (index, word) in expectedWords.enumerated() {
                if isCancelled {
                    print("🛑 WorkingMemoryTask: Task cancelled during word reading")
                    break
                }
                
                // Update UI to show current word BEFORE speaking
                // This ensures the word is visible immediately
                if let taskRunnerInstance = taskRunner as? TaskRunner {
                    await MainActor.run {
                        print("  📺 WorkingMemoryTask: Setting currentWord to '\(word)' on main thread")
                        taskRunnerInstance.currentWord = word
                        
                        // Add word to transcript and highlight it
                        let transcriptItem = TranscriptItem(text: word, type: .word, isHighlighted: true)
                        taskRunnerInstance.transcript.append(transcriptItem)
                        
                        print("  ✅ WorkingMemoryTask: currentWord set to '\(taskRunnerInstance.currentWord ?? "nil")'")
                    }
                    print("  📺 WorkingMemoryTask: Displaying word \(index + 1)/\(expectedWords.count): '\(word)'")
                    
                    // Small delay to ensure UI updates before speaking
                    try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds for UI to render
                }
                
                print("  🔊 WorkingMemoryTask: Speaking word \(index + 1)/\(expectedWords.count): '\(word)'")
                try? await audioManager.speak(word)
                print("  ✅ WorkingMemoryTask: Word '\(word)' spoken, pausing \(wordPauseDuration)s")
                
                // Keep word visible during pause, checking for cancellation
                let pauseChecks = Int(wordPauseDuration / 0.5)
                for _ in 0..<pauseChecks {
                    if isCancelled { break }
                    try? await _Concurrency.Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                }
                if isCancelled {
                    print("🛑 WorkingMemoryTask: Task cancelled during word pause")
                    break
                }
                
                // Unhighlight word after pause
                if let taskRunnerInstance = taskRunner as? TaskRunner {
                    await MainActor.run {
                        // Find and unhighlight the last word item
                        if let lastWordIndex = taskRunnerInstance.transcript.lastIndex(where: { $0.text == word && $0.type == .word }) {
                            taskRunnerInstance.transcript[lastWordIndex].isHighlighted = false
                        }
                    }
                }
            }
            
            // Clear the displayed word after reading all words
            if let taskRunnerInstance = taskRunner as? TaskRunner {
                await MainActor.run {
                    taskRunnerInstance.currentWord = nil
                }
                print("📺 WorkingMemoryTask: Cleared displayed word")
            }
            
            if isCancelled {
                print("🛑 WorkingMemoryTask: Task cancelled after word reading")
                break
            }
            
            // Prompt to repeat words
            let promptText = "Now it's your turn! Please repeat those words back to me. You have 10 seconds."
            
            // Add to transcript
            if let taskRunnerInstance = taskRunner as? TaskRunner {
                await MainActor.run {
                    taskRunnerInstance.transcript.append(
                        TranscriptItem(text: promptText, type: .prompt, isHighlighted: true)
                    )
                }
            }
            
            print("🔊 WorkingMemoryTask: Prompting user to repeat words")
            try? await audioManager.speak(promptText)
            print("✅ WorkingMemoryTask: Prompt completed")
            
            // Unhighlight prompt after speaking
            if let taskRunnerInstance = taskRunner as? TaskRunner {
                await MainActor.run {
                    if let lastIndex = taskRunnerInstance.transcript.indices.last {
                        taskRunnerInstance.transcript[lastIndex].isHighlighted = false
                    }
                }
            }
            
            // Ensure word is cleared before recording
            if let taskRunnerInstance = taskRunner as? TaskRunner {
                await MainActor.run {
                    taskRunnerInstance.currentWord = nil
                }
            }
            
            // Play beep to indicate when to start speaking
            print("🔔 WorkingMemoryTask: Playing beep before recording starts")
            try? await audioManager.playBeep(soundID: 1057) // Start beep
            print("✅ WorkingMemoryTask: Beep played")
            
            // Transition to recording state (TaskRunner will create ItemResponse and AudioClip)
            print("🎙️ WorkingMemoryTask: Transitioning to .recording state")
            await taskRunner.transition(to: .recording)
            print("✅ WorkingMemoryTask: Recording state transitioned, waiting for ItemResponse creation...")
            
            // Small delay to ensure ItemResponse is created by TaskRunner
            try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            // Wait exactly 10 seconds, checking for cancellation every 0.5 seconds
            print("⏱️ WorkingMemoryTask: Starting \(recordingDuration)s recording period")
            let checkInterval: TimeInterval = 0.5
            let totalChecks = Int(recordingDuration / checkInterval)
            for i in 0..<totalChecks {
                if isCancelled {
                    print("🛑 WorkingMemoryTask: Task cancelled during recording (check \(i + 1)/\(totalChecks))")
                    break
                }
                try? await _Concurrency.Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
            }
            
            if isCancelled {
                print("🛑 WorkingMemoryTask: Task cancelled during recording")
                // Still process whatever was recorded before cancellation
                print("📊 WorkingMemoryTask: Processing partial data from cancelled trial")
            } else {
                print("✅ WorkingMemoryTask: Recording period completed")
            }
            
            // Transition to evaluating state (TaskRunner will stop recording and start transcription)
            print("🔄 WorkingMemoryTask: Transitioning to .evaluating state (stopping recording, starting transcription)")
            await taskRunner.transition(to: .evaluating)
            
            // Small delay to ensure recording has stopped
            try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            // Fetch current ItemResponse (even if cancelled, process what we have)
            print("🔍 WorkingMemoryTask: Fetching ItemResponse for trial \(trialNumber)")
            if let currentResponse = try? await getCurrentResponse(),
               let audioClipId = currentResponse.audioClipId {
                print("✅ WorkingMemoryTask: Found ItemResponse (id: \(currentResponse.id), audioClipId: \(audioClipId))")
                
                // Wait for transcription (with timeout protection and cancellation checks)
                print("📝 WorkingMemoryTask: Waiting for transcription (max \(transcriptionMaxWaitTime)s)...")
                let transcription = try? await waitForTranscription(audioClipId: audioClipId, maxWaitSeconds: transcriptionMaxWaitTime)
                
                if let transcription = transcription {
                    print("✅ WorkingMemoryTask: Transcription received: \"\(transcription)\"")
                } else {
                    print("⚠️ WorkingMemoryTask: Transcription failed or timed out for trial \(trialNumber)")
                    print("   Continuing with empty transcription for scoring...")
                }
                
                // Score response (always proceed, even with empty transcription or if cancelled)
                print("📊 WorkingMemoryTask: Scoring response...")
                let (score, correctWords) = scoreResponse(transcription ?? "", expectedWords: expectedWords)
                print("📊 WorkingMemoryTask: Score: \(String(format: "%.2f", score)) (\(correctWords.count)/\(expectedWords.count))")
                print("   - Correct words: \(correctWords.isEmpty ? "None" : correctWords.joined(separator: ", "))")
                print("   - Expected words: \(expectedWords.joined(separator: ", "))")
                
                // Update ItemResponse with scoring data
                var updatedResponse = currentResponse
                updatedResponse.score = score
                updatedResponse.correctWords = correctWords
                updatedResponse.expectedWords = expectedWords
                updatedResponse.responseText = transcription
                updatedResponse.updatedAt = Date()
                
                print("💾 WorkingMemoryTask: Updating ItemResponse with scoring data...")
                print("   - Response ID: \(updatedResponse.id)")
                print("   - Score: \(updatedResponse.score?.description ?? "nil")")
                print("   - Correct words count: \(updatedResponse.correctWords?.count ?? 0)")
                print("   - Expected words: \(updatedResponse.expectedWords?.joined(separator: ", ") ?? "nil")")
                do {
                    try await dataController.updateItemResponse(updatedResponse)
                    print("✅ WorkingMemoryTask: ItemResponse updated successfully for trial \(trialNumber)")
                    
                    // Verify it was saved
                    if let saved = try? await dataController.fetchItemResponse(id: updatedResponse.id) {
                        print("   ✅ Verification: ItemResponse saved correctly")
                        print("      - Saved score: \(saved.score?.description ?? "nil")")
                        print("      - Saved correctWords: \(saved.correctWords?.count ?? 0)")
                    } else {
                        print("   ⚠️ Verification: Could not fetch saved ItemResponse")
                    }
                } catch {
                    print("⚠️ WorkingMemoryTask: Failed to update ItemResponse for trial \(trialNumber): \(error)")
                }
                
                print("✅ WorkingMemoryTask: Trial \(trialNumber) processed\n")
            } else {
                print("⚠️ WorkingMemoryTask: Failed to fetch ItemResponse or audioClipId for trial \(trialNumber)")
                print("   - CurrentResponse: \(String(describing: try? await getCurrentResponse()))")
                // If cancelled and no response exists, create a zero-scored response
                if isCancelled {
                    print("📊 WorkingMemoryTask: Task cancelled with no response - creating zero-scored response")
                    if let sessionId = (taskRunner as? TaskRunner)?.currentSessionId {
                        let zeroResponse = ItemResponse(
                            sessionId: sessionId,
                            taskId: self.id,
                            responseText: nil,
                            score: 0.0,
                            correctWords: [],
                            expectedWords: expectedWords
                        )
                        _ = try? await dataController.createItemResponse(zeroResponse)
                    }
                }
            }
            
            // Exit immediately if cancelled
            if isCancelled {
                print("🛑 WorkingMemoryTask: Exiting trial loop due to cancellation")
                break
            }
        }
        
        if !isCancelled {
            // Completion message
            print("🎉 WorkingMemoryTask: All trials completed, speaking completion message")
            let completionText = "Great job! You've completed the working memory task."
            try? await audioManager.speak(completionText)
            print("✅ WorkingMemoryTask: Task fully completed")
            
            // Transition to completed state
            print("🔄 WorkingMemoryTask: Transitioning to .completed state")
            await taskRunner.transition(to: .completed)
            print("✅ WorkingMemoryTask: State transitioned to .completed")
        } else {
            print("🛑 WorkingMemoryTask: Task was cancelled, skipping completion message")
            // Still transition to completed even if cancelled
            await taskRunner.transition(to: .completed)
        }
    }
    
    func stop() async throws {
        print("🛑 WorkingMemoryTask: stop() called, cancelling task")
        isCancelled = true
        // TTS will stop automatically when cancelled or when new speech starts
    }
    
    func captureResponse(_ response: String) async throws {
        // Not used directly - handled via DataController updates in start()
    }
    
    // MARK: - Helper Methods
    
    /// Fetches the most recent ItemResponse for this task
    /// CRITICAL: Must sort by createdAt to ensure we get the most recently created response
    /// For multiple trials, we want the one that was just created (hasn't been scored yet)
    private func getCurrentResponse() async throws -> ItemResponse? {
        print("🔍 WorkingMemoryTask.getCurrentResponse: Fetching all ItemResponses...")
        let allResponses = try await dataController.fetchAllItemResponses()
        print("   - Total responses found: \(allResponses.count)")
        let taskResponses = allResponses.filter { $0.taskId == self.id }
        print("   - Responses for this task (id: \(self.id)): \(taskResponses.count)")
        
        // CRITICAL: Sort by createdAt DESCENDING (most recent first)
        // This ensures we get the response that was just created for this trial
        let sortedResponses = taskResponses.sorted { $0.createdAt > $1.createdAt }
        
        // Prefer responses that haven't been scored yet (for the current trial)
        // But if all are scored, take the most recent one
        let unscoredResponse = sortedResponses.first { $0.score == nil }
        let mostRecent = unscoredResponse ?? sortedResponses.first
        
        if let response = mostRecent {
            print("   - Selected response: id=\(response.id), createdAt=\(response.createdAt), score=\(response.score?.description ?? "nil"), audioClipId=\(response.audioClipId?.uuidString ?? "nil")")
            // Log all responses for debugging
            for (index, response) in sortedResponses.enumerated() {
                print("     Response \(index + 1): id=\(response.id), createdAt=\(response.createdAt), score=\(response.score?.description ?? "nil")")
            }
        } else {
            print("   - No responses found for this task")
        }
        
        return mostRecent
    }
    
    /// Polls AudioClip until transcription is available or timeout
    private func waitForTranscription(audioClipId: UUID, maxWaitSeconds: TimeInterval = 30.0) async throws -> String? {
        let startTime = Date()
        var pollCount = 0
        let maxPolls = Int(maxWaitSeconds / transcriptionPollInterval) + 1
        
        print("   🔄 WorkingMemoryTask.waitForTranscription: Starting polling (audioClipId: \(audioClipId), maxWait: \(maxWaitSeconds)s, maxPolls: \(maxPolls))")
        
        while pollCount < maxPolls {
            if isCancelled {
                print("   🛑 WorkingMemoryTask.waitForTranscription: Task cancelled during polling")
                return nil
            }
            
            pollCount += 1
            let elapsed = Date().timeIntervalSince(startTime)
            
            // Safety check - ensure we don't exceed maxWaitSeconds
            if elapsed >= maxWaitSeconds {
                print("   ⏰ WorkingMemoryTask.waitForTranscription: Max wait time reached (\(String(format: "%.1f", elapsed))s)")
                break
            }
            
            if let audioClip = try? await dataController.fetchAudioClip(id: audioClipId) {
                if let transcription = audioClip.transcription, !transcription.isEmpty {
                    print("   ✅ WorkingMemoryTask.waitForTranscription: Transcription found after \(String(format: "%.1f", elapsed))s (\(pollCount) polls)")
                    return transcription
                } else {
                    if pollCount % 10 == 0 || pollCount == 1 { // Log first poll and every 10th poll
                        print("   ⏳ WorkingMemoryTask.waitForTranscription: Poll \(pollCount), elapsed \(String(format: "%.1f", elapsed))s, transcription still nil")
                    }
                }
            } else {
                if pollCount % 10 == 0 || pollCount == 1 {
                    print("   ⚠️ WorkingMemoryTask.waitForTranscription: Poll \(pollCount), AudioClip not found")
                }
            }
            
            // Wait before next poll
            try? await _Concurrency.Task.sleep(nanoseconds: UInt64(transcriptionPollInterval * 1_000_000_000))
        }
        
        // Timeout
        let elapsed = Date().timeIntervalSince(startTime)
        print("   ⚠️ WorkingMemoryTask.waitForTranscription: Timeout after \(String(format: "%.1f", elapsed))s (\(pollCount) polls) - proceeding without transcription")
        return nil
    }
    
    /// Scores the transcription against expected words
    /// Returns: (score as fraction, array of correct words)
    private func scoreResponse(_ transcription: String, expectedWords: [String]) -> (score: Double, correctWords: [String]) {
        print("   📝 WorkingMemoryTask.scoreResponse: Scoring transcription")
        print("      - Raw transcription: \"\(transcription)\"")
        
        // Normalize transcription: lowercase, remove punctuation
        let normalized = transcription.lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("      - Normalized: \"\(normalized)\"")
        
        // Split into words
        let words = normalized.split(separator: " ").map { String($0) }
        print("      - Words extracted: \(words.count) words - [\(words.joined(separator: ", "))]")
        
        var correctWords: [String] = []
        
        // Compare word-by-word in order
        for (index, expectedWord) in expectedWords.enumerated() {
            if index < words.count {
                let spokenWord = words[index].lowercased()
                let expectedWordLower = expectedWord.lowercased()
                
                // Exact match (case-insensitive), but plurals are NOT matches
                if spokenWord == expectedWordLower {
                    correctWords.append(expectedWord)
                    print("      - ✅ Word \(index + 1): '\(spokenWord)' matches '\(expectedWord)'")
                } else {
                    print("      - ❌ Word \(index + 1): '\(spokenWord)' does NOT match '\(expectedWord)'")
                }
            } else {
                print("      - ⚠️ Word \(index + 1): No word provided (expected '\(expectedWord)')")
            }
        }
        
        // Calculate score as fraction
        let score = Double(correctWords.count) / Double(expectedWords.count)
        print("      - Final score: \(correctWords.count)/\(expectedWords.count) = \(String(format: "%.2f", score))")
        
        return (score, correctWords)
    }
}

