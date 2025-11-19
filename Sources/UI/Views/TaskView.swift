import SwiftUI

/// Generic container for task presentation.
/// Reacts to TaskRunner state changes.
struct TaskView: View {
    @StateObject private var viewModel: TaskViewModel
    @State private var responseText: String = ""
    
    init(taskRunner: TaskRunnerProtocol? = nil) {
        // In a real app, this would be injected via environment
        // For now, this is a placeholder that shows the structure
        let dataController = DataController()
        let fileStorage = FileStorage()
        let audioManager = AudioManager(fileStorage: fileStorage)
        let transcriptionManager = TranscriptionManager(fileStorage: fileStorage)
        let taskRunner = taskRunner ?? TaskRunner(
            dataController: dataController,
            audioManager: audioManager,
            transcriptionManager: transcriptionManager,
            fileStorage: fileStorage
        )
        
        _viewModel = StateObject(wrappedValue: TaskViewModel(taskRunner: taskRunner))
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Task: \(viewModel.currentTaskTitle)")
                .font(.title)
                .padding()
            
            // Display current state
            Text("State: \(viewModel.currentState.description)")
                .foregroundColor(.secondary)
            
            // State-specific UI
            switch viewModel.currentState {
            case .idle:
                Text("No active task")
                    .foregroundColor(.secondary)
            case .presenting:
                Text("Presenting task instructions...")
                    .foregroundColor(.secondary)
            case .recording:
                Text("Recording...")
                    .foregroundColor(.red)
            case .evaluating:
                Text("Evaluating response...")
                    .foregroundColor(.blue)
            case .completed:
                Text("Task completed")
                    .foregroundColor(.green)
            }
            
            // Text response input (for text-based tasks)
            if viewModel.currentState == .presenting || viewModel.currentState == .recording {
                TextField("Enter response", text: $responseText)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                
                Button("Submit Response") {
                    Task {
                        await viewModel.captureTextResponse(responseText)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }
            
            Button("Stop Task") {
                Task {
                    await viewModel.stopTask()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

extension TaskRunnerState {
    var description: String {
        switch self {
        case .idle: return "Idle"
        case .presenting: return "Presenting"
        case .recording: return "Recording"
        case .evaluating: return "Evaluating"
        case .completed: return "Completed"
        }
    }
}

