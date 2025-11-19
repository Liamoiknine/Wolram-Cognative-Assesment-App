import Foundation

/// Protocol for speech transcription operations.
/// All operations are asynchronous with callback-based results.
protocol TranscriptionManagerProtocol {
    /// Starts transcribing audio from the specified file path.
    /// Results are delivered via the completion callback.
    func startTranscription(from path: String, completion: @escaping (Result<String, Error>) -> Void) async throws
    
    /// Stops the current transcription if in progress.
    func stopTranscription() async throws
    
    /// Checks if currently transcribing.
    var isTranscribing: Bool { get }
}

