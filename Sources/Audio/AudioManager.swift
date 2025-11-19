import Foundation
import AVFoundation

/// AVFoundation-based implementation of AudioManagerProtocol.
/// Handles audio recording and playback with async operations.
class AudioManager: AudioManagerProtocol {
    private let fileStorage: FileStorageProtocol
    private let sessionManager: AudioSessionManager
    
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingStartTime: Date?
    
    var isRecording: Bool {
        return audioRecorder?.isRecording ?? false
    }
    
    var isPlaying: Bool {
        return audioPlayer?.isPlaying ?? false
    }
    
    init(fileStorage: FileStorageProtocol, sessionManager: AudioSessionManager = AudioSessionManager()) {
        self.fileStorage = fileStorage
        self.sessionManager = sessionManager
    }
    
    func startRecording(to path: String) async throws {
        // Ensure previous recording is stopped
        if isRecording {
            _ = try await stopRecording()
        }
        
        // Request permission
        let hasPermission = await sessionManager.requestRecordingPermission()
        guard hasPermission else {
            throw AudioError.recordingPermissionDenied
        }
        
        // Configure session
        try await sessionManager.configureForRecording()
        
        // Get full path from file storage
        let fullPath = fileStorage.path(for: path)
        
        // Ensure directory exists
        let directory = (fullPath as NSString).deletingLastPathComponent
        try await fileStorage.createDirectory(at: directory)
        
        // Configure recorder settings
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        // Create recorder
        let url = URL(fileURLWithPath: fullPath)
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        
        // Start recording
        let success = recorder.record()
        guard success else {
            throw AudioError.recordingFailed
        }
        
        audioRecorder = recorder
        recordingStartTime = Date()
    }
    
    func stopRecording() async throws -> TimeInterval {
        guard let recorder = audioRecorder else {
            throw AudioError.notRecording
        }
        
        let duration: TimeInterval
        if let startTime = recordingStartTime {
            duration = Date().timeIntervalSince(startTime)
        } else {
            duration = recorder.currentTime
        }
        
        recorder.stop()
        audioRecorder = nil
        recordingStartTime = nil
        
        try await sessionManager.deactivate()
        
        return duration
    }
    
    func play(from path: String) async throws {
        // Stop any current playback
        if isPlaying {
            try await stopPlayback()
        }
        
        // Configure session for playback
        try await sessionManager.configureForPlayback()
        
        // Get full path from file storage
        let fullPath = fileStorage.path(for: path)
        let url = URL(fileURLWithPath: fullPath)
        
        // Create player
        let player = try AVAudioPlayer(contentsOf: url)
        player.prepareToPlay()
        
        // Play
        let success = player.play()
        guard success else {
            throw AudioError.playbackFailed
        }
        
        audioPlayer = player
        
        // Wait for playback to complete
        while player.isPlaying {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        try await stopPlayback()
    }
    
    func stopPlayback() async throws {
        audioPlayer?.stop()
        audioPlayer = nil
        try await sessionManager.deactivate()
    }
}

enum AudioError: LocalizedError {
    case recordingPermissionDenied
    case recordingFailed
    case notRecording
    case playbackFailed
    
    var errorDescription: String? {
        switch self {
        case .recordingPermissionDenied:
            return "Recording permission was denied"
        case .recordingFailed:
            return "Failed to start recording"
        case .notRecording:
            return "No active recording to stop"
        case .playbackFailed:
            return "Failed to start playback"
        }
    }
}

