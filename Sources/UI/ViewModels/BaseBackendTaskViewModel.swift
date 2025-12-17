import Foundation
import SwiftUI
import AVFoundation
import AudioToolbox

/// Base ViewModel for backend-controlled tasks
/// Provides common WebSocket and audio management while allowing task-specific customization
@MainActor
class BaseBackendTaskViewModel: ObservableObject {
    // Shared state properties
    @Published var currentState: TaskState = .listening
    @Published var trialNumber: Int = 0
    @Published var statusMessage: String = ""
    @Published var isConnected: Bool = false
    @Published var timeRemaining: Double = 10.0  // Countdown timer for recording
    @Published var isRecording: Bool = false  // Track if currently recording
    
    // Task-specific properties (must be provided by subclasses)
    // Subclasses should provide: @Published var showResults: Bool = false
    
    // Internal state (accessible to subclasses)
    var webSocketClient: WebSocketClient?
    var audioPlayer: AVAudioPlayer?
    var audioRecorder: SimpleAudioRecorder?
    var sessionId: String?
    var currentTrialNumber: Int = 0  // Track which trial we're on (0 = instruction)
    var recordingTimer: Timer?
    
    // Task-specific configuration (must be provided by subclasses)
    var webSocketURL: String {
        fatalError("Subclasses must provide webSocketURL")
    }
    
    var uploadURL: String {
        fatalError("Subclasses must provide uploadURL")
    }
    
    let recordingDuration: TimeInterval = 10.0  // Default, can be overridden
    
    // MARK: - Shared Methods
    
    func startTask() async {
        print("🚀 BaseBackendTaskViewModel: startTask() called")
        
        // Initialize audio recorder
        audioRecorder = SimpleAudioRecorder()
        
        // Initialize WebSocket client
        guard let url = URL(string: webSocketURL) else {
            print("❌ BaseBackendTaskViewModel: Invalid server URL: \(webSocketURL)")
            statusMessage = "Invalid server URL"
            return
        }
        
        print("🌐 BaseBackendTaskViewModel: Creating WebSocket client for: \(url)")
        let client = WebSocketClient(url: url)
        client.delegate = self
        webSocketClient = client
        
        // Connect WebSocket
        do {
            print("🌐 BaseBackendTaskViewModel: Connecting WebSocket...")
            try await client.connect()
            isConnected = true
            print("✅ BaseBackendTaskViewModel: WebSocket connected")
            
            // Send start event immediately - WebSocket is ready after connect() returns
            print("📤 BaseBackendTaskViewModel: Sending start_task event")
            client.sendEvent("start_task")
            
        } catch {
            print("❌ BaseBackendTaskViewModel: Connection failed: \(error)")
            statusMessage = "Connection failed: \(error.localizedDescription)"
            isConnected = false
        }
    }
    
    func stopTask() async {
        recordingTimer?.invalidate()
        recordingTimer = nil
        webSocketClient?.sendEvent("end_session")
        webSocketClient?.disconnect()
        audioPlayer?.stop()
        audioRecorder?.stop()
        isConnected = false
    }
    
    func playAudio(_ audioData: Data) async throws {
        // Stop any currently playing audio
        audioPlayer?.stop()
        
        // Create temporary file for audio
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp3")
        
        try audioData.write(to: tempURL)
        
        // Create audio player
        audioPlayer = try AVAudioPlayer(contentsOf: tempURL)
        audioPlayer?.prepareToPlay()
        
        // Configure audio session for playback
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .default)
        try audioSession.setActive(true)
        
