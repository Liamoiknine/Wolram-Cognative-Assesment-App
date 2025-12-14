import Foundation
import AVFoundation
import AudioToolbox


/// Helper function to sleep using Swift's concurrency Task.
/// Uses _Concurrency.Task to explicitly reference Swift's concurrency Task type.
fileprivate func sleepTask(nanoseconds: UInt64) async throws {
    try await _Concurrency.Task.sleep(nanoseconds: nanoseconds)
}


/// AVFoundation-based implementation of AudioManagerProtocol.
/// Handles audio recording and playback with async operations.
@available(iOS 13.0, macOS 10.15, *)
class AudioManager: AudioManagerProtocol {
    private let fileStorage: FileStorageProtocol
    private let sessionManager: AudioSessionManager
    
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingStartTime: Date?
    private var speechSynthesizer: AVSpeechSynthesizer?
    private var speechDelegate: SpeechSynthesizerDelegate?
    private var speechCompletionContinuation: CheckedContinuation<Void, Error>?
    
    var isRecording: Bool {
        return audioRecorder?.isRecording ?? false
    }
    
    var isPlaying: Bool {
        return audioPlayer?.isPlaying ?? false
    }
    
    var isSpeaking: Bool {
        return speechSynthesizer?.isSpeaking ?? false
    }
    
    init(fileStorage: FileStorageProtocol, sessionManager: AudioSessionManager = AudioSessionManager()) {
        self.fileStorage = fileStorage
        self.sessionManager = sessionManager
    }
    
    func startRecording(to path: String) async throws {
        print("🎙️ AudioManager: Starting recording to: \(path)")
        
        // Ensure previous recording is stopped
        if isRecording {
            print("⚠️ AudioManager: Stopping previous recording")
            _ = try await stopRecording()
            // Small delay to allow cleanup
            try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        // Request permission
        print("🔐 AudioManager: Requesting recording permission")
        let hasPermission = await sessionManager.requestRecordingPermission()
        guard hasPermission else {
            print("❌ AudioManager: Recording permission denied")
            throw AudioError.recordingPermissionDenied
        }
        print("✅ AudioManager: Recording permission granted")
        
        // Configure session
        print("🔧 AudioManager: Configuring audio session for recording")
        try await sessionManager.configureForRecording()
        print("✅ AudioManager: Audio session configured for recording")
        
        // Get full path from file storage
        let fullPath = fileStorage.path(for: path)
        print("📁 AudioManager: Full path: \(fullPath)")
        
        // Ensure directory exists - use relative path, not absolute
        // Extract relative directory from the original path parameter
        let relativeDirectory = (path as NSString).deletingLastPathComponent
        print("📁 AudioManager: Creating directory: \(relativeDirectory)")
        try await fileStorage.createDirectory(at: relativeDirectory)
        print("✅ AudioManager: Directory created/verified")
        
        // Configure recorder settings
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        // Create recorder
        let url = URL(fileURLWithPath: fullPath)
        print("📁 AudioManager: Recording URL: \(url)")
        print("📁 AudioManager: URL exists: \(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))")
        
        // Verify the directory actually exists before creating recorder
        let directoryURL = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            print("⚠️ AudioManager: Directory doesn't exist, creating it directly...")
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            print("✅ AudioManager: Directory created directly via FileManager")
        }
        
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        print("✅ AudioManager: AVAudioRecorder created")
        
        let prepared = recorder.prepareToRecord()
        print("📝 AudioManager: prepareToRecord() returned: \(prepared)")
        guard prepared else {
            print("❌ AudioManager: prepareToRecord() failed")
            throw AudioError.recordingFailed
        }
        
        // Start recording
        let success = recorder.record()
        print("🎙️ AudioManager: recorder.record() returned: \(success)")
        guard success else {
            print("❌ AudioManager: recorder.record() returned false")
            print("   - Recorder isRecording: \(recorder.isRecording)")
            print("   - URL: \(url)")
            throw AudioError.recordingFailed
        }
        
        print("✅ AudioManager: Recording started successfully")
        
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
        
        print("⏹️ AudioManager: Stopping recording (duration: \(String(format: "%.2f", duration))s)")
        recorder.stop()
        audioRecorder = nil
        recordingStartTime = nil
        
        print("🔧 AudioManager: Deactivating audio session after recording")
        // Small delay before deactivating to allow final audio processing
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        try await sessionManager.deactivate()
        print("✅ AudioManager: Audio session deactivated after recording")
        
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
            try await sleepTask(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        try await stopPlayback()
    }
    
    func stopPlayback() async throws {
        audioPlayer?.stop()
        audioPlayer = nil
        try await sessionManager.deactivate()
    }
    
    /// Plays a system beep sound to indicate when to start or end speaking.
    /// - Parameter soundID: System sound ID to play. Default is 1057 (short beep).
    ///   Use 1057 for start beep, 1054 for end beep (different pitch).
    func playBeep(soundID: SystemSoundID) async throws {
        print("🔔 AudioManager: Playing beep sound (ID: \(soundID))")
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            AudioServicesPlaySystemSoundWithCompletion(soundID) {
                continuation.resume()
            }
        }
    }
    
