import Foundation
import Combine

/// State-machine-based task runner implementation.
/// Manages task progression, response capture, timestamping, and result storage.
@available(iOS 13.0, macOS 10.15, *)
class TaskRunner: TaskRunnerProtocol, ObservableObject {
    @Published private(set) var state: TaskRunnerState = .idle
    @Published private(set) var currentTask: (any Task)?
    @Published var currentWord: String? = nil // Current word being displayed (for WorkingMemoryTask)
    @Published var transcript: [TranscriptItem] = [] // Transcript of what's being said (for WorkingMemoryTask)
    
    let dataController: DataControllerProtocol
    private let audioManager: AudioManagerProtocol
    private let transcriptionManager: TranscriptionManagerProtocol
    private let fileStorage: FileStorageProtocol
    
    var currentSessionId: UUID? { _currentSessionId }
    private var _currentSessionId: UUID?
    private var currentResponse: ItemResponse?
    private var currentAudioClipId: UUID?
    
    init(
        dataController: DataControllerProtocol,
        audioManager: AudioManagerProtocol,
        transcriptionManager: TranscriptionManagerProtocol,
        fileStorage: FileStorageProtocol
    ) {
        self.dataController = dataController
        self.audioManager = audioManager
        self.transcriptionManager = transcriptionManager
        self.fileStorage = fileStorage
    }
    
    func startTask(_ task: any Task, sessionId: UUID) async throws {
        // Reset all state first to ensure complete isolation from previous tasks
        await reset()
        
        guard state == .idle else {
            throw TaskRunnerError.invalidState
        }
        
        _currentSessionId = sessionId
        currentTask = task
        
        await transition(to: .presenting)
        
        do {
            try await task.start()
            // Task completed successfully - transition to completed state if not already there
            if state != .completed {
                print("✅ TaskRunner: Task.start() completed, transitioning to .completed state")
                await transition(to: .completed)
            }
        } catch {
            print("❌ TaskRunner: Task.start() threw error: \(error)")
            await transition(to: .idle)
            throw error
        }
    }
    
    func stopTask() async throws {
        guard state != .idle && state != .completed else {
            throw TaskRunnerError.invalidState
        }
        
        print("🛑 TaskRunner: stopTask() called - stopping task immediately")
        
        // Stop current task FIRST to set cancellation flag
        if let task = currentTask {
            print("🛑 TaskRunner: Calling task.stop() to set cancellation flag")
            try await task.stop()
        }
        
        // Stop any active recording
        if audioManager.isRecording {
            print("🛑 TaskRunner: Stopping active recording")
            let duration = try await audioManager.stopRecording()
            
            // Update audio clip duration if we have one
            if let audioClipId = currentAudioClipId,
               var audioClip = try? await dataController.fetchAudioClip(id: audioClipId) {
                audioClip.duration = duration
                try await dataController.updateAudioClip(audioClip)
                print("✅ TaskRunner: Updated audio clip duration: \(duration)s")
            }
        }
        
        // Transition to completed state immediately
        print("🛑 TaskRunner: Transitioning to .completed state")
        await transition(to: .completed)
        
        // Clean up
        currentTask = nil
        currentResponse = nil
        currentAudioClipId = nil
        print("✅ TaskRunner: Task stopped and cleaned up")
    }
    
    /// Load a completed task for viewing results (without starting it)
    func loadCompletedTask(_ task: any Task, sessionId: UUID) async {
        await MainActor.run {
            self._currentSessionId = sessionId
            self.currentTask = task
            self.state = .completed
        }
        print("✅ TaskRunner: Loaded completed task \(task.id) for viewing results")
    }
    
    func captureResponse(_ response: String) async throws {
        guard let sessionId = currentSessionId,
              let task = currentTask else {
            throw TaskRunnerError.noActiveTask
        }
        
        // Create or update response
        if var existingResponse = currentResponse {
            existingResponse.responseText = response
            existingResponse.updatedAt = Date()
            try await dataController.updateItemResponse(existingResponse)
            currentResponse = existingResponse
        } else {
            let newResponse = ItemResponse(
                sessionId: sessionId,
                taskId: task.id,
                responseText: response
            )
            let savedResponse = try await dataController.createItemResponse(newResponse)
            currentResponse = savedResponse
        }
        
        // Capture in task
        try await task.captureResponse(response)
    }
    
