import Foundation
import AudioToolbox

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
    
    /// Plays a system beep sound to indicate when to start or end speaking.
    /// - Parameter soundID: System sound ID to play. Default is 1057 (short beep).
    func playBeep(soundID: SystemSoundID) async throws
    
    /// Speaks the provided text using text-to-speech.
    /// Uses the device locale for speech synthesis.
    /// Awaits completion of the speech before returning.
    func speak(_ text: String) async throws
    
    /// Checks if currently recording.
    var isRecording: Bool { get }
    
    /// Checks if currently playing.
    var isPlaying: Bool { get }
    
    /// Checks if currently speaking.
    var isSpeaking: Bool { get }
}

