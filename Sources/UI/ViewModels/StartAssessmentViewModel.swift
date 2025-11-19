import Foundation
import SwiftUI

/// ViewModel for starting an assessment.
/// Handles assessment initialization and patient selection.
class StartAssessmentViewModel: ObservableObject {
    private let dataController: DataControllerProtocol
    private let taskRunner: TaskRunnerProtocol
    
    @Published var patients: [Patient] = []
    @Published var selectedPatient: Patient?
    @Published var isStartingAssessment = false
    @Published var errorMessage: String?
    
    init(dataController: DataControllerProtocol, taskRunner: TaskRunnerProtocol) {
        self.dataController = dataController
        self.taskRunner = taskRunner
    }
    
    func loadPatients() async {
        do {
            let loadedPatients = try await dataController.fetchAllPatients()
            await MainActor.run {
                self.patients = loadedPatients
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load patients: \(error.localizedDescription)"
            }
        }
    }
    
    func startAssessment() async {
        guard let patient = selectedPatient else {
            await MainActor.run {
                self.errorMessage = "Please select a patient"
            }
            return
        }
        
        await MainActor.run {
            self.isStartingAssessment = true
            self.errorMessage = nil
        }
        
        do {
            // Create a new session
            let session = Session(patientId: patient.id)
            let savedSession = try await dataController.createSession(session)
            
            // Note: TaskRunner will be started from the view when a task is available
            // For now, this is a placeholder that would be called when a task is selected
            
            await MainActor.run {
                self.isStartingAssessment = false
            }
        } catch {
            await MainActor.run {
                self.isStartingAssessment = false
                self.errorMessage = "Failed to start assessment: \(error.localizedDescription)"
            }
        }
    }
}

