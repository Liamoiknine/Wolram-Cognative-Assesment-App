import Foundation
import SwiftUI
import Combine

/// ViewModel for the task view.
/// Observes TaskRunner state and drives UI updates.
class TaskViewModel: ObservableObject {
    private let taskRunner: TaskRunnerProtocol
    private var cancellables = Set<AnyCancellable>()
    
    @Published var currentState: TaskRunnerState = .idle
    @Published var currentTaskTitle: String = ""
    @Published var errorMessage: String?
    
    init(taskRunner: TaskRunnerProtocol) {
        self.taskRunner = taskRunner
        
        // Observe task runner state changes
        if let observableRunner = taskRunner as? TaskRunner {
            observableRunner.$state
                .receive(on: DispatchQueue.main)
                .assign(to: \.currentState, on: self)
                .store(in: &cancellables)
            
            observableRunner.$currentTask
                .receive(on: DispatchQueue.main)
                .map { $0?.title ?? "" }
                .assign(to: \.currentTaskTitle, on: self)
                .store(in: &cancellables)
        }
    }
    
    func captureTextResponse(_ text: String) async {
        do {
            try await taskRunner.captureResponse(text)
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to capture response: \(error.localizedDescription)"
            }
        }
    }
    
    func stopTask() async {
        do {
            try await taskRunner.stopTask()
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to stop task: \(error.localizedDescription)"
            }
        }
    }
}

