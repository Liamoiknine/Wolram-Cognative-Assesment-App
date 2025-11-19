import Foundation
import SwiftUI

/// ViewModel for session history view.
/// Fetches and manages session data from DataController.
class SessionHistoryViewModel: ObservableObject {
    private let dataController: DataControllerProtocol
    
    @Published var sessions: [Session] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    init(dataController: DataControllerProtocol) {
        self.dataController = dataController
    }
    
    func loadSessions() async {
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        do {
            let loadedSessions = try await dataController.fetchAllSessions()
            await MainActor.run {
                self.sessions = loadedSessions.sorted { $0.startTime > $1.startTime }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load sessions: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
}

