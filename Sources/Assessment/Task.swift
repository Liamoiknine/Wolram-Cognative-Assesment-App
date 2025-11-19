import Foundation

/// Expected input type for a task.
enum TaskInputType {
    case audio
    case text
    case none
}

/// Timing requirements for a task.
struct TimingRequirements {
    var maxDuration: TimeInterval?
    var minDuration: TimeInterval?
    var timeout: TimeInterval?
}

/// Instructions for a task, which can be text or an audio reference.
enum TaskInstructions {
    case text(String)
    case audioReference(String) // Path to audio file
}

/// Protocol defining a cognitive assessment task.
/// All task operations are asynchronous.
protocol Task {
    /// Unique identifier for the task.
    var id: UUID { get }
    
    /// Title of the task.
    var title: String { get }
    
    /// Instructions for the task (text or audio reference).
    var instructions: TaskInstructions { get }
    
    /// Expected type of input from the user.
    var expectedInputType: TaskInputType { get }
    
    /// Optional timing requirements.
    var timingRequirements: TimingRequirements? { get }
    
    /// Placeholder scoring metadata for future implementation.
    var scoringMetadata: [String: Any]? { get }
    
    /// Starts the task.
    func start() async throws
    
    /// Stops the task.
    func stop() async throws
    
    /// Captures a response for the task.
    func captureResponse(_ response: String) async throws
}