    func transition(to newState: TaskRunnerState) async {
        await MainActor.run {
            state = newState
        }
        
        // Handle state-specific logic
        switch newState {
        case .recording:
            await handleRecordingState()
        case .evaluating:
            await handleEvaluatingState()
        case .completed:
            await handleCompletedState()
        default:
            break
        }
    }
    
    private func handleRecordingState() async {
        guard let task = currentTask,
              let sessionId = currentSessionId else {
            print("⚠️ TaskRunner.handleRecordingState: Missing task or sessionId")
            return
        }
        
        // Start audio recording if task expects audio input
        if task.expectedInputType == .audio {
            var audioClipId: UUID? = nil
            var audioPath: String? = nil
            
            do {
                print("🎙️ TaskRunner.handleRecordingState: Starting recording for task \(task.id)")
                print("   - DataController instance: \(ObjectIdentifier(dataController as AnyObject))")
                
                audioPath = "recordings/\(UUID().uuidString).m4a"
                try await audioManager.startRecording(to: audioPath!)
                print("✅ TaskRunner.handleRecordingState: Recording started")
                
                // Create audio clip record
                let audioClip = AudioClip(filePath: audioPath!)
                let savedClip = try await dataController.createAudioClip(audioClip)
                audioClipId = savedClip.id
                currentAudioClipId = savedClip.id
                print("✅ TaskRunner.handleRecordingState: AudioClip created (id: \(savedClip.id))")
            } catch {
                // Recording failed, but we still need to create ItemResponse
                print("⚠️ TaskRunner.handleRecordingState: Recording failed: \(error)")
                print("   Will create ItemResponse without audioClipId to allow task to continue")
                
                // Try to create a placeholder AudioClip even if recording failed
                // This allows the task to still reference an AudioClip for transcription attempts
                if let path = audioPath {
                    let audioClip = AudioClip(filePath: path)
                    if let savedClip = try? await dataController.createAudioClip(audioClip) {
                        audioClipId = savedClip.id
                        currentAudioClipId = savedClip.id
                        print("✅ TaskRunner.handleRecordingState: Created placeholder AudioClip (id: \(savedClip.id))")
                    } else {
                        print("⚠️ TaskRunner.handleRecordingState: Failed to create placeholder AudioClip")
                    }
                }
            }
            
            // CRITICAL: Always create ItemResponse, even if recording failed
            // This allows WorkingMemoryTask to update it with scoring data
            do {
                let response = ItemResponse(
                    sessionId: sessionId,
                    taskId: task.id,
                    audioClipId: audioClipId
                )
                print("📝 TaskRunner.handleRecordingState: Creating ItemResponse...")
                print("   - SessionId: \(sessionId)")
                print("   - TaskId: \(task.id)")
                print("   - AudioClipId: \(audioClipId?.uuidString ?? "nil")")
                
                let savedResponse = try await dataController.createItemResponse(response)
                currentResponse = savedResponse
                print("✅ TaskRunner.handleRecordingState: ItemResponse created successfully (id: \(savedResponse.id))")
                
                // Verify it was saved
                if (try? await dataController.fetchItemResponse(id: savedResponse.id)) != nil {
                    print("   ✅ Verification: ItemResponse exists in DataController")
                } else {
                    print("   ⚠️ Verification: ItemResponse NOT found in DataController!")
                }
            } catch {
                print("❌ TaskRunner.handleRecordingState: CRITICAL - Failed to create ItemResponse: \(error)")
                print("   This will prevent the task from saving results!")
            }
        }
    }
    
