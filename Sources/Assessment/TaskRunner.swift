import Foundation
import Combine

/// State-machine-based task runner implementation.
/// Manages task progression, response capture, timestamping, and result storage.
class TaskRunner: TaskRunnerProtocol, ObservableObject {
    @Published private(set) var state: TaskRunnerState = .idle
    @Published private(set) var currentTask: (any Task)?
    
    private let dataController: DataControllerProtocol
    private let audioManager: AudioManagerProtocol
    private let transcriptionManager: TranscriptionManagerProtocol
    private let fileStorage: FileStorageProtocol
    
    private var currentSessionId: UUID?
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
        guard state == .idle else {
            throw TaskRunnerError.invalidState
        }
        
        currentSessionId = sessionId
        currentTask = task
        
        await transition(to: .presenting)
        
        do {
            try await task.start()
        } catch {
            await transition(to: .idle)
            throw error
        }
    }
    
    func stopTask() async throws {
        guard state != .idle && state != .completed else {
            throw TaskRunnerError.invalidState
        }
        
        // Stop any active recording
        if audioManager.isRecording {
            let duration = try await audioManager.stopRecording()
            
            // Update audio clip duration if we have one
            if let audioClipId = currentAudioClipId,
               var audioClip = try? await dataController.fetchAudioClip(id: audioClipId) {
                audioClip.duration = duration
                try await dataController.updateAudioClip(audioClip)
            }
        }
        
        // Stop current task
        if let task = currentTask {
            try await task.stop()
        }
        
        await transition(to: .completed)
        
        // Clean up
        currentTask = nil
        currentResponse = nil
        currentAudioClipId = nil
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
            return
        }
        
        // Start audio recording if task expects audio input
        if task.expectedInputType == .audio {
            do {
                let audioPath = "recordings/\(UUID().uuidString).m4a"
                try await audioManager.startRecording(to: audioPath)
                
                // Create audio clip record
                let audioClip = AudioClip(filePath: audioPath)
                let savedClip = try await dataController.createAudioClip(audioClip)
                currentAudioClipId = savedClip.id
                
                // Create response with audio reference
                let response = ItemResponse(
                    sessionId: sessionId,
                    taskId: task.id,
                    audioClipId: savedClip.id
                )
                let savedResponse = try await dataController.createItemResponse(response)
                currentResponse = savedResponse
            } catch {
                // Handle error - could transition to error state
                print("Failed to start recording: \(error)")
            }
        }
    }
    
    private func handleEvaluatingState() async {
        // Stop recording if active
        if audioManager.isRecording {
            do {
                let duration = try await audioManager.stopRecording()
                
                // Update audio clip duration
                if let audioClipId = currentAudioClipId,
                   var audioClip = try? await dataController.fetchAudioClip(id: audioClipId) {
                    audioClip.duration = duration
                    try await dataController.updateAudioClip(audioClip)
                    
                    // Transcribe audio if available
                    try? await transcriptionManager.startTranscription(from: audioClip.filePath) { [weak self] result in
                        Task { @MainActor in
                            switch result {
                            case .success(let text):
                                if var updatedClip = try? await self?.dataController.fetchAudioClip(id: audioClipId) {
                                    updatedClip.transcription = text
                                    updatedClip.updatedAt = Date()
                                    try? await self?.dataController.updateAudioClip(updatedClip)
                                }
                            case .failure:
                                break
                            }
                        }
                    }
                }
            } catch {
                print("Failed to stop recording: \(error)")
            }
        }
    }
    
    private func handleCompletedState() async {
        // Finalize response if needed
        if var response = currentResponse {
            response.updatedAt = Date()
            try? await dataController.updateItemResponse(response)
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

