import Foundation
import Combine

/// Protocol for task runner operations.
/// Manages task lifecycle and state transitions.
protocol TaskRunnerProtocol {
    /// Current state of the task runner.
    var state: TaskRunnerState { get }
    
    /// Current task being executed.
    var currentTask: (any Task)? { get }
    
    /// Starts running a task.
    func startTask(_ task: any Task, sessionId: UUID) async throws
    
    /// Stops the current task.
    func stopTask() async throws
    
    /// Captures a response for the current task.
    func captureResponse(_ response: String) async throws
    
    /// Moves to the next state in the state machine.
    func transition(to newState: TaskRunnerState) async
}