    /// Selects a specific, known-good voice for text-to-speech.
    /// Uses explicit voice selection to avoid novelty or inappropriate voices.
    private func selectBestVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        // Get all available voices
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        
        // For English, explicitly select Samantha or Alex (standard, natural voices)
        if languageCode.hasPrefix("en") {
            // Try Samantha first (most common, natural female voice)
            if let samantha = allVoices.first(where: { 
                $0.name == "Samantha" && $0.language.hasPrefix(languageCode)
            }) {
                print("✅ AudioManager: Selected explicit voice: Samantha (\(samantha.identifier))")
                return samantha
            }
            
            // Try Alex second (natural male voice)
            if let alex = allVoices.first(where: { 
                $0.name == "Alex" && $0.language.hasPrefix(languageCode)
            }) {
                print("✅ AudioManager: Selected explicit voice: Alex (\(alex.identifier))")
                return alex
            }
        }
        
        // Fallback: Use language default
        if let defaultVoice = AVSpeechSynthesisVoice(language: languageCode) {
            print("✅ AudioManager: Using language default voice: \(defaultVoice.name) (\(defaultVoice.identifier))")
            return defaultVoice
        }
        
        // Absolute last resort
        print("⚠️ AudioManager: Using system default voice")
        return AVSpeechSynthesisVoice(language: languageCode)
    }
    
    func speak(_ text: String) async throws {
        print("🔊 AudioManager: Starting TTS for text: \"\(text.prefix(50))\(text.count > 50 ? "..." : "")\"")
        
        // Stop any current speech
        if isSpeaking {
            print("⚠️ AudioManager: Stopping current speech before starting new")
            stopSpeaking()
            // Small delay to allow cleanup
            try? await _Concurrency.Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        }
        
        // Configure session for playback
        print("🔧 AudioManager: Configuring audio session for playback")
        try await sessionManager.configureForPlayback()
        print("✅ AudioManager: Audio session configured for playback")
        
        // Create speech synthesizer if needed
        let synthesizer = AVSpeechSynthesizer()
        speechSynthesizer = synthesizer
        
        // Create speech utterance
        let utterance = AVSpeechUtterance(string: text)
        
        // Select the most natural-sounding voice available
        let languageCode = Locale.current.language.languageCode?.identifier ?? "en-US"
        if let bestVoice = selectBestVoice(for: languageCode) {
            utterance.voice = bestVoice
        }
        
        // Adjust speech parameters for more natural sound
        // Rate: 0.0 (slowest) to 1.0 (fastest), default is 0.5
        // Slightly slower rate (0.45) sounds more natural and easier to understand
        utterance.rate = 0.45
        
        // Pitch: 0.5 (lowest) to 2.0 (highest), default is 1.0
        // Keep at 1.0 for natural pitch
        utterance.pitchMultiplier = 1.0
        
        // Volume: 0.0 (silent) to 1.0 (loudest), default is 1.0
        // Keep at 1.0 for clear audio
        utterance.volume = 1.0
        
        // Wait for speech to complete
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            speechCompletionContinuation = continuation
            
            // Create and retain delegate to handle completion
            let delegate = SpeechSynthesizerDelegate { [weak self] in
                self?.speechCompletionContinuation?.resume()
                self?.speechCompletionContinuation = nil
                self?.speechSynthesizer = nil
                self?.speechDelegate = nil
            }
            speechDelegate = delegate
            synthesizer.delegate = delegate
            
            // Start speaking (speak() returns Void, so we can't check for success directly)
            print("▶️ AudioManager: Starting speech synthesis")
            synthesizer.speak(utterance)
        }
        
        print("✅ AudioManager: Speech synthesis completed, deactivating audio session")
        // Small delay before deactivating to allow final audio processing
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        try await sessionManager.deactivate()
        print("✅ AudioManager: Audio session deactivated")
    }
    
    private func stopSpeaking() {
        speechSynthesizer?.stopSpeaking(at: .immediate)
        speechCompletionContinuation?.resume(throwing: AudioError.speechCancelled)
        speechCompletionContinuation = nil
        speechSynthesizer = nil
        speechDelegate = nil
    }
}

/// Delegate for AVSpeechSynthesizer to handle speech completion.
@available(iOS 13.0, macOS 10.15, *)
private class SpeechSynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate {
    private let onFinish: () -> Void
    
    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinish()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        // No action needed
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        // No action needed
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        // No action needed
    }
}

@available(iOS 13.0, macOS 10.15, *)
enum AudioError: LocalizedError {
    case recordingPermissionDenied
    case recordingFailed
    case notRecording
    case playbackFailed
    case speechSynthesisFailed
    case speechCancelled
    
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
        case .speechSynthesisFailed:
            return "Failed to start speech synthesis"
        case .speechCancelled:
            return "Speech was cancelled"
        }
    }
}

