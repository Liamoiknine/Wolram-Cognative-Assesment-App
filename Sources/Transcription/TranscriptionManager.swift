import Foundation
import Speech

/// Speech framework-based implementation of TranscriptionManagerProtocol.
/// Provides async transcription with callback-based results.
@available(iOS 13.0, macOS 10.15, *)
class TranscriptionManager: TranscriptionManagerProtocol {
    private let fileStorage: FileStorageProtocol
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechRecognitionRequest?
    private let speechRecognizer: SFSpeechRecognizer
    
    var isTranscribing: Bool {
        guard let task = recognitionTask else { return false }
        return !task.isCancelled && task.state != .completed && task.state != .canceling
    }
    
    init(fileStorage: FileStorageProtocol, locale: Locale = .current) {
        self.fileStorage = fileStorage
        self.speechRecognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    }
    
    func startTranscription(from path: String, completion: @escaping (Result<String, Error>) -> Void) async throws {
        print("🎤 TranscriptionManager: Starting transcription from path: \(path)")
        
        // Stop any existing transcription
        if isTranscribing {
            print("⚠️ TranscriptionManager: Stopping existing transcription")
            try await stopTranscription()
        }
        
        // Request authorization
        print("🔐 TranscriptionManager: Requesting speech recognition authorization")
        let status = await requestAuthorization()
        print("   Authorization status: \(status.rawValue)")
        guard status == .authorized else {
            print("❌ TranscriptionManager: Authorization denied (status: \(status.rawValue))")
            completion(.failure(TranscriptionError.authorizationDenied))
            return
        }
        print("✅ TranscriptionManager: Authorization granted")
        
        // Get full path from file storage
        let fullPath = fileStorage.path(for: path)
        let url = URL(fileURLWithPath: fullPath)
        print("📁 TranscriptionManager: Full file path: \(fullPath)")
        print("   File exists: \(FileManager.default.fileExists(atPath: fullPath))")
        
        // Create recognition request
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        print("📋 TranscriptionManager: Created recognition request")
        
        recognitionRequest = request
        
        // Start recognition task
        print("▶️ TranscriptionManager: Starting recognition task...")
        
        // Set up a timeout to handle cases where recognition never completes
        let completionQueue = DispatchQueue(label: "com.transcription.completion")
        var hasCompleted = false
        var timeoutTask: _Concurrency.Task<Void, Never>?
        
        timeoutTask = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(nanoseconds: 60_000_000_000) // 60 second timeout
            completionQueue.sync {
                if !hasCompleted {
                    print("⏰ TranscriptionManager: Recognition timeout (60s), cancelling task")
                    recognitionTask?.cancel()
                    hasCompleted = true
                    completion(.failure(TranscriptionError.transcriptionFailed))
                }
            }
        }
        
        recognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
            var shouldComplete = false
            var completionResult: Result<String, Error>?
            
            completionQueue.sync {
                if hasCompleted {
                    return // Already handled
                }
                
            if let error = error {
                    print("❌ TranscriptionManager: Recognition task error: \(error.localizedDescription)")
                    print("   Error code: \((error as NSError).code)")
                    print("   Error domain: \((error as NSError).domain)")
                    hasCompleted = true
                    shouldComplete = true
                    timeoutTask?.cancel()
                    completionResult = .failure(error)
                return
            }
            
                if let result = result {
                    print("📝 TranscriptionManager: Recognition result received (isFinal: \(result.isFinal))")
                    if result.isFinal {
                let transcribedText = result.bestTranscription.formattedString
                        print("✅ TranscriptionManager: Final transcription: \"\(transcribedText)\"")
                        hasCompleted = true
                        shouldComplete = true
                        timeoutTask?.cancel()
                        completionResult = .success(transcribedText)
                    } else {
                        print("⏳ TranscriptionManager: Partial result (waiting for final)")
            }
                } else {
                    print("⚠️ TranscriptionManager: Recognition callback called with no result and no error")
                    // Check if task is completed - might be empty audio
                    if let task = self.recognitionTask, task.state == .completed {
                        print("⚠️ TranscriptionManager: Task completed with no result, assuming empty audio")
                        hasCompleted = true
                        shouldComplete = true
                        timeoutTask?.cancel()
                        completionResult = .success("")
                    }
                }
            }
            
            if shouldComplete, let result = completionResult {
                completion(result)
            }
        }
        print("✅ TranscriptionManager: Recognition task started")
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

