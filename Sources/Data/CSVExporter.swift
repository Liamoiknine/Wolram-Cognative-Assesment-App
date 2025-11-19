import Foundation

/// Utility for exporting data to CSV format.
/// Works entirely from DataControllerProtocol abstractions.
class CSVExporter {
    private let dataController: DataControllerProtocol
    private let fileStorage: FileStorageProtocol
    
    init(dataController: DataControllerProtocol, fileStorage: FileStorageProtocol) {
        self.dataController = dataController
        self.fileStorage = fileStorage
    }
    
    /// Exports all data to CSV files in a folder structure.
    /// Returns the paths to all created CSV files and audio file references.
    func exportAll(to folderPath: String) async throws -> ExportResult {
        // Create export directory
        try await fileStorage.createDirectory(at: folderPath)
        
        // Export each entity type
        let patientsCSV = try await exportPatients(to: folderPath)
        let sessionsCSV = try await exportSessions(to: folderPath)
        let responsesCSV = try await exportItemResponses(to: folderPath)
        let audioClipsCSV = try await exportAudioClips(to: folderPath)
        
        // Collect audio file references
        let audioClips = try await dataController.fetchAllAudioClips()
        let audioFileReferences = audioClips.map { $0.filePath }
        
        return ExportResult(
            csvFiles: [patientsCSV, sessionsCSV, responsesCSV, audioClipsCSV],
            audioFileReferences: audioFileReferences
        )
    }
    
    private func exportPatients(to folderPath: String) async throws -> String {
        let patients = try await dataController.fetchAllPatients()
        let csvPath = "\(folderPath)/patients.csv"
        
        let header = "id,name,dateOfBirth,createdAt,updatedAt\n"
        let rows = patients.map { patient in
            let dateOfBirth = patient.dateOfBirth?.ISO8601Format() ?? ""
            let createdAt = patient.createdAt.ISO8601Format()
            let updatedAt = patient.updatedAt.ISO8601Format()
            return "\(patient.id.uuidString),\"\(patient.name)\",\(dateOfBirth),\(createdAt),\(updatedAt)"
        }
        
        let csvContent = header + rows.joined(separator: "\n")
        let data = csvContent.data(using: .utf8)!
        try await fileStorage.save(data: data, to: csvPath)
        
        return csvPath
    }
    
    private func exportSessions(to folderPath: String) async throws -> String {
        let sessions = try await dataController.fetchAllSessions()
        let csvPath = "\(folderPath)/sessions.csv"
        
        let header = "id,patientId,startTime,endTime,status,createdAt,updatedAt\n"
        let rows = sessions.map { session in
            let startTime = session.startTime.ISO8601Format()
            let endTime = session.endTime?.ISO8601Format() ?? ""
            let createdAt = session.createdAt.ISO8601Format()
            let updatedAt = session.updatedAt.ISO8601Format()
            return "\(session.id.uuidString),\(session.patientId.uuidString),\(startTime),\(endTime),\(session.status.rawValue),\(createdAt),\(updatedAt)"
        }
        
        let csvContent = header + rows.joined(separator: "\n")
        let data = csvContent.data(using: .utf8)!
        try await fileStorage.save(data: data, to: csvPath)
        
        return csvPath
    }
    
    private func exportItemResponses(to folderPath: String) async throws -> String {
        let responses = try await dataController.fetchAllItemResponses()
        let csvPath = "\(folderPath)/item_responses.csv"
        
        let header = "id,sessionId,taskId,responseText,timestamp,audioClipId,createdAt,updatedAt\n"
        let rows = responses.map { response in
            let responseText = response.responseText?.replacingOccurrences(of: "\"", with: "\"\"") ?? ""
            let timestamp = response.timestamp.ISO8601Format()
            let audioClipId = response.audioClipId?.uuidString ?? ""
            let createdAt = response.createdAt.ISO8601Format()
            let updatedAt = response.updatedAt.ISO8601Format()
            return "\(response.id.uuidString),\(response.sessionId.uuidString),\(response.taskId.uuidString),\"\(responseText)\",\(timestamp),\(audioClipId),\(createdAt),\(updatedAt)"
        }
        
        let csvContent = header + rows.joined(separator: "\n")
        let data = csvContent.data(using: .utf8)!
        try await fileStorage.save(data: data, to: csvPath)
        
        return csvPath
    }
    
    private func exportAudioClips(to folderPath: String) async throws -> String {
        let audioClips = try await dataController.fetchAllAudioClips()
        let csvPath = "\(folderPath)/audio_clips.csv"
        
        let header = "id,filePath,duration,createdAt,transcription,updatedAt\n"
        let rows = audioClips.map { clip in
            let transcription = clip.transcription?.replacingOccurrences(of: "\"", with: "\"\"") ?? ""
            let createdAt = clip.createdAt.ISO8601Format()
            let updatedAt = clip.updatedAt.ISO8601Format()
            return "\(clip.id.uuidString),\"\(clip.filePath)\",\(clip.duration),\(createdAt),\"\(transcription)\",\(updatedAt)"
        }
        
        let csvContent = header + rows.joined(separator: "\n")
        let data = csvContent.data(using: .utf8)!
        try await fileStorage.save(data: data, to: csvPath)
        
        return csvPath
    }
}

/// Result of an export operation.
struct ExportResult {
    let csvFiles: [String]
    let audioFileReferences: [String]
}

