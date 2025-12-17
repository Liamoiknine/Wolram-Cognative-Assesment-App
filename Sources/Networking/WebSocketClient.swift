import Foundation

// Import message types
// Note: These are defined in BackendMessage.swift and should be available
// If compilation fails, ensure BackendMessage.swift is included in the build

protocol WebSocketClientDelegate: AnyObject {
    func didReceiveTTS(audio: Data, trialNumber: Int?)
    func didReceiveTaskState(state: TaskState, trialNumber: Int?, message: String?)
    func didReceiveDebug(message: String)
    func didReceiveEvaluationResult(_ result: EvaluationResult)
    func didReceiveAllResults(_ results: [EvaluationResult])
    func didReceiveWordDisplay(word: String, trialNumber: Int, wordIndex: Int)
    func didReceiveStateTransition(phase: String, trialNumber: Int?, message: String?)
    func didConnect()
    func didDisconnect()
    func didError(_ error: Error)
}

class WebSocketClient {
    weak var delegate: WebSocketClientDelegate?
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let url: URL
    private var isConnected: Bool = false
    private var audioChunkCount: Int = 0
    
    init(url: URL) {
        self.url = url
    }
    
    func connect() async throws {
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        isConnected = true
        
        // Ensure delegate call happens on main thread
        await MainActor.run {
            delegate?.didConnect()
        }
        
        // Start listening for messages in background (don't await - it runs forever)
        // This allows connect() to return so audio streaming can start
        _Concurrency.Task {
            await self.receiveMessages()
        }
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isConnected = false
        _Concurrency.Task { @MainActor in
            delegate?.didDisconnect()
        }
    }
    
    func sendAudioChunk(_ pcmData: Data, sampleRate: Int) {
        guard isConnected, let webSocketTask = webSocketTask else { return }
        
        // Only send non-empty audio chunks
        guard pcmData.count > 0 else {
            return
        }
        
        // Log periodically (every ~1 second of audio at 16kHz = 32000 bytes)
        audioChunkCount += 1
        if audioChunkCount % 100 == 0 {  // Log every 100 chunks
            print("🎤 WebSocket: Sending audio chunk #\(audioChunkCount), size: \(pcmData.count) bytes")
        }
        
        let base64Audio = pcmData.base64EncodedString()
        let audioChunk = AudioChunk(
            audio: base64Audio,
            sampleRate: sampleRate,
            format: "pcm_16bit_mono"
        )
        
        let message = ClientMessage(
            type: "audio_chunk",
            data: .audioChunk(audioChunk)
        )
        
        sendMessage(message)
    }
    
    func sendEvent(_ action: String) {
        let event = ClientEvent(action: action)
        let message = ClientMessage(
            type: "event",
            data: .event(event)
        )
        
        sendMessage(message)
    }
    
