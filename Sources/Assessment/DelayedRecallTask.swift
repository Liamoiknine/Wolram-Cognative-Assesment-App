import Foundation

/// Delayed Recall Task implementation.
/// Asks user to recall the 5 words from the Working Memory task (first activity) without being told them.
/// Records user responses for 15 seconds, transcribes responses, scores them against expected words.
/// Scoring is based on word presence (not order) - allows minor pronunciation errors, ignores extra/incorrect words.
@available(iOS 13.0, macOS 10.15, *)
class DelayedRecallTask: Task {
    let id: UUID
    let title: String = "Delayed Recall Task"
    let instructions: TaskInstructions = .text("Recall the 5 words from the first activity. You won't hear them again - just try to remember them. You have 15 seconds to respond.")
    let expectedInputType: TaskInputType = .audio
    let timingRequirements: TimingRequirements? = TimingRequirements(maxDuration: 15.0)
    let scoringMetadata: [String: Any]? = nil
    
    private let audioManager: AudioManagerProtocol
    private let taskRunner: TaskRunnerProtocol
    private let dataController: DataControllerProtocol
    
    // Constants
    private let expectedWords = ["chair", "book", "hand", "road", "cloud"]
    private let recordingDuration: TimeInterval = 15.0
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
                print("⚠️ DelayedRecallTask: WARNING - DataController differs from TaskRunner's!")
            } else {
                print("✅ DelayedRecallTask: Using same DataController as TaskRunner")
            }
        }
        print("🎯 DelayedRecallTask: Initialized with ID: \(id)")
        print("   - DataController instance: \(ObjectIdentifier(dataController as AnyObject))")
    }
    
    func start() async throws {
        print("🎯 DelayedRecallTask: Starting task (id: \(id))")
        isCancelled = false

        // Clear any previous word display and transcript
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                taskRunnerInstance.currentWord = nil
                taskRunnerInstance.transcript = []
            }
        }

        // Intro explanation
        let introText = "Hi! I'm going to ask you to recall the 5 words from the first activity. You won't hear them again - just try to remember them. You'll have 15 seconds to say as many as you can remember."
        
        // Add to transcript
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                taskRunnerInstance.transcript.append(
                    TranscriptItem(text: introText, type: .instruction, isHighlighted: true)
                )
            }
        }
        
        print("🔊 DelayedRecallTask: Speaking intro explanation")
        try? await audioManager.speak(introText)
        print("✅ DelayedRecallTask: Intro explanation completed")
        
        // Unhighlight intro after speaking
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                if let lastIndex = taskRunnerInstance.transcript.indices.last {
                    taskRunnerInstance.transcript[lastIndex].isHighlighted = false
                }
            }
        }
        
        if isCancelled {
            print("🛑 DelayedRecallTask: Task cancelled after intro")
            await taskRunner.transition(to: .completed)
            return
        }
        
        // Ensure we're in presenting state
        print("🔄 DelayedRecallTask: Ensuring .presenting state")
        await taskRunner.transition(to: .presenting)
        
        // Prompt to recall words
        let promptText = "Now, please tell me the words you remember from the first activity. You have 15 seconds."
        
        // Add to transcript
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await MainActor.run {
                taskRunnerInstance.transcript.append(
                    TranscriptItem(text: promptText, type: .prompt, isHighlighted: true)
                )
            }
        }
        
        print("🔊 DelayedRecallTask: Prompting user to recall words")
        try? await audioManager.speak(promptText)
        print("✅ DelayedRecallTask: Prompt completed")
        
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
        
        if isCancelled {
            print("🛑 DelayedRecallTask: Task cancelled after prompt")
            await taskRunner.transition(to: .completed)
            return
        }
        
        // Play beep to indicate when to start speaking
        print("🔔 DelayedRecallTask: Playing beep before recording starts")
        try? await audioManager.playBeep(soundID: 1057) // Start beep
        print("✅ DelayedRecallTask: Beep played")
        
        // Transition to recording state (TaskRunner will create ItemResponse and AudioClip)
        print("🎙️ DelayedRecallTask: Transitioning to .recording state")
        await taskRunner.transition(to: .recording)
        print("✅ DelayedRecallTask: Recording state transitioned, waiting for ItemResponse creation...")
        
        // Small delay to ensure ItemResponse is created by TaskRunner
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Wait exactly 15 seconds, checking for cancellation every 0.5 seconds
        print("⏱️ DelayedRecallTask: Starting \(recordingDuration)s recording period")
        let checkInterval: TimeInterval = 0.5
        let totalChecks = Int(recordingDuration / checkInterval)
        for i in 0..<totalChecks {
            if isCancelled {
                print("🛑 DelayedRecallTask: Task cancelled during recording (check \(i + 1)/\(totalChecks))")
                break
            }
            try? await _Concurrency.Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
        }
        
        if isCancelled {
            print("🛑 DelayedRecallTask: Task cancelled during recording")
            // Still process whatever was recorded before cancellation
            print("📊 DelayedRecallTask: Processing partial data from cancelled task")
        } else {
            print("✅ DelayedRecallTask: Recording period completed")
        }
        
        // Transition to evaluating state (TaskRunner will stop recording and start transcription)
        print("🔄 DelayedRecallTask: Transitioning to .evaluating state (stopping recording, starting transcription)")
        await taskRunner.transition(to: .evaluating)
        
        // Small delay to ensure recording has stopped
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Fetch current ItemResponse (even if cancelled, process what we have)
        print("🔍 DelayedRecallTask: Fetching ItemResponse")
        if let currentResponse = try? await getCurrentResponse(),
           let audioClipId = currentResponse.audioClipId {
            print("✅ DelayedRecallTask: Found ItemResponse (id: \(currentResponse.id), audioClipId: \(audioClipId))")
            
            // Wait for transcription (with timeout protection and cancellation checks)
            print("📝 DelayedRecallTask: Waiting for transcription (max \(transcriptionMaxWaitTime)s)...")
            let transcription = try? await waitForTranscription(audioClipId: audioClipId, maxWaitSeconds: transcriptionMaxWaitTime)
            
            if let transcription = transcription {
                print("✅ DelayedRecallTask: Transcription received: \"\(transcription)\"")
            } else {
                print("⚠️ DelayedRecallTask: Transcription failed or timed out")
                print("   Continuing with empty transcription for scoring...")
            }
            
            // Score response (always proceed, even with empty transcription or if cancelled)
            print("📊 DelayedRecallTask: Scoring response...")
            let (score, correctWords) = scoreResponse(transcription ?? "", expectedWords: expectedWords)
            print("📊 DelayedRecallTask: Score: \(String(format: "%.2f", score)) (\(correctWords.count)/\(expectedWords.count))")
            print("   - Correct words: \(correctWords.isEmpty ? "None" : correctWords.joined(separator: ", "))")
            print("   - Expected words: \(expectedWords.joined(separator: ", "))")
            
            // Update ItemResponse with scoring data
            var updatedResponse = currentResponse
            updatedResponse.score = score
            updatedResponse.correctWords = correctWords
            updatedResponse.expectedWords = expectedWords
            updatedResponse.responseText = transcription
            updatedResponse.updatedAt = Date()
            
            print("💾 DelayedRecallTask: Updating ItemResponse with scoring data...")
            print("   - Response ID: \(updatedResponse.id)")
            print("   - Score: \(updatedResponse.score?.description ?? "nil")")
            print("   - Correct words count: \(updatedResponse.correctWords?.count ?? 0)")
            print("   - Expected words: \(updatedResponse.expectedWords?.joined(separator: ", ") ?? "nil")")
            do {
                try await dataController.updateItemResponse(updatedResponse)
                print("✅ DelayedRecallTask: ItemResponse updated successfully")
                
                // Verify it was saved
                if let saved = try? await dataController.fetchItemResponse(id: updatedResponse.id) {
                    print("   ✅ Verification: ItemResponse saved correctly")
                    print("      - Saved score: \(saved.score?.description ?? "nil")")
                    print("      - Saved correctWords: \(saved.correctWords?.count ?? 0)")
                } else {
                    print("   ⚠️ Verification: Could not fetch saved ItemResponse")
                }
            } catch {
                print("⚠️ DelayedRecallTask: Failed to update ItemResponse: \(error)")
            }
            
            print("✅ DelayedRecallTask: Task processed\n")
        } else {
            print("⚠️ DelayedRecallTask: Failed to fetch ItemResponse or audioClipId")
            print("   - CurrentResponse: \(String(describing: try? await getCurrentResponse()))")
            // If cancelled and no response exists, create a zero-scored response
            if isCancelled {
                print("📊 DelayedRecallTask: Task cancelled with no response - creating zero-scored response")
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
        
        if !isCancelled {
            // Completion message
            print("🎉 DelayedRecallTask: Task completed, speaking completion message")
            let completionText = "Great job! You've completed the delayed recall task."
            try? await audioManager.speak(completionText)
            print("✅ DelayedRecallTask: Task fully completed")
            
            // Transition to completed state
            print("🔄 DelayedRecallTask: Transitioning to .completed state")
            await taskRunner.transition(to: .completed)
            print("✅ DelayedRecallTask: State transitioned to .completed")
        } else {
            print("🛑 DelayedRecallTask: Task was cancelled, skipping completion message")
            // Still transition to completed even if cancelled
            await taskRunner.transition(to: .completed)
        }
    }
    
    func stop() async throws {
        print("🛑 DelayedRecallTask: stop() called, cancelling task")
        isCancelled = true
        // TTS will stop automatically when cancelled or when new speech starts
    }
    
    func captureResponse(_ response: String) async throws {
        // Not used directly - handled via DataController updates in start()
    }
    
    // MARK: - Helper Methods
    
    /// Fetches the most recent ItemResponse for this task
    /// CRITICAL: Must sort by createdAt to ensure we get the most recently created response
    private func getCurrentResponse() async throws -> ItemResponse? {
        print("🔍 DelayedRecallTask.getCurrentResponse: Fetching all ItemResponses...")
        let allResponses = try await dataController.fetchAllItemResponses()
        print("   - Total responses found: \(allResponses.count)")
        let taskResponses = allResponses.filter { $0.taskId == self.id }
        print("   - Responses for this task (id: \(self.id)): \(taskResponses.count)")
        
        // CRITICAL: Sort by createdAt DESCENDING (most recent first)
        // This ensures we get the response that was just created
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
        
        print("   🔄 DelayedRecallTask.waitForTranscription: Starting polling (audioClipId: \(audioClipId), maxWait: \(maxWaitSeconds)s, maxPolls: \(maxPolls))")
        
        while pollCount < maxPolls {
            if isCancelled {
                print("   🛑 DelayedRecallTask.waitForTranscription: Task cancelled during polling")
                return nil
            }
            
            pollCount += 1
            let elapsed = Date().timeIntervalSince(startTime)
            
            // Safety check - ensure we don't exceed maxWaitSeconds
            if elapsed >= maxWaitSeconds {
                print("   ⏰ DelayedRecallTask.waitForTranscription: Max wait time reached (\(String(format: "%.1f", elapsed))s)")
                break
            }
            
            if let audioClip = try? await dataController.fetchAudioClip(id: audioClipId) {
                if let transcription = audioClip.transcription, !transcription.isEmpty {
                    print("   ✅ DelayedRecallTask.waitForTranscription: Transcription found after \(String(format: "%.1f", elapsed))s (\(pollCount) polls)")
                    return transcription
                } else {
                    if pollCount % 10 == 0 || pollCount == 1 { // Log first poll and every 10th poll
                        print("   ⏳ DelayedRecallTask.waitForTranscription: Poll \(pollCount), elapsed \(String(format: "%.1f", elapsed))s, transcription still nil")
                    }
                }
            } else {
                if pollCount % 10 == 0 || pollCount == 1 {
                    print("   ⚠️ DelayedRecallTask.waitForTranscription: Poll \(pollCount), AudioClip not found")
                }
            }
            
            // Wait before next poll
            try? await _Concurrency.Task.sleep(nanoseconds: UInt64(transcriptionPollInterval * 1_000_000_000))
        }
        
        // Timeout
        let elapsed = Date().timeIntervalSince(startTime)
        print("   ⚠️ DelayedRecallTask.waitForTranscription: Timeout after \(String(format: "%.1f", elapsed))s (\(pollCount) polls) - proceeding without transcription")
        return nil
    }
    
    /// Scores the transcription against expected words
    /// Returns: (score as fraction, array of correct words)
    /// KEY DIFFERENCE: Checks for word presence (not order) - allows minor pronunciation errors, ignores extra/incorrect words
    private func scoreResponse(_ transcription: String, expectedWords: [String]) -> (score: Double, correctWords: [String]) {
        print("   📝 DelayedRecallTask.scoreResponse: Scoring transcription")
        print("      - Raw transcription: \"\(transcription)\"")
        
        // Normalize transcription: lowercase, remove punctuation
        let normalized = transcription.lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("      - Normalized: \"\(normalized)\"")
        
        // Split into words
        let spokenWords = normalized.split(separator: " ").map { String($0) }
        print("      - Words extracted: \(spokenWords.count) words - [\(spokenWords.joined(separator: ", "))]")
        
        var correctWords: [String] = []
        
        // Check for each expected word in the spoken words (order doesn't matter)
        for expectedWord in expectedWords {
            let expectedWordLower = expectedWord.lowercased()
            var found = false
            
            // Check for exact match first
            for spokenWord in spokenWords {
                if spokenWord.lowercased() == expectedWordLower {
                    correctWords.append(expectedWord)
                    found = true
                    print("      - ✅ Found word '\(expectedWord)' (exact match)")
                    break
                }
            }
            
            // If not found, check for minor pronunciation variations (fuzzy matching)
            // This allows for minor pronunciation errors
            if !found {
                for spokenWord in spokenWords {
                    // Check if spoken word contains expected word or vice versa (for plurals, etc.)
                    let spokenLower = spokenWord.lowercased()
                    if spokenLower.contains(expectedWordLower) || expectedWordLower.contains(spokenLower) {
                        // Additional check: ensure it's not too different (length check)
                        let lengthDiff = abs(spokenLower.count - expectedWordLower.count)
                        if lengthDiff <= 2 { // Allow up to 2 character difference
                            correctWords.append(expectedWord)
                            found = true
                            print("      - ✅ Found word '\(expectedWord)' (fuzzy match with '\(spokenWord)')")
                            break
                        }
                    }
                }
            }
            
            if !found {
                print("      - ❌ Word '\(expectedWord)' not found in response")
            }
        }
        
        // Calculate score as fraction (0-1, where 1 = all 5 words recalled)
        let score = Double(correctWords.count) / Double(expectedWords.count)
        print("      - Final score: \(correctWords.count)/\(expectedWords.count) = \(String(format: "%.2f", score))")
        
        return (score, correctWords)
    }
}

