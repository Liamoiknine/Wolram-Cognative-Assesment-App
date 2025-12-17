import Foundation
import AVFoundation

/// Simple audio recorder for fixed-duration recording
class SimpleAudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var isRecording = false
    
    /// Record audio for a fixed duration
    /// Returns PCM audio data (16kHz, 16-bit, mono)
    func recordForDuration(_ duration: TimeInterval) async throws -> Data {
        // Request microphone permission
        let hasPermission = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        
        guard hasPermission else {
            throw AudioError.recordingPermissionDenied
        }
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .default)
        try audioSession.setActive(true)
        
        // Setup audio engine
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        // Target format: 16kHz, 16-bit PCM, mono
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioError.recordingFailed
        }
        
        // Create temporary file for recording
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        
        // Remove file if it exists
        try? FileManager.default.removeItem(at: tempURL)
        
        // Create audio file with target format
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: targetFormat.sampleRate,
            AVNumberOfChannelsKey: targetFormat.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: !targetFormat.isInterleaved
        ]
        
        guard let audioFile = try? AVAudioFile(
            forWriting: tempURL,
            settings: fileSettings
        ) else {
            throw AudioError.recordingFailed
        }
        
        // Use the file's actual processing format (may differ slightly from our target)
        let fileFormat = audioFile.processingFormat
        
        self.audioFile = audioFile
        self.audioEngine = engine
        
        // Install tap
        let bufferSize: AVAudioFrameCount = 1024
        
        // Convert format if needed - convert to file format, not target format
        let converter: AVAudioConverter?
        if inputFormat != fileFormat {
            guard let conv = AVAudioConverter(from: inputFormat, to: fileFormat) else {
                throw AudioError.recordingFailed
            }
            converter = conv
        } else {
            converter = nil
        }
        
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            guard let self = self, let audioFile = self.audioFile else { return }
            
            if let converter = converter {
                // Convert buffer to file format
                let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * (fileFormat.sampleRate / buffer.format.sampleRate))
                guard let converted = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: frameCapacity) else {
                    return
                }
                
                var error: NSError?
                let status = converter.convert(to: converted, error: &error) { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }
                
                if status == .haveData, converted.frameLength > 0 {
                    do {
                        try audioFile.write(from: converted)
                    } catch {
                        print("⚠️ SimpleAudioRecorder: Error writing converted buffer: \(error)")
                    }
                }
            } else {
                // Direct write - format should match
                do {
                    try audioFile.write(from: buffer)
                } catch {
                    print("⚠️ SimpleAudioRecorder: Error writing buffer: \(error)")
                }
            }
        }
        
        // Prepare and start engine
        engine.prepare()
        try engine.start()
        isRecording = true
        
        // Record for specified duration
        try await _Concurrency.Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        
        // Stop recording
        inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        
        // Read recorded data
        let recordedData = try Data(contentsOf: tempURL)
        
        // Extract PCM data from WAV file (skip header)
        // Simple WAV header is 44 bytes
        let pcmData = recordedData.suffix(from: 44)
        
        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
        try? audioSession.setActive(false)
        
        return Data(pcmData)
    }
    
    func stop() {
        guard isRecording else { return }
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        isRecording = false
    }
}