    private func sendMessage(_ message: ClientMessage) {
        guard let webSocketTask = webSocketTask else {
            print("⚠️ WebSocket: Cannot send message - webSocketTask is nil")
            return
        }
        
        guard isConnected else {
            print("⚠️ WebSocket: Cannot send message - not connected")
            return
        }
        
        do {
            // Manually construct JSON to handle the nested data structure
            var jsonDict: [String: Any] = ["type": message.type]
            
            switch message.data {
            case .audioChunk(let chunk):
                jsonDict["data"] = [
                    "audio": chunk.audio,
                    "sample_rate": chunk.sampleRate,
                    "format": chunk.format
                ]
            case .event(let event):
                jsonDict["data"] = [
                    "action": event.action
                ]
            }
            
            let jsonData = try JSONSerialization.data(withJSONObject: jsonDict)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)
                webSocketTask.send(wsMessage) { error in
                    if let error = error {
                        print("❌ WebSocket: Error sending message: \(error)")
                        _Concurrency.Task { @MainActor in
                            self.delegate?.didError(error)
                        }
                    }
                }
            } else {
                print("❌ WebSocket: Failed to convert JSON data to string")
            }
        } catch {
            print("❌ WebSocket: Error encoding message: \(error)")
            _Concurrency.Task { @MainActor in
                delegate?.didError(error)
            }
        }
    }
    
    private func receiveMessages() async {
        guard let webSocketTask = webSocketTask else { return }
        
        while isConnected {
            do {
                let message = try await webSocketTask.receive()
                
                switch message {
                case .string(let text):
                    await handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                if isConnected {
                    await MainActor.run {
                        self.delegate?.didError(error)
                    }
                }
                break
            }
        }
    }
    
    private func handleMessage(_ text: String) async {
        guard let data = text.data(using: .utf8) else { 
            print("⚠️ WebSocket: Failed to convert message to data")
            return 
        }
        
        do {
            let decoder = JSONDecoder()
            let serverMessage = try decoder.decode(ServerMessage.self, from: data)
            
            print("📨 WebSocket: Received message type: \(serverMessage.type)")
            
            // Call delegate methods directly on MainActor
            await MainActor.run {
                switch serverMessage.data {
                case .tts(let tts):
                    if let audioData = tts.audioData {
                        print("📢 WebSocket: Received TTS audio (trial: \(tts.trialNumber ?? -1))")
                        self.delegate?.didReceiveTTS(audio: audioData, trialNumber: tts.trialNumber)
                    } else {
                        print("⚠️ WebSocket: TTS message has no audio data")
                    }
                case .taskState(let taskState):
                    let state = TaskState(rawValue: taskState.state) ?? .listening
                    print("📊 WebSocket: Task state: \(state.rawValue), trial: \(taskState.trialNumber ?? -1)")
                    self.delegate?.didReceiveTaskState(
                        state: state,
                        trialNumber: taskState.trialNumber,
                        message: taskState.message
                    )
                case .debug(let debug):
                    print("🐛 WebSocket: Debug: \(debug.message)")
                    self.delegate?.didReceiveDebug(message: debug.message)
                case .evaluationResult(let result):
                    print("📊 WebSocket: Received evaluation result for trial \(result.trialNumber)")
                    self.delegate?.didReceiveEvaluationResult(result)
                case .allResults(let results):
                    print("📊 WebSocket: Received all results (\(results.count) trials)")
                    self.delegate?.didReceiveAllResults(results)
                case .wordDisplay(let wordDisplay):
                    print("📺 WebSocket: Received word display: '\(wordDisplay.word)' (trial: \(wordDisplay.trialNumber), index: \(wordDisplay.wordIndex))")
                    self.delegate?.didReceiveWordDisplay(
                        word: wordDisplay.word,
                        trialNumber: wordDisplay.trialNumber,
                        wordIndex: wordDisplay.wordIndex
                    )
                case .stateTransition(let transition):
                    print("🔄 WebSocket: Received state transition: \(transition.phase) (trial: \(transition.trialNumber ?? -1))")
                    self.delegate?.didReceiveStateTransition(
                        phase: transition.phase,
                        trialNumber: transition.trialNumber,
                        message: transition.message
                    )
                }
            }
        } catch {
            print("❌ Error decoding message: \(error)")
            print("   Error details: \(error.localizedDescription)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .dataCorrupted(let context):
                    print("   Data corrupted: \(context.debugDescription)")
                case .keyNotFound(let key, let context):
                    print("   Key not found: \(key.stringValue), context: \(context.debugDescription)")
                case .typeMismatch(let type, let context):
                    print("   Type mismatch: \(type), context: \(context.debugDescription)")
                case .valueNotFound(let type, let context):
                    print("   Value not found: \(type), context: \(context.debugDescription)")
                @unknown default:
                    print("   Unknown decoding error")
                }
            }
            print("   Raw message: \(text.prefix(200))")
            await MainActor.run {
                self.delegate?.didError(error)
            }
        }
    }
}