        // Play audio
        guard let player = audioPlayer else {
            throw NSError(domain: "BaseBackendTaskViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio player"])
        }
        
        player.play()
        
        // Wait for playback to complete
        while player.isPlaying {
            try await _Concurrency.Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    func signalAudioComplete() async {
        // Send audio_complete event to backend via WebSocket
        guard let webSocketClient = webSocketClient else {
            print("⚠️ BaseBackendTaskViewModel: No WebSocket client, cannot signal audio_complete")
            return
        }
        
        webSocketClient.sendEvent("audio_complete")
        print("✅ BaseBackendTaskViewModel: Sent audio_complete signal")
    }
    
    func signalInstructionComplete() async {
        guard let sessionId = sessionId else {
            print("❌ BaseBackendTaskViewModel: No session ID available")
            statusMessage = "No session ID"
            return
        }
        
        // Upload empty data to signal instruction is complete
        // Backend will ignore the audio but use this as signal to proceed
        do {
            let emptyData = Data()
            try await uploadAudio(emptyData, trialNumber: 0, sessionId: sessionId)
            print("✅ BaseBackendTaskViewModel: Instruction complete signal sent")
            statusMessage = "Ready for first trial..."
        } catch {
            print("❌ BaseBackendTaskViewModel: Error signaling instruction complete: \(error)")
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }
    
    func recordAndUpload(trialNumber: Int) async {
        guard let sessionId = sessionId else {
            print("❌ BaseBackendTaskViewModel: No session ID available")
            statusMessage = "No session ID"
            return
        }
        
        print("🎙️ BaseBackendTaskViewModel: Starting recording for trial \(trialNumber)")
        
        // Reset and start countdown timer
        timeRemaining = recordingDuration
        isRecording = true
        statusMessage = ""  // Don't show status during recording - just the countdown
        
        // Start timer to update countdown (runs on main thread via RunLoop)
        recordingTimer?.invalidate()
        recordingTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // Update on main thread for @Published properties
            DispatchQueue.main.async {
                if self.timeRemaining > 0 {
                    self.timeRemaining -= 0.1
                } else {
                    self.isRecording = false
                }
            }
        }
        // Add timer to main run loop to ensure it runs on main thread
        RunLoop.main.add(recordingTimer!, forMode: .common)
        
        do {
            // Record for specified duration
            print("🎙️ BaseBackendTaskViewModel: Calling audioRecorder.recordForDuration(\(recordingDuration))")
            let audioData = try await audioRecorder?.recordForDuration(recordingDuration) ?? Data()
            print("🎙️ BaseBackendTaskViewModel: Recording finished, audio data size: \(audioData.count) bytes")
            
            // Stop timer
            recordingTimer?.invalidate()
            recordingTimer = nil
            timeRemaining = 0
            isRecording = false
            
            // Note: End beep will be played when backend sends beep_end state transition
            
            // Upload in background (fire-and-forget) - don't block UI
            statusMessage = ""  // No status - just wait for next audio
            
            // Capture sessionId for background upload (already unwrapped by guard above)
            let uploadSessionId = sessionId
            
            // Upload via HTTP in background task
            _Concurrency.Task.detached(priority: .utility) {
                do {
                    print("📤 BaseBackendTaskViewModel: Uploading audio for trial \(trialNumber) (size: \(audioData.count) bytes)")
                    try await self.uploadAudio(audioData, trialNumber: trialNumber, sessionId: uploadSessionId)
                    print("✅ BaseBackendTaskViewModel: Audio uploaded for trial \(trialNumber) (background)")
                } catch {
                    print("❌ BaseBackendTaskViewModel: Error uploading audio (background): \(error)")
                }
            }
            
            // Immediately ready - backend will send next trial audio when ready
            // No waiting for upload or processing
            
        } catch {
            // Stop timer on error
            recordingTimer?.invalidate()
            recordingTimer = nil
            timeRemaining = 0
            isRecording = false
            
            print("❌ BaseBackendTaskViewModel: Error recording/uploading: \(error)")
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Task-Specific Methods (must be overridden)
    
    /// Handle TTS audio received - task-specific flow after audio plays
    func handleTTSReceived(audio: Data, trialNumber: Int?) {
        fatalError("Subclasses must implement handleTTSReceived")
    }
    
    /// Handle individual evaluation result - task-specific result handling
    func handleEvaluationResult(_ result: EvaluationResult) {
        fatalError("Subclasses must implement handleEvaluationResult")
    }
    
    /// Handle all results received - task-specific completion handling
    func handleAllResults(_ results: [EvaluationResult]) {
        fatalError("Subclasses must implement handleAllResults")
    }
    
    /// Hook method called when task state changes - can be overridden by subclasses
    func handleTaskStateChanged(state: TaskState, trialNumber: Int?, message: String?) {
        // Default implementation does nothing - subclasses can override
    }
    
    /// Handle word display message - can be overridden by subclasses
    func handleWordDisplayReceived(word: String, trialNumber: Int, wordIndex: Int) {
        // Default implementation does nothing - subclasses can override
    }
    
    /// Handle state transition - can be overridden by subclasses
    func handleStateTransitionReceived(phase: String, trialNumber: Int?, message: String?) {
        // Default implementation does nothing - subclasses can override
    }
    
    // MARK: - Helper Methods
    
    func _playStartBeep() async {
        // Play a system beep sound to indicate recording is about to start
        AudioServicesPlaySystemSound(1057) // System beep sound
        // Small delay to ensure beep plays
        try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000) // 0.3s to match beep duration
    }
    
    func _playEndBeep() async {
        // Play a system beep sound to indicate recording has ended
        AudioServicesPlaySystemSound(1057) // System beep sound (same as start beep)
        // Small delay to ensure beep plays
        try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000) // 0.3s to match beep duration
    }
    
    private func uploadAudio(_ audioData: Data, trialNumber: Int, sessionId: String) async throws {
        let url = URL(string: uploadURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Create multipart/form-data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add trial_number
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"trial_number\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(trialNumber)".data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add session_id
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"session_id\"\r\n\r\n".data(using: .utf8)!)
        body.append(sessionId.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "BaseBackendTaskViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "BaseBackendTaskViewModel", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Upload failed with status \(httpResponse.statusCode)"])
        }
    }
}

