import Foundation

/// Protocol defining Core Data-like API for data operations.
/// Provides context-like operations with stable UUID-based object identity.
protocol DataControllerProtocol {
    // MARK: - Patient Operations
    
    func createPatient(_ patient: Patient) async throws -> Patient
    func fetchPatient(id: UUID) async throws -> Patient?
    func fetchAllPatients() async throws -> [Patient]
    func updatePatient(_ patient: Patient) async throws
    func deletePatient(id: UUID) async throws
    
    // MARK: - Session Operations
    
    func createSession(_ session: Session) async throws -> Session
    func fetchSession(id: UUID) async throws -> Session?
    func fetchSessions(for patientId: UUID) async throws -> [Session]
    func fetchAllSessions() async throws -> [Session]
    func updateSession(_ session: Session) async throws
    func deleteSession(id: UUID) async throws
    
    // MARK: - ItemResponse Operations
    
    func createItemResponse(_ response: ItemResponse) async throws -> ItemResponse
    func fetchItemResponse(id: UUID) async throws -> ItemResponse?
    func fetchItemResponses(for sessionId: UUID) async throws -> [ItemResponse]
    func fetchAllItemResponses() async throws -> [ItemResponse]
    func updateItemResponse(_ response: ItemResponse) async throws
    func deleteItemResponse(id: UUID) async throws
    
    // MARK: - AudioClip Operations
    
    func createAudioClip(_ clip: AudioClip) async throws -> AudioClip
    func fetchAudioClip(id: UUID) async throws -> AudioClip?
    func fetchAllAudioClips() async throws -> [AudioClip]
    func updateAudioClip(_ clip: AudioClip) async throws
    func deleteAudioClip(id: UUID) async throws
}

