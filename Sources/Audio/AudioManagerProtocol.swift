import Foundation

/// Protocol for audio recording and playback operations.
/// All operations are asynchronous to avoid blocking the main thread.
protocol AudioManagerProtocol {
    /// Starts recording audio to the specified file path.
    /// Returns the duration of the recording when stopped.
    func startRecording(to path: String) async throws
    
    /// Stops the current recording.
    /// Returns the duration of the recording.
    func stopRecording() async throws -> TimeInterval
    
    /// Plays an audio file from the specified path.
    func play(from path: String) async throws
    
    /// Stops the current playback.
    func stopPlayback() async throws
    
    /// Checks if currently recording.
    var isRecording: Bool { get }
    
    /// Checks if currently playing.
    var isPlaying: Bool { get }
}

