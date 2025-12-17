import Foundation

struct BackendConfig {
    static let wsBaseURL = "ws://localhost:8000"
    static let httpBaseURL = "http://localhost:8000"
    static let abstractionEndpoint = "/ws/abstraction-session"
    static let uploadEndpoint = "/abstraction/upload_audio"
    
    static var abstractionURL: String {
        return "\(wsBaseURL)\(abstractionEndpoint)"
    }
    
    static var uploadURL: String {
        return "\(httpBaseURL)\(uploadEndpoint)"
    }
    
    static let workingMemoryEndpoint = "/ws/working-memory-session"
    static let workingMemoryUploadEndpoint = "/working_memory/upload_audio"
    
    static var workingMemoryURL: String {
        return "\(wsBaseURL)\(workingMemoryEndpoint)"
    }
    
    static var workingMemoryUploadURL: String {
        return "\(httpBaseURL)\(workingMemoryUploadEndpoint)"
    }
    
    /// Upload audio file to backend
    static func uploadAudio(_ audioData: Data, trialNumber: Int, sessionId: String) async throws {
        let url = URL(string: uploadURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Create multipart/form-data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add trial_number
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"trial_number\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(trialNumber)".data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add session_id
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"session_id\"\r\n\r\n".data(using: .utf8)!)
        body.append(sessionId.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "BackendConfig", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "BackendConfig", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Upload failed with status \(httpResponse.statusCode)"])
        }
    }
}

