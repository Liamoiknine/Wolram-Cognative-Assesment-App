import SwiftUI

/// View for starting a new assessment.
/// Launches the TaskRunner when ready.
struct StartAssessmentView: View {
    @StateObject private var viewModel: StartAssessmentViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(
        dataController: DataControllerProtocol? = nil,
        taskRunner: TaskRunnerProtocol? = nil
    ) {
        // In a real app, these would be injected via environment or dependency injection
        // For now, this is a placeholder that shows the structure
        let dataController = dataController ?? DataController()
        let fileStorage = FileStorage()
        let audioManager = AudioManager(fileStorage: fileStorage)
        let transcriptionManager = TranscriptionManager(fileStorage: fileStorage)
        let taskRunner = taskRunner ?? TaskRunner(
            dataController: dataController,
            audioManager: audioManager,
            transcriptionManager: transcriptionManager,
            fileStorage: fileStorage
        )
        
        _viewModel = StateObject(wrappedValue: StartAssessmentViewModel(
            dataController: dataController,
            taskRunner: taskRunner
        ))
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Start Assessment")
                .font(.title)
                .padding()
            
            if viewModel.patients.isEmpty {
                Text("No patients available")
                    .foregroundColor(.secondary)
            } else {
                Picker("Select Patient", selection: $viewModel.selectedPatient) {
                    Text("Select a patient").tag(Patient?.none)
                    ForEach(viewModel.patients) { patient in
                        Text(patient.name).tag(Patient?.some(patient))
                    }
                }
                .pickerStyle(.menu)
            }
            
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }
            
            Button("Start") {
                Task {
                    await viewModel.startAssessment()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isStartingAssessment || viewModel.selectedPatient == nil)
            
            if viewModel.isStartingAssessment {
                ProgressView()
            }
        }
        .padding()
        .task {
            await viewModel.loadPatients()
        }
    }
}

