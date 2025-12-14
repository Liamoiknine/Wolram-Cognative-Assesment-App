import Foundation
import Combine

/// In-memory implementation of DataControllerProtocol.
/// Mimics Core Data patterns with stable UUID-based object identity.
/// Prepared for future Core Data migration.
class DataController: DataControllerProtocol, ObservableObject, @unchecked Sendable {
    // In-memory storage
    private var patients: [UUID: Patient] = [:]
    private var sessions: [UUID: Session] = [:]
    private var itemResponses: [UUID: ItemResponse] = [:]
    private var audioClips: [UUID: AudioClip] = [:]
    
    // Thread-safe access
    private let queue = DispatchQueue(label: "com.cognitiveassessment.datacontroller", attributes: .concurrent)
    
    // MARK: - Patient Operations
    
    func createPatient(_ patient: Patient) async throws -> Patient {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Patient, Error>) in
            queue.async(flags: .barrier) {
                var updatedPatient = patient
                updatedPatient = Patient(
                    id: patient.id,
                    name: patient.name,
                    dateOfBirth: patient.dateOfBirth,
                    createdAt: patient.createdAt,
                    updatedAt: Date()
                )
                self.patients[patient.id] = updatedPatient
                continuation.resume(returning: updatedPatient)
            }
        }
    }
    
    func fetchPatient(id: UUID) async throws -> Patient? {
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.patients[id])
            }
        }
    }
    
    func fetchAllPatients() async throws -> [Patient] {
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Array(self.patients.values))
            }
        }
    }
    
    func updatePatient(_ patient: Patient) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async(flags: .barrier) {
                guard self.patients[patient.id] != nil else {
                    continuation.resume(throwing: DataControllerError.notFound)
                    return
                }
                var updatedPatient = patient
                updatedPatient = Patient(
                    id: patient.id,
                    name: patient.name,
                    dateOfBirth: patient.dateOfBirth,
                    createdAt: patient.createdAt,
                    updatedAt: Date()
                )
                self.patients[patient.id] = updatedPatient
                continuation.resume()
            }
        }
    }
    
    func deletePatient(id: UUID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async(flags: .barrier) {
                guard self.patients[id] != nil else {
                    continuation.resume(throwing: DataControllerError.notFound)
                    return
                }
                self.patients.removeValue(forKey: id)
                continuation.resume()
            }
        }
    }
    
    // MARK: - Session Operations
    
    func createSession(_ session: Session) async throws -> Session {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Session, Error>) in
            queue.async(flags: .barrier) {
                var updatedSession = session
                updatedSession = Session(
                    id: session.id,
                    patientId: session.patientId,
                    startTime: session.startTime,
                    endTime: session.endTime,
                    status: session.status,
                    createdAt: session.createdAt,
                    updatedAt: Date()
                )
                self.sessions[session.id] = updatedSession
                continuation.resume(returning: updatedSession)
            }
        }
    }
    
    func fetchSession(id: UUID) async throws -> Session? {
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.sessions[id])
            }
        }
    }
    
    func fetchSessions(for patientId: UUID) async throws -> [Session] {
        return await withCheckedContinuation { continuation in
            queue.async {
                let patientSessions = self.sessions.values.filter { $0.patientId == patientId }
                continuation.resume(returning: Array(patientSessions))
            }
        }
    }
    
    func fetchAllSessions() async throws -> [Session] {
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Array(self.sessions.values))
            }
        }
    }
    
    func updateSession(_ session: Session) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async(flags: .barrier) {
                guard self.sessions[session.id] != nil else {
                    continuation.resume(throwing: DataControllerError.notFound)
                    return
                }
                var updatedSession = session
                updatedSession = Session(
                    id: session.id,
                    patientId: session.patientId,
                    startTime: session.startTime,
                    endTime: session.endTime,
                    status: session.status,
                    createdAt: session.createdAt,
                    updatedAt: Date()
                )
                self.sessions[session.id] = updatedSession
                continuation.resume()
            }
        }
    }
    
    func deleteSession(id: UUID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async(flags: .barrier) {
                guard self.sessions[id] != nil else {
                    continuation.resume(throwing: DataControllerError.notFound)
                    return
                }
                self.sessions.removeValue(forKey: id)
                continuation.resume()
            }
        }
    }
    
    // MARK: - ItemResponse Operations
    
    func createItemResponse(_ response: ItemResponse) async throws -> ItemResponse {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ItemResponse, Error>) in
            queue.async(flags: .barrier) {
                var updatedResponse = response
                updatedResponse = ItemResponse(
                    id: response.id,
                    sessionId: response.sessionId,
                    taskId: response.taskId,
                    responseText: response.responseText,
                    timestamp: response.timestamp,
                    audioClipId: response.audioClipId,
                    createdAt: response.createdAt,
                    updatedAt: Date(),
                    score: response.score,
                    correctWords: response.correctWords,
                    expectedWords: response.expectedWords
                )
                self.itemResponses[response.id] = updatedResponse
                continuation.resume(returning: updatedResponse)
            }
        }
    }
    
    func fetchItemResponse(id: UUID) async throws -> ItemResponse? {
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.itemResponses[id])
            }
        }
    }
    
    func fetchItemResponses(for sessionId: UUID) async throws -> [ItemResponse] {
        return await withCheckedContinuation { continuation in
            queue.async {
                let sessionResponses = self.itemResponses.values.filter { $0.sessionId == sessionId }
                continuation.resume(returning: Array(sessionResponses))
            }
        }
    }
    
    func fetchAllItemResponses() async throws -> [ItemResponse] {
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Array(self.itemResponses.values))
            }
        }
    }
    
    func updateItemResponse(_ response: ItemResponse) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async(flags: .barrier) {
                guard self.itemResponses[response.id] != nil else {
                    continuation.resume(throwing: DataControllerError.notFound)
                    return
                }
                var updatedResponse = response
                updatedResponse = ItemResponse(
                    id: response.id,
                    sessionId: response.sessionId,
                    taskId: response.taskId,
                    responseText: response.responseText,
                    timestamp: response.timestamp,
                    audioClipId: response.audioClipId,
                    createdAt: response.createdAt,
                    updatedAt: Date(),
                    score: response.score,
                    correctWords: response.correctWords,
                    expectedWords: response.expectedWords
                )
                self.itemResponses[response.id] = updatedResponse
                continuation.resume()
            }
        }
    }
    
    func deleteItemResponse(id: UUID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async(flags: .barrier) {
                guard self.itemResponses[id] != nil else {
                    continuation.resume(throwing: DataControllerError.notFound)
                    return
                }
                self.itemResponses.removeValue(forKey: id)
                continuation.resume()
            }
        }
    }
    
    // MARK: - AudioClip Operations
    
    func createAudioClip(_ clip: AudioClip) async throws -> AudioClip {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AudioClip, Error>) in
            queue.async(flags: .barrier) {
                var updatedClip = clip
                updatedClip = AudioClip(
                    id: clip.id,
                    filePath: clip.filePath,
                    duration: clip.duration,
                    createdAt: clip.createdAt,
                    transcription: clip.transcription,
                    updatedAt: Date()
                )
                self.audioClips[clip.id] = updatedClip
                continuation.resume(returning: updatedClip)
            }
        }
    }
    
    func fetchAudioClip(id: UUID) async throws -> AudioClip? {
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.audioClips[id])
            }
        }
    }
    
    func fetchAllAudioClips() async throws -> [AudioClip] {
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Array(self.audioClips.values))
            }
        }
    }
    
    func updateAudioClip(_ clip: AudioClip) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async(flags: .barrier) {
                guard self.audioClips[clip.id] != nil else {
                    continuation.resume(throwing: DataControllerError.notFound)
                    return
                }
                var updatedClip = clip
                updatedClip = AudioClip(
                    id: clip.id,
                    filePath: clip.filePath,
                    duration: clip.duration,
                    createdAt: clip.createdAt,
                    transcription: clip.transcription,
                    updatedAt: Date()
                )
                self.audioClips[clip.id] = updatedClip
                continuation.resume()
            }
        }
    }
    
    func deleteAudioClip(id: UUID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async(flags: .barrier) {
                guard self.audioClips[id] != nil else {
                    continuation.resume(throwing: DataControllerError.notFound)
                    return
                }
                self.audioClips.removeValue(forKey: id)
                continuation.resume()
            }
        }
    }
}

enum DataControllerError: LocalizedError {
    case notFound
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Entity not found"
        }
    }
}

