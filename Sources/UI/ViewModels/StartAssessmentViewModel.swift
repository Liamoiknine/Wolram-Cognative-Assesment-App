import Foundation
import SwiftUI

/// ViewModel for starting an assessment.
/// Handles assessment initialization and patient selection.
class StartAssessmentViewModel: ObservableObject {
    private let dataController: DataControllerProtocol
    private let taskRunner: TaskRunnerProtocol
    private var audioManager: AudioManagerProtocol
    
    @Published var patients: [Patient] = []
    @Published var selectedPatient: Patient?
    @Published var isStartingAssessment = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var createdSessionId: UUID?
    @Published var shouldNavigateToTask = false
    @Published var shouldNavigateToWorkingMemory = false
    @Published var shouldNavigateToAttention = false
    @Published var shouldNavigateToLanguage = false
    @Published var shouldNavigateToAbstraction = false
    @Published var currentTestType: TestType?
    
    init(dataController: DataControllerProtocol, taskRunner: TaskRunnerProtocol, audioManager: AudioManagerProtocol) {
        self.dataController = dataController
        self.taskRunner = taskRunner
        self.audioManager = audioManager
    }
    
    func updateAudioManager(_ audioManager: AudioManagerProtocol) {
        self.audioManager = audioManager
    }
    
    func loadPatients() async {
        do {
            let loadedPatients = try await dataController.fetchAllPatients()
            await MainActor.run {
                self.patients = loadedPatients
                // Auto-select "test" patient
                if let testPatient = loadedPatients.first(where: { $0.name.lowercased() == "test" }) {
                    self.selectedPatient = testPatient
                    print("✅ StartAssessmentViewModel: Auto-selected patient: \(testPatient.name)")
                } else if let firstPatient = loadedPatients.first {
                    // Fallback to first patient if "test" not found
                    self.selectedPatient = firstPatient
                    print("⚠️ StartAssessmentViewModel: 'test' patient not found, using first patient: \(firstPatient.name)")
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load patients: \(error.localizedDescription)"
            }
        }
    }
    
    /// Starts a specific assessment test
    /// Checks for completed sessions first - if found, navigates to results
    /// Otherwise starts a new task
    func startTest(_ testType: TestType) async {
        guard let patient = selectedPatient else {
            await MainActor.run {
                self.errorMessage = "Patient not available"
            }
            return
        }
        
        // CRITICAL: Reset TaskRunner state first to ensure complete isolation
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            await taskRunnerInstance.reset()
            print("✅ StartAssessmentViewModel: TaskRunner reset before checking for completed sessions")
        }
        
        // Check for completed sessions for this patient
        do {
            let allSessions = try await dataController.fetchSessions(for: patient.id)
            let completedSessions = allSessions
                .filter { $0.status == .completed }
                .sorted { $0.endTime ?? $0.startTime > $1.endTime ?? $1.startTime }
            
            // Check if there's a completed session with results for this test type
            for session in completedSessions {
                let sessionResponses = try await dataController.fetchItemResponses(for: session.id)
                
                if !sessionResponses.isEmpty {
                    // Get unique task IDs from responses
                    let uniqueTaskIds = Set(sessionResponses.map { $0.taskId })
                    
                    // For each unique task, check if it matches the test type
                    // We'll infer task type from response count:
                    // Working Memory: exactly 2 responses (2 trials)
                    // Attention: 4+ responses (multiple phases)
                    // Language: exactly 3 responses (2 sentences + 1 fluency)
                    // Abstraction: exactly 2 responses (2 trials)
                    for taskId in uniqueTaskIds {
                        let taskResponses = sessionResponses.filter { $0.taskId == taskId }
                        let responseCount = taskResponses.count
                        
                        // More strict matching: only match if response count matches expected pattern AND test type matches
                        let isWorkingMemory = responseCount == 2 && testType == .workingMemory
                        let isAttention = responseCount >= 4 && testType == .attention
                        let isLanguage = responseCount == 3 && testType == .language
                        let isAbstraction = responseCount == 2 && testType == .abstraction
                        
                        // Only proceed if we have a clear match for the requested test type
                        if (isWorkingMemory && testType == .workingMemory) || (isAttention && testType == .attention) || (isLanguage && testType == .language) || (isAbstraction && testType == .abstraction) {
                            // Found a completed session for this test type
                            let taskTitle: String
                            switch testType {
                            case .workingMemory:
                                taskTitle = "Working Memory Task"
                            case .attention:
                                taskTitle = "Attention Task"
                            case .language:
                                taskTitle = "Language Task"
                            case .abstraction:
                                taskTitle = "Abstraction Task"
                            }
                            
                            // Create a placeholder task for viewing results
                            let placeholderTask = PlaceholderTask(id: taskId, title: taskTitle)
                            
                            // Load the completed task in TaskRunner (this will set state to completed)
                            if let taskRunnerInstance = taskRunner as? TaskRunner {
                                await taskRunnerInstance.loadCompletedTask(placeholderTask, sessionId: session.id)
                                
                                await MainActor.run {
                                    self.createdSessionId = session.id
                                    self.currentTestType = testType
                                    // Navigate to the appropriate view based on test type
                                    if testType == .workingMemory {
                                        self.shouldNavigateToWorkingMemory = true
                                    } else if testType == .attention {
                                        self.shouldNavigateToAttention = true
                                    } else if testType == .language {
                                        self.shouldNavigateToLanguage = true
                                    } else if testType == .abstraction {
                                        self.shouldNavigateToAbstraction = true
                                    }
                                    print("✅ StartAssessmentViewModel: Found completed session \(session.id) for \(taskTitle), navigating to results")
                                }
                                return
                            }
                        }
                    }
                }
            }
        } catch {
            print("⚠️ StartAssessmentViewModel: Error checking for completed sessions: \(error)")
            // Continue to start new task if check fails
        }
        
        // No completed session found, start a new task
        await startAssessment(for: patient, testType: testType)
    }
    
