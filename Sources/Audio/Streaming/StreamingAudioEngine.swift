import Foundation
import AVFoundation

enum StreamingAudioError: Error {
    case recordingPermissionDenied
    case playbackFailed
}

class StreamingAudioEngine {
    private let audioEngine = AVAudioEngine()
    private let inputNode: AVAudioInputNode
    private let playerNode: AVAudioPlayerNode
    private let mixerNode = AVAudioMixerNode()
    
    private var webSocketClient: WebSocketClient?
    private var isStreaming = false
    private var nodesConnected = false
    private var bufferProcessCount: Int = 0
    private var emptyBufferCount: Int = 0
    
    // Audio playback buffering to reduce choppiness
    private var audioPlaybackBuffer: Data = Data()
    private let playbackBufferThreshold: Int = 48000 * 2 // ~1 second at 48kHz (2 bytes per sample for 16-bit)
    private var isPlayingAudio = false
    
    init() {
        print("🎤 StreamingAudioEngine: init() called")
        inputNode = audioEngine.inputNode
        playerNode = AVAudioPlayerNode()
        
        // Setup audio engine - just attach nodes, don't connect yet
        // Connections must happen after audio session is configured
        audioEngine.attach(playerNode)
        audioEngine.attach(mixerNode)
        print("✅ StreamingAudioEngine: init() completed, nodes attached")
    }
    
    // Target format: 16kHz, 16-bit PCM, mono
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!
    
    
    func startStreaming(to webSocket: WebSocketClient) async throws {
        print("🎤 StreamingAudioEngine: startStreaming called")
        guard !isStreaming else {
            print("⚠️ StreamingAudioEngine: Already streaming, returning")
            return
        }
        
        self.webSocketClient = webSocket
        print("✅ StreamingAudioEngine: WebSocket client set")
        
        // Wrap entire operation in do-catch to ensure errors are logged
        do {
            try await performStartStreaming()
        } catch {
            print("❌ StreamingAudioEngine: startStreaming failed with error: \(error)")
            print("   Error type: \(type(of: error))")
            print("   Error description: \(error.localizedDescription)")
            isStreaming = false
            throw error
        }
    }
    
    private func performStartStreaming() async throws {
        
        // Request microphone permission
        print("🎤 StreamingAudioEngine: Requesting microphone permission...")
        let hasPermission = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        print("🎤 StreamingAudioEngine: Permission granted: \(hasPermission)")
        guard hasPermission else {
            print("❌ StreamingAudioEngine: Permission denied")
            throw StreamingAudioError.recordingPermissionDenied
        }
        
        // Configure audio session FIRST - required before connecting nodes
        // Use .playAndRecord with .mixWithOthers to allow TTS while recording
        print("🎤 StreamingAudioEngine: Configuring audio session...")
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Check if input is available
            let inputAvailable = audioSession.isInputAvailable
            print("🎤 StreamingAudioEngine: Input hardware available: \(inputAvailable)")
            
            if !inputAvailable {
                print("⚠️ StreamingAudioEngine: No input hardware available (simulator?)")
            }
            
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
            try audioSession.setActive(true)
            print("✅ StreamingAudioEngine: Audio session configured for playAndRecord with mixWithOthers")
            print("🎤 StreamingAudioEngine: Audio session isActive: \(audioSession.isOtherAudioPlaying ? "other audio playing" : "no other audio"), category: \(audioSession.category.rawValue)")
            
            // Verify session is actually active
            let isActive = audioSession.isOtherAudioPlaying == false || audioSession.category == .playAndRecord
            if !isActive {
                print("⚠️ StreamingAudioEngine: Audio session may not be properly active")
            }
        } catch {
            print("❌ StreamingAudioEngine: Failed to configure audio session: \(error)")
            throw error
        }
        
        // Now get the actual input format (only valid after session is active)
        // Wait a tiny bit to ensure audio session is fully active
        try? await _Concurrency.Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        print("🎤 StreamingAudioEngine: Getting input format...")
        
