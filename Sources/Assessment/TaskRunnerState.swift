import Foundation

/// State machine states for TaskRunner.
enum TaskRunnerState: Equatable {
    case idle
    case presenting
    case recording
    case evaluating
    case completed
}