    /// Starts the working memory assessment
    func startAssessment() async {
        guard let patient = selectedPatient else {
            await MainActor.run {
                self.errorMessage = "Patient not available"
            }
            return
        }
        
        await startAssessment(for: patient, testType: .workingMemory)
    }
    
    private func startAssessment(for patient: Patient, testType: TestType) async {
        
        await MainActor.run {
            self.isStartingAssessment = true
            self.errorMessage = nil
        }
        
        do {
            // CRITICAL: Reset TaskRunner state first to ensure complete isolation from previous tasks
            if let taskRunnerInstance = taskRunner as? TaskRunner {
                await taskRunnerInstance.reset()
                print("✅ StartAssessmentViewModel: TaskRunner reset before starting new task")
            }
            
            // Create a new session
            let session = Session(patientId: patient.id)
            let savedSession = try await dataController.createSession(session)
            
            // Create and start the appropriate task based on test type
            switch testType {
            case .workingMemory:
                // Create and start WorkingMemoryTask
                // CRITICAL: Use TaskRunner's DataController to ensure we use the same instance
                // that actually saves the ItemResponses
                let workingMemoryTask = WorkingMemoryTask(
                    audioManager: audioManager,
                    taskRunner: taskRunner,
                    dataController: taskRunner.dataController
                )
                
                // Verify we're using the same DataController
                // Cast to AnyObject for identity comparison (since DataController is a class)
                if (dataController as AnyObject) !== (taskRunner.dataController as AnyObject) {
                    print("⚠️ StartAssessmentViewModel: WARNING - Environment DataController differs from TaskRunner's DataController!")
                    print("   WorkingMemoryTask will use TaskRunner's DataController to ensure data consistency.")
                } else {
                    print("✅ StartAssessmentViewModel: Using same DataController instance as TaskRunner")
                }
                
                // Start the task (don't await - let it run in background)
                // Navigate immediately so user sees the task UI
                _Concurrency.Task {
                    do {
                        try await taskRunner.startTask(workingMemoryTask, sessionId: savedSession.id)
                        print("✅ Task completed successfully")
                    } catch {
                        print("❌ Task failed: \(error)")
                        await MainActor.run {
                            self.errorMessage = "Task failed: \(error.localizedDescription)"
                        }
                    }
                }
                
                // Navigate immediately after starting the task
                await MainActor.run {
                    self.isStartingAssessment = false
                    self.createdSessionId = savedSession.id
                    self.currentTestType = .workingMemory
                    self.shouldNavigateToWorkingMemory = true
                    print("✅ Created session: \(savedSession.id) and started WorkingMemoryTask - navigating to task view")
                }
                
            case .attention:
                // Create and start AttentionTask
                let attentionTask = AttentionTask(
                    audioManager: audioManager,
                    taskRunner: taskRunner,
                    dataController: taskRunner.dataController
                )
                
                // Verify we're using the same DataController
                if (dataController as AnyObject) !== (taskRunner.dataController as AnyObject) {
                    print("⚠️ StartAssessmentViewModel: WARNING - Environment DataController differs from TaskRunner's DataController!")
                    print("   AttentionTask will use TaskRunner's DataController to ensure data consistency.")
                } else {
                    print("✅ StartAssessmentViewModel: Using same DataController instance as TaskRunner")
                }
                
                // Start the task (don't await - let it run in background)
                // Navigate immediately so user sees the task UI
                _Concurrency.Task {
                    do {
                        try await taskRunner.startTask(attentionTask, sessionId: savedSession.id)
                        print("✅ Attention task completed successfully")
                    } catch {
                        print("❌ Attention task failed: \(error)")
                        await MainActor.run {
                            self.errorMessage = "Task failed: \(error.localizedDescription)"
                        }
                    }
                }
                
                // Navigate immediately after starting the task
                await MainActor.run {
                    self.isStartingAssessment = false
                    self.createdSessionId = savedSession.id
                    self.currentTestType = .attention
                    self.shouldNavigateToAttention = true
                    print("✅ Created session: \(savedSession.id) and started AttentionTask - navigating to task view")
                }
                
            case .language:
                // Create and start LanguageTask
                let languageTask = LanguageTask(
                    audioManager: audioManager,
                    taskRunner: taskRunner,
                    dataController: taskRunner.dataController
                )
                
                // Verify we're using the same DataController
                if (dataController as AnyObject) !== (taskRunner.dataController as AnyObject) {
                    print("⚠️ StartAssessmentViewModel: WARNING - Environment DataController differs from TaskRunner's DataController!")
                    print("   LanguageTask will use TaskRunner's DataController to ensure data consistency.")
                } else {
                    print("✅ StartAssessmentViewModel: Using same DataController instance as TaskRunner")
                }
                
                // Start the task (don't await - let it run in background)
                // Navigate immediately so user sees the task UI
                _Concurrency.Task {
                    do {
                        try await taskRunner.startTask(languageTask, sessionId: savedSession.id)
                        print("✅ Language task completed successfully")
                    } catch {
                        print("❌ Language task failed: \(error)")
                        await MainActor.run {
                            self.errorMessage = "Task failed: \(error.localizedDescription)"
                        }
                    }
                }
                
                // Navigate immediately after starting the task
                await MainActor.run {
                    self.isStartingAssessment = false
                    self.createdSessionId = savedSession.id
                    self.currentTestType = .language
                    self.shouldNavigateToLanguage = true
                    print("✅ Created session: \(savedSession.id) and started LanguageTask - navigating to task view")
                }
                
            case .abstraction:
                // Create and start AbstractionTask
                let abstractionTask = AbstractionTask(
                    audioManager: audioManager,
                    taskRunner: taskRunner,
                    dataController: taskRunner.dataController
                )
                
                // Verify we're using the same DataController
                if (dataController as AnyObject) !== (taskRunner.dataController as AnyObject) {
                    print("⚠️ StartAssessmentViewModel: WARNING - Environment DataController differs from TaskRunner's DataController!")
                    print("   AbstractionTask will use TaskRunner's DataController to ensure data consistency.")
                } else {
                    print("✅ StartAssessmentViewModel: Using same DataController instance as TaskRunner")
                }
                
                // Start the task (don't await - let it run in background)
                // Navigate immediately so user sees the task UI
                _Concurrency.Task {
                    do {
                        try await taskRunner.startTask(abstractionTask, sessionId: savedSession.id)
                        print("✅ Abstraction task completed successfully")
                    } catch {
                        print("❌ Abstraction task failed: \(error)")
                        await MainActor.run {
                            self.errorMessage = "Task failed: \(error.localizedDescription)"
                        }
                    }
                }
                
                // Navigate immediately after starting the task
                await MainActor.run {
                    self.isStartingAssessment = false
                    self.createdSessionId = savedSession.id
                    self.currentTestType = .abstraction
                    self.shouldNavigateToAbstraction = true
                    print("✅ Created session: \(savedSession.id) and started AbstractionTask - navigating to task view")
                }
            }
        } catch {
            await MainActor.run {
                self.isStartingAssessment = false
                self.errorMessage = "Failed to start assessment: \(error.localizedDescription)"
                print("❌ Failed to create session or start task: \(error)")
            }
        }
    }
}