        // Verify audio session is still active
        let sessionCheck = AVAudioSession.sharedInstance()
        print("🎤 StreamingAudioEngine: Session check - category: \(sessionCheck.category.rawValue)")
        
        // CRITICAL: For recording/streaming, we DON'T need to connect inputNode to output
        // The tap will work without any connection. However, we need at least one connection
        // to prepare the engine. So we'll connect playerNode (for future playback) but NOT inputNode.
        // The inputNode tap will work independently.
        if !nodesConnected {
            print("🎤 StreamingAudioEngine: Setting up audio graph...")
            // Only connect playerNode for playback (we're not using it yet, but it allows engine to prepare)
            // DO NOT connect inputNode - the tap works without connection
            let mainMixer = audioEngine.mainMixerNode
            
            // Get the hardware input format to use as the engine format
            let hardwareInputFormat = inputNode.inputFormat(forBus: 0)
            
            // Connect playerNode with the hardware format so it matches the engine's format
            audioEngine.connect(playerNode, to: mainMixer, format: hardwareInputFormat)
            nodesConnected = true
            print("✅ StreamingAudioEngine: Player node connected with format: \(hardwareInputFormat.sampleRate)Hz, \(hardwareInputFormat.channelCount)ch")
        }
        
        // NOW prepare the engine - we have at least one connection (playerNode)
        print("🎤 StreamingAudioEngine: Preparing audio engine...")
        audioEngine.prepare()
        print("✅ StreamingAudioEngine: Audio engine prepared")
        
        // CRITICAL: Get the actual hardware input format - the tap MUST use this exact format
        // We cannot specify a different format for the tap - it must match hardware exactly
        let hardwareInputFormat = inputNode.inputFormat(forBus: 0)
        print("🎤 StreamingAudioEngine: Hardware input format: \(hardwareInputFormat.sampleRate)Hz, \(hardwareInputFormat.channelCount) channels, \(hardwareInputFormat.commonFormat.rawValue)")
        print("🎤 StreamingAudioEngine: Target format: \(targetFormat.sampleRate)Hz, \(targetFormat.channelCount) channels")
        
        // Install tap on input node BEFORE starting engine
        // IMPORTANT: Install tap AFTER engine is prepared but BEFORE starting
        // The tap works independently - inputNode doesn't need to be connected to anything
        let bufferSize: AVAudioFrameCount = 1024
        print("🎤 StreamingAudioEngine: Installing tap on input node, bufferSize: \(bufferSize)")
        print("🎤 StreamingAudioEngine: Using hardware format: \(hardwareInputFormat)")
        
        // Remove any existing tap first (safely, without accessing format)
        // Just try to remove - if no tap exists, this is safe
        inputNode.removeTap(onBus: 0)
        