// MARK: - WebSocketClientDelegate Implementation

extension BaseBackendTaskViewModel: WebSocketClientDelegate {
    func didReceiveTTS(audio: Data, trialNumber: Int?) {
        print("🔊 BaseBackendTaskViewModel: Received TTS audio (trial: \(trialNumber ?? -1))")
        
        // Update trial number
        if let trialNumber = trialNumber {
            self.trialNumber = trialNumber
            self.currentTrialNumber = trialNumber
        }
        
        // Delegate to task-specific handler
        handleTTSReceived(audio: audio, trialNumber: trialNumber)
    }
    
    func didReceiveTaskState(state: TaskState, trialNumber: Int?, message: String?) {
        currentState = state
        if let trialNumber = trialNumber {
            self.trialNumber = trialNumber
        }
        if let message = message {
            statusMessage = message
        } else {
            // Default messages based on state
            switch state {
            case .listening:
                statusMessage = "Listening..."
            case .complete:
                statusMessage = "Task completed!"
            }
        }
        
        // Call hook method for task-specific handling
        handleTaskStateChanged(state: state, trialNumber: trialNumber, message: message)
    }
    
    func didReceiveEvaluationResult(_ result: EvaluationResult) {
        // Delegate to task-specific handler
        handleEvaluationResult(result)
    }
    
    func didReceiveAllResults(_ results: [EvaluationResult]) {
        // Delegate to task-specific handler
        handleAllResults(results)
    }
    
    func didReceiveWordDisplay(word: String, trialNumber: Int, wordIndex: Int) {
        handleWordDisplayReceived(word: word, trialNumber: trialNumber, wordIndex: wordIndex)
    }
    
    func didReceiveStateTransition(phase: String, trialNumber: Int?, message: String?) {
        // Delegate to task-specific handler (subclasses can override handleStateTransitionReceived)
        handleStateTransitionReceived(phase: phase, trialNumber: trialNumber, message: message)
    }
    
    func didReceiveDebug(message: String) {
        print("Debug: \(message)")
        
        // Extract session ID from debug message
        if message.contains("Session ID:") {
            let components = message.components(separatedBy: "Session ID: ")
            if components.count > 1 {
                sessionId = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                print("✅ BaseBackendTaskViewModel: Extracted session ID: \(sessionId ?? "nil")")
            }
        }
    }
    
    func didConnect() {
        isConnected = true
        statusMessage = "Connected"
    }
    
    func didDisconnect() {
        isConnected = false
        statusMessage = "Disconnected"
    }
    
    func didError(_ error: Error) {
        statusMessage = "Error: \(error.localizedDescription)"
        print("WebSocket error: \(error)")
    }
}