    private func handleEvaluatingState() async {
        print("🔄 TaskRunner.handleEvaluatingState: Entering evaluating state")
        
        // Stop recording if active
        if audioManager.isRecording {
            print("🛑 TaskRunner.handleEvaluatingState: Stopping recording...")
            do {
                let duration = try await audioManager.stopRecording()
                print("✅ TaskRunner.handleEvaluatingState: Recording stopped (duration: \(String(format: "%.2f", duration))s)")
                
                // Update audio clip duration
                if let audioClipId = currentAudioClipId {
                    print("📝 TaskRunner.handleEvaluatingState: Updating AudioClip duration (id: \(audioClipId))")
                    if var audioClip = try? await dataController.fetchAudioClip(id: audioClipId) {
                        audioClip.duration = duration
                        try await dataController.updateAudioClip(audioClip)
                        print("✅ TaskRunner.handleEvaluatingState: AudioClip duration updated")
                        
                        // Transcribe audio if available
                        print("🎤 TaskRunner.handleEvaluatingState: Starting transcription for file: \(audioClip.filePath)")
                        do {
                            try await transcriptionManager.startTranscription(from: audioClip.filePath) { [weak self] result in
                                print("📞 TaskRunner.handleEvaluatingState: Transcription callback received")
                                // Use _Concurrency.Task to explicitly reference Swift's concurrency Task type
                                // This avoids conflict with the local Task protocol
                                _Concurrency.Task.detached { @MainActor in
                                    switch result {
                                    case .success(let text):
                                        print("✅ TaskRunner.handleEvaluatingState: Transcription success: \"\(text)\"")
                                        if var updatedClip = try? await self?.dataController.fetchAudioClip(id: audioClipId) {
                                            updatedClip.transcription = text
                                            updatedClip.updatedAt = Date()
                                            try? await self?.dataController.updateAudioClip(updatedClip)
                                            print("✅ TaskRunner.handleEvaluatingState: AudioClip transcription saved")
                                        } else {
                                            print("⚠️ TaskRunner.handleEvaluatingState: Failed to fetch AudioClip for update")
                                        }
                                    case .failure(let error):
                                        print("❌ TaskRunner.handleEvaluatingState: Transcription failed: \(error.localizedDescription)")
                                        print("   Error details: \(error)")
                                    }
                                }
                            }
                            print("✅ TaskRunner.handleEvaluatingState: Transcription started successfully")
                        } catch {
                            print("❌ TaskRunner.handleEvaluatingState: Failed to start transcription: \(error)")
                        }
                    } else {
                        print("⚠️ TaskRunner.handleEvaluatingState: Could not fetch AudioClip (id: \(audioClipId))")
                    }
                } else {
                    print("⚠️ TaskRunner.handleEvaluatingState: No audioClipId available")
                }
            } catch {
                print("❌ TaskRunner.handleEvaluatingState: Failed to stop recording: \(error)")
            }
        } else {
            print("ℹ️ TaskRunner.handleEvaluatingState: No active recording to stop")
        }
        print("✅ TaskRunner.handleEvaluatingState: Evaluation state handling completed")
    }
    
    private func handleCompletedState() async {
        // Finalize response if needed
        // CRITICAL: Fetch the latest response from DataController instead of using currentResponse
        // This ensures we don't overwrite updates made by the task (like scores)
        if let responseId = currentResponse?.id {
            if var latestResponse = try? await dataController.fetchItemResponse(id: responseId) {
                // Only update updatedAt, preserving all other fields (score, correctWords, etc.)
                latestResponse.updatedAt = Date()
                try? await dataController.updateItemResponse(latestResponse)
                print("✅ TaskRunner.handleCompletedState: Finalized ItemResponse (id: \(responseId))")
            } else {
                print("⚠️ TaskRunner.handleCompletedState: Could not fetch latest ItemResponse (id: \(responseId))")
            }
        } else {
            print("ℹ️ TaskRunner.handleCompletedState: No current response to finalize")
        }
    }
    
    func reset() async {
        await MainActor.run {
            print("🔄 TaskRunner: Resetting all state for task isolation")
            
            // Reset state to idle
            self.state = .idle
            
            // Clear current task
            self.currentTask = nil
            
            // Clear session ID
            self._currentSessionId = nil
            
            // Clear current response
            self.currentResponse = nil
            
            // Clear audio clip ID
            self.currentAudioClipId = nil
            
            // Clear UI state
            self.currentWord = nil
            self.transcript = []
            
            print("✅ TaskRunner: State reset complete - ready for new task")
        }
    }
}

enum TaskRunnerError: LocalizedError {
    case invalidState
    case noActiveTask
    
    var errorDescription: String? {
        switch self {
        case .invalidState:
            return "Task runner is in an invalid state for this operation"
        case .noActiveTask:
            return "No active task to capture response for"
        }
    }
}


