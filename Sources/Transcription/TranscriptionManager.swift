import Foundation
import Speech

/// Speech framework-based implementation of TranscriptionManagerProtocol.
/// Provides async transcription with callback-based results.
class TranscriptionManager: TranscriptionManagerProtocol {
    private let fileStorage: FileStorageProtocol
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private let speechRecognizer: SFSpeechRecognizer
    
    var isTranscribing: Bool {
        return recognitionTask != nil && recognitionTask?.state != .completed && recognitionTask?.state != .cancelled
    }
    
    init(fileStorage: FileStorageProtocol, locale: Locale = .current) {
        self.fileStorage = fileStorage
        self.speechRecognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    }
    
    func startTranscription(from path: String, completion: @escaping (Result<String, Error>) -> Void) async throws {
        // Stop any existing transcription
        if isTranscribing {
            try await stopTranscription()
        }
        
        // Request authorization
        let status = await requestAuthorization()
        guard status == .authorized else {
            completion(.failure(TranscriptionError.authorizationDenied))
            return
        }
        
        // Get full path from file storage
        let fullPath = fileStorage.path(for: path)
        let url = URL(fileURLWithPath: fullPath)
        
        // Create recognition request
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        
        recognitionRequest = request
        
        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            if let result = result, result.isFinal {
                let transcribedText = result.bestTranscription.formattedString
                completion(.success(transcribedText))
            }
        }
    }
    
    func stopTranscription() async throws {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }
    
    private func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

enum TranscriptionError: LocalizedError {
    case authorizationDenied
    case transcriptionFailed
    
    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Speech recognition authorization was denied"
        case .transcriptionFailed:
            return "Transcription failed"
        }
    }
}