/// Enum representing different test types available in the assessment
enum TestType: String, Identifiable {
    case workingMemory = "working_memory"
    case attention = "attention"
    case language = "language"
    case abstraction = "abstraction"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .workingMemory:
            return "Working Memory"
        case .attention:
            return "Attention Task"
        case .language:
            return "Language Task"
        case .abstraction:
            return "Abstraction Task"
        }
    }
    
    var description: String {
        switch self {
        case .workingMemory:
            return "Test your ability to remember and recall words in sequence"
        case .attention:
            return "Test attention and focus through multiple assessments"
        case .language:
            return "Test language through sentence repetition and word fluency"
        case .abstraction:
            return "Test your ability to identify categories that unite two words"
        }
    }
    
    var icon: String {
        switch self {
        case .workingMemory:
            return "brain.head.profile"
        case .attention:
            return "eye.fill"
        case .language:
            return "text.bubble.fill"
        case .abstraction:
            return "lightbulb.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .workingMemory:
            return .blue
        case .attention:
            return .purple
        case .language:
            return .orange
        case .abstraction:
            return .green
        }
    }
}

/// Placeholder task for viewing completed session results
/// This allows TaskRunner to load completed tasks without actually running them
private class PlaceholderTask: Task {
    let id: UUID
    let title: String
    let instructions: TaskInstructions = .text("Viewing completed session results")
    let expectedInputType: TaskInputType = .none
    let timingRequirements: TimingRequirements? = nil
    let scoringMetadata: [String: Any]? = nil
    
    init(id: UUID, title: String) {
        self.id = id
        self.title = title
        print("📋 PlaceholderTask: Created with id=\(id), title='\(title)'")
    }
    
    func start() async throws {
        // No-op for placeholder - should never be called
        print("⚠️ PlaceholderTask: start() called - this should not happen!")
    }
    
    func stop() async throws {
        // No-op for placeholder - should never be called
        print("⚠️ PlaceholderTask: stop() called - this should not happen!")
    }
    
    func captureResponse(_ response: String) async throws {
        // No-op for placeholder - should never be called
        print("⚠️ PlaceholderTask: captureResponse() called - this should not happen!")
    }
}

