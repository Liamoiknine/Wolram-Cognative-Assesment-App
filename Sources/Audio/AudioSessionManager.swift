import Foundation
import AVFoundation

/// Manages AVAudioSession configuration and state.
/// Provides async methods for session setup and management.
class AudioSessionManager {
    private let audioSession: AVAudioSession
    
    init(audioSession: AVAudioSession = .sharedInstance()) {
        self.audioSession = audioSession
    }
    
    /// Configures the audio session for recording.
    func configureForRecording() async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                    try self.audioSession.setActive(true)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Configures the audio session for playback only.
    func configureForPlayback() async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.audioSession.setCategory(.playback, mode: .default)
                    try self.audioSession.setActive(true)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Deactivates the audio session.
    func deactivate() async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Requests recording permission.
    func requestRecordingPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            audioSession.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