        // Install the tap using the EXACT hardware format - this is required
        // The conversion to target format (16kHz mono) will happen in processAudioBuffer
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: hardwareInputFormat) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer)
        }
        print("✅ StreamingAudioEngine: Tap installed on input node with hardware format")
        
        // Start audio engine
        print("🎤 StreamingAudioEngine: Starting audio engine...")
        do {
            // Engine is already prepared, just start it
            try audioEngine.start()
            isStreaming = true
            print("✅ StreamingAudioEngine: Audio engine started successfully, isStreaming: \(isStreaming)")
            print("🎤 StreamingAudioEngine: Audio engine isRunning: \(audioEngine.isRunning)")
            
            // Verify input node is available
            let inputAvailable = inputNode.inputFormat(forBus: 0).sampleRate > 0
            print("🎤 StreamingAudioEngine: Input node available: \(inputAvailable), sampleRate: \(inputNode.inputFormat(forBus: 0).sampleRate)Hz")
            
            // Set up periodic check to verify engine is still running
            _Concurrency.Task {
                for i in 1...10 {
                    try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    print("🔍 StreamingAudioEngine: Health check #\(i) - isRunning: \(self.audioEngine.isRunning), isStreaming: \(self.isStreaming), bufferCount: \(self.bufferProcessCount)")
                }
            }
        } catch {
            print("❌ StreamingAudioEngine: Failed to start audio engine: \(error)")
            throw error
        }
    }
    
    func stop() {
        guard isStreaming else { return }
        
        print("🛑 StreamingAudioEngine: Stopping audio engine...")
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isStreaming = false
        nodesConnected = false
        webSocketClient = nil
        print("✅ StreamingAudioEngine: Audio engine stopped, processed \(bufferProcessCount) buffers, \(emptyBufferCount) empty buffers")
    }
    
    func playAudioBuffer(_ buffer: AVAudioPCMBuffer) async throws {
        // Get the player node's output format (the format it was connected with)
        // Since we connected playerNode to mainMixer with hardwareInputFormat,
        // that's the format the playerNode expects
        let hardwareInputFormat = inputNode.inputFormat(forBus: 0)
        let playerOutputFormat = hardwareInputFormat
        
        print("🎵 StreamingAudioEngine: Playing audio - buffer format: \(buffer.format.sampleRate)Hz, \(buffer.format.channelCount)ch, \(buffer.format.commonFormat.rawValue), player expects: \(playerOutputFormat.sampleRate)Hz, \(playerOutputFormat.channelCount)ch, \(playerOutputFormat.commonFormat.rawValue)")
        
        // Convert to player output format for playback
        let convertedBuffer: AVAudioPCMBuffer
        if buffer.format != playerOutputFormat {
            guard let converter = AVAudioConverter(from: buffer.format, to: playerOutputFormat) else {
                print("❌ StreamingAudioEngine: Failed to create audio converter")
                print("   From: \(buffer.format)")
                print("   To: \(playerOutputFormat)")
                throw StreamingAudioError.playbackFailed
            }
            
            let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * (playerOutputFormat.sampleRate / buffer.format.sampleRate))
            guard let converted = AVAudioPCMBuffer(pcmFormat: playerOutputFormat, frameCapacity: frameCapacity) else {
                print("❌ StreamingAudioEngine: Failed to create converted buffer")
                throw StreamingAudioError.playbackFailed
            }
            
            var error: NSError?
            let inputStatus = converter.convert(to: converted, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            if let error = error {
                print("❌ StreamingAudioEngine: Audio conversion error: \(error)")
                throw error
            }
            
            if inputStatus == .error {
                print("❌ StreamingAudioEngine: Conversion returned error status")
                throw StreamingAudioError.playbackFailed
            }
            
            guard converted.frameLength > 0 else {
                print("⚠️ StreamingAudioEngine: Converted buffer has 0 frames")
                throw StreamingAudioError.playbackFailed
            }
            
            convertedBuffer = converted
            print("✅ StreamingAudioEngine: Converted audio for playback - \(converted.frameLength) frames, format: \(converted.format)")
        } else {
            convertedBuffer = buffer
            print("✅ StreamingAudioEngine: No conversion needed, using buffer directly")
        }
        
        // Verify format matches before scheduling
        let playerFormat = playerNode.outputFormat(forBus: 0)
        if convertedBuffer.format.channelCount != playerFormat.channelCount {
            print("❌ StreamingAudioEngine: Channel count mismatch! Buffer: \(convertedBuffer.format.channelCount), Player: \(playerFormat.channelCount)")
            throw StreamingAudioError.playbackFailed
        }
        
        // Schedule buffer for playback
        playerNode.scheduleBuffer(convertedBuffer, completionHandler: nil)
        
        // Start player if not already playing
        if !playerNode.isPlaying {
            playerNode.play()
            print("▶️ StreamingAudioEngine: Started audio playback")
        }
    }
    
    func playAudioData(_ data: Data) async throws {
        // Buffer audio data to reduce choppiness from small chunks
        audioPlaybackBuffer.append(data)
        
        // Play when we have enough buffered data
        // Smaller threshold for lower latency, but still buffers to reduce choppiness
        let minBufferSize = 8000  // ~0.25 second at 16kHz (2 bytes per sample)
        
        if audioPlaybackBuffer.count >= minBufferSize {
            let dataToPlay = audioPlaybackBuffer
            audioPlaybackBuffer.removeAll()
            
            try await _playBufferedAudio(dataToPlay)
        }
    }
    
    func flushAudioBuffer() async throws {
        // Flush any remaining buffered audio
        if audioPlaybackBuffer.count > 0 {
            let dataToPlay = audioPlaybackBuffer
            audioPlaybackBuffer.removeAll()
            try await _playBufferedAudio(dataToPlay)
        }
    }
    
    private func _playBufferedAudio(_ dataToPlay: Data) async throws {
        // Convert Data to AVAudioPCMBuffer
        // Data is 16kHz, 16-bit PCM, mono (Int16)
        let frameCount = dataToPlay.count / 2  // 2 bytes per sample (16-bit)
        guard frameCount > 0 else { return }
        
        // Create buffer in target format (16kHz, Int16, mono)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
            print("❌ StreamingAudioEngine: Failed to create PCM buffer")
            throw StreamingAudioError.playbackFailed
        }
        
        buffer.frameLength = AVAudioFrameCount(frameCount)
        
        // Copy Int16 data to buffer
        dataToPlay.withUnsafeBytes { bytes in
            guard let int16Pointer = buffer.int16ChannelData?[0] else {
                print("❌ StreamingAudioEngine: No int16 channel data")
                return
            }
            let samples = bytes.bindMemory(to: Int16.self)
            int16Pointer.initialize(from: samples.baseAddress!, count: frameCount)
        }
        
        try await playAudioBuffer(buffer)
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let webSocketClient = webSocketClient else {
            print("⚠️ StreamingAudioEngine: processAudioBuffer called but webSocketClient is nil")
            return
        }
        
        // Check if buffer has data
        guard buffer.frameLength > 0 else {
            // Log occasionally to avoid spam
            emptyBufferCount += 1
            if emptyBufferCount % 100 == 0 {
                print("⚠️ StreamingAudioEngine: Empty buffer #\(emptyBufferCount), format: \(buffer.format)")
            }
            return  // Skip empty buffers
        }
        
        // Log first few buffers to confirm we're getting data
        bufferProcessCount += 1
        if bufferProcessCount <= 5 || bufferProcessCount % 100 == 0 {
            print("🎤 StreamingAudioEngine: Processing buffer #\(bufferProcessCount), frames: \(buffer.frameLength), format: \(buffer.format.sampleRate)Hz")
        }
        
        // Convert to target format if needed
        let processedBuffer: AVAudioPCMBuffer
        if buffer.format != targetFormat {
            guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
                print("⚠️ StreamingAudioEngine: Failed to create audio converter")
                return
            }
            
            let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * (targetFormat.sampleRate / buffer.format.sampleRate))
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
                print("⚠️ StreamingAudioEngine: Failed to create converted buffer")
                return
            }
            
            var error: NSError?
            let inputStatus = converter.convert(to: converted, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            if let error = error {
                print("❌ StreamingAudioEngine: Audio conversion error: \(error)")
                return
            }
            
            if inputStatus == .error {
                print("❌ StreamingAudioEngine: Conversion returned error status")
                return
            }
            
            guard converted.frameLength > 0 else {
                print("⚠️ StreamingAudioEngine: Converted buffer has 0 frames")
                return
            }
            
            processedBuffer = converted
        } else {
            processedBuffer = buffer
        }
        
        // Convert buffer to Data (PCM 16-bit)
        guard let channelData = processedBuffer.int16ChannelData?[0] else {
            print("⚠️ StreamingAudioEngine: No channel data available")
            return
        }
        
        let frameCount = Int(processedBuffer.frameLength)
        guard frameCount > 0 else {
            print("⚠️ StreamingAudioEngine: Frame count is 0")
            return
        }
        
        let data = Data(bytes: channelData, count: frameCount * 2)  // 2 bytes per sample
        
        // Log first few sends
        if bufferProcessCount <= 5 || bufferProcessCount % 100 == 0 {
            print("📤 StreamingAudioEngine: Sending audio data, size: \(data.count) bytes, frames: \(frameCount)")
        }
        
        // Send to WebSocket
        webSocketClient.sendAudioChunk(data, sampleRate: Int(targetFormat.sampleRate))
    }
}
