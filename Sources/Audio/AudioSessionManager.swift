import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Manages AVAudioSession configuration and state.
/// Provides async methods for session setup and management.
@available(iOS 13.0, *)
class AudioSessionManager {
    #if os(iOS)
    private let audioSession: AVAudioSession
    
    init(audioSession: AVAudioSession = .sharedInstance()) {
        self.audioSession = audioSession
    }
    #else
    init() {
        // macOS doesn't have AVAudioSession
        fatalError("AudioSessionManager is iOS-only")
    }
    #endif
    
    /// Configures the audio session for recording.
    func configureForRecording() async throws {
        #if os(iOS)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
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
        #else
        // macOS doesn't need audio session configuration
        #endif
    }
    
    /// Configures the audio session for playback only.
    func configureForPlayback() async throws {
        #if os(iOS)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // Use .playback category with .defaultToSpeaker to ensure audio goes to speaker
                    // and .duckOthers to reduce other audio if needed
                    try self.audioSession.setCategory(.playback, mode: .spokenAudio, options: [.defaultToSpeaker, .duckOthers])
                    try self.audioSession.setActive(true, options: [])
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        #else
        // macOS doesn't need audio session configuration
        #endif
    }
    
    /// Deactivates the audio session.
    func deactivate() async throws {
        #if os(iOS)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        #else
        // macOS doesn't need audio session deactivation
        #endif
    }
    
    /// Requests recording permission.
    func requestRecordingPermission() async -> Bool {
        #if os(iOS)
        await withCheckedContinuation { continuation in
            audioSession.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        #else
        // macOS doesn't need permission requests
        return true
        #endif
    }
}

