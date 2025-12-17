import Foundation
import SwiftUI
import Combine

/// ViewModel for the task view.
/// Observes TaskRunner state and drives UI updates.
class TaskViewModel: ObservableObject {
    private let taskRunner: TaskRunnerProtocol
    private let dataController: DataControllerProtocol
    private var cancellables = Set<AnyCancellable>()
    
    @Published var currentState: TaskRunnerState = .idle
    @Published var currentTaskTitle: String = ""
    @Published var errorMessage: String?
    @Published var workingMemoryResults: [ItemResponse] = []
    @Published var attentionResults: [ItemResponse] = []
    @Published var languageResults: [ItemResponse] = []
    @Published var abstractionResults: [ItemResponse] = []
    @Published var delayedRecallResults: [ItemResponse] = []
    @Published var orientationResults: [ItemResponse] = []
    @Published var currentWord: String? = nil // Current word being displayed (for WorkingMemoryTask)
    @Published var transcript: [TranscriptItem] = [] // Transcript of what's being said (for WorkingMemoryTask)
    
    init(taskRunner: TaskRunnerProtocol, dataController: DataControllerProtocol? = nil) {
        self.taskRunner = taskRunner
        // CRITICAL: Use TaskRunner's DataController to ensure we access the same data
        // This is the DataController that actually saves the ItemResponses
        self.dataController = taskRunner.dataController
        
        if let providedController = dataController {
            // Verify we're using the same instance as TaskRunner
            // Cast to AnyObject for identity comparison (since DataController is a class)
            if (providedController as AnyObject) !== (taskRunner.dataController as AnyObject) {
                print("⚠️ TaskViewModel: WARNING - Provided DataController is different from TaskRunner's DataController!")
                print("   Using TaskRunner's DataController instead to ensure data access.")
            } else {
                print("✅ TaskViewModel: Using same DataController instance as TaskRunner")
            }
        } else {
            print("✅ TaskViewModel: Using TaskRunner's DataController instance (no DataController provided)")
        }
        
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
            
            // Observe current word for WorkingMemoryTask
            observableRunner.$currentWord
                .receive(on: DispatchQueue.main)
                .sink { [weak self] word in
                    print("📺 TaskViewModel: currentWord changed to: '\(word ?? "nil")'")
                    self?.currentWord = word
                }
                .store(in: &cancellables)
            
            // Observe transcript for WorkingMemoryTask
            observableRunner.$transcript
                .receive(on: DispatchQueue.main)
                .assign(to: \.transcript, on: self)
                .store(in: &cancellables)
            
            // When task completes, fetch results for WorkingMemoryTask or AttentionTask
            observableRunner.$state
                .sink { [weak self] state in
                    print("🔄 TaskViewModel: State changed to: \(state)")
                    if state == .completed {
                        print("✅ TaskViewModel: Task completed, loading results...")
                        // Add a small delay to ensure data is saved
                        _Concurrency.Task {
                            try? await _Concurrency.Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                            if self?.isWorkingMemoryTask == true {
                                await self?.loadWorkingMemoryResults()
                            } else if self?.isAttentionTask == true {
                                await self?.loadAttentionResults()
                            } else if self?.isLanguageTask == true {
                                await self?.loadLanguageResults()
                            } else if self?.isAbstractionTask == true {
                                await self?.loadAbstractionResults()
                            } else if self?.isDelayedRecallTask == true {
                                await self?.loadDelayedRecallResults()
                            } else if self?.isOrientationTask == true {
                                await self?.loadOrientationResults()
                            }
                        }
                    }
                }
                .store(in: &cancellables)
        }
    }
    
    var isWorkingMemoryTask: Bool {
        // Check both title and actual task instance type for reliability
        if let task = taskRunner.currentTask {
            return task is WorkingMemoryTask || currentTaskTitle == "Working Memory Task"
        }
        return currentTaskTitle == "Working Memory Task"
    }
    
    var isAttentionTask: Bool {
        // Check both title and actual task instance type for reliability
        if let task = taskRunner.currentTask {
            return task is AttentionTask || currentTaskTitle == "Attention Task"
        }
        return currentTaskTitle == "Attention Task"
    }
    
    var isLanguageTask: Bool {
        // Check both title and actual task instance type for reliability
        if let task = taskRunner.currentTask {
            return task is LanguageTask || currentTaskTitle == "Language Task"
        }
        return currentTaskTitle == "Language Task"
    }
    
    var isAbstractionTask: Bool {
        // Check both title and actual task instance type for reliability
        if let task = taskRunner.currentTask {
            return task is AbstractionTask || currentTaskTitle == "Abstraction Task"
        }
        return currentTaskTitle == "Abstraction Task"
    }
    
    var isDelayedRecallTask: Bool {
        // Check both title and actual task instance type for reliability
        if let task = taskRunner.currentTask {
            return task is DelayedRecallTask || currentTaskTitle == "Delayed Recall Task"
        }
        return currentTaskTitle == "Delayed Recall Task"
    }
    
    var isOrientationTask: Bool {
        // Check both title and actual task instance type for reliability
        if let task = taskRunner.currentTask {
            return task is OrientationTask || currentTaskTitle == "Orientation Task"
        }
        return currentTaskTitle == "Orientation Task"
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
    
    func loadWorkingMemoryResults() async {
        print("📊 TaskViewModel: Loading working memory results...")
        print("   - DataController instance: \(ObjectIdentifier(dataController as AnyObject))")
        
        // Verify we're using TaskRunner's DataController
        if let taskRunnerInstance = taskRunner as? TaskRunner {
            // Cast to AnyObject for identity comparison (since DataController is a class)
            if (dataController as AnyObject) !== (taskRunnerInstance.dataController as AnyObject) {
                print("⚠️ TaskViewModel: CRITICAL - DataController instance mismatch!")
                print("   - TaskViewModel DataController: \(ObjectIdentifier(dataController as AnyObject))")
                print("   - TaskRunner DataController: \(ObjectIdentifier(taskRunnerInstance.dataController as AnyObject))")
            } else {
                print("✅ TaskViewModel: Using same DataController instance as TaskRunner")
            }
        }
        
        guard let currentTask = taskRunner.currentTask else {
            print("⚠️ TaskViewModel: No current task available")
            return
        }
        
        print("   - Current task ID: \(currentTask.id)")
        print("   - Current task title: \(currentTask.title)")
        
        // Try loading with retries (in case data is still being saved)
        for attempt in 1...3 {
            do {
                let allResponses = try await dataController.fetchAllItemResponses()
                print("   - Attempt \(attempt): Total ItemResponses in database: \(allResponses.count)")
                
                // Log all responses for debugging
                for response in allResponses {
                    print("     - Response: id=\(response.id), taskId=\(response.taskId), score=\(response.score?.description ?? "nil")")
                }
                
                let taskResponses = allResponses
                    .filter { $0.taskId == currentTask.id }
                    .sorted { $0.createdAt < $1.createdAt }
                
                print("   - ItemResponses for this task: \(taskResponses.count)")
                for (index, response) in taskResponses.enumerated() {
                    print("     Response \(index + 1): id=\(response.id), score=\(response.score?.description ?? "nil"), correctWords=\(response.correctWords?.count ?? 0)")
                }
                
                if !taskResponses.isEmpty || attempt == 3 {
                    await MainActor.run {
                        self.workingMemoryResults = taskResponses
                        print("✅ TaskViewModel: Results loaded and published (\(taskResponses.count) responses)")
                    }
                    return
                } else {
                    print("   ⏳ Attempt \(attempt): No results yet, retrying in 1 second...")
                    try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                }
            } catch {
                print("❌ TaskViewModel: Failed to load working memory results (attempt \(attempt)): \(error)")
                if attempt < 3 {
                    try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000) // 1 second before retry
                }
            }
        }
        
        print("⚠️ TaskViewModel: No results found after 3 attempts")
    }
    
    func loadAttentionResults() async {
        print("📊 TaskViewModel: Loading attention task results...")
        print("   - DataController instance: \(ObjectIdentifier(dataController as AnyObject))")
        
        guard let currentTask = taskRunner.currentTask else {
            print("⚠️ TaskViewModel: No current task available")
            return
        }
        
        print("   - Current task ID: \(currentTask.id)")
        print("   - Current task title: \(currentTask.title)")
        
        // Try loading with retries
        for attempt in 1...3 {
            do {
                let allResponses = try await dataController.fetchAllItemResponses()
                print("   - Attempt \(attempt): Total ItemResponses in database: \(allResponses.count)")
                
                let taskResponses = allResponses
                    .filter { $0.taskId == currentTask.id }
                    .sorted { $0.createdAt < $1.createdAt }
                
                print("   - ItemResponses for this task: \(taskResponses.count)")
                
                if !taskResponses.isEmpty || attempt == 3 {
                    await MainActor.run {
                        self.attentionResults = taskResponses
                        print("✅ TaskViewModel: Attention results loaded and published (\(taskResponses.count) responses)")
                    }
                    return
                } else {
                    print("   ⏳ Attempt \(attempt): No results yet, retrying in 1 second...")
                    try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)
                }
            } catch {
                print("❌ TaskViewModel: Failed to load attention results (attempt \(attempt)): \(error)")
                if attempt < 3 {
                    try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
        
        print("⚠️ TaskViewModel: No attention results found after 3 attempts")
    }
    
    func loadLanguageResults() async {
        print("📊 TaskViewModel: Loading language task results...")
        print("   - DataController instance: \(ObjectIdentifier(dataController as AnyObject))")
        
        guard let currentTask = taskRunner.currentTask else {
            print("⚠️ TaskViewModel: No current task available")
            return
        }
        
        print("   - Current task ID: \(currentTask.id)")
        print("   - Current task title: \(currentTask.title)")
        
        // Try loading with retries
        for attempt in 1...3 {
            do {
                let allResponses = try await dataController.fetchAllItemResponses()
                print("   - Attempt \(attempt): Total ItemResponses in database: \(allResponses.count)")
                
                let taskResponses = allResponses
                    .filter { $0.taskId == currentTask.id }
                    .sorted { $0.createdAt < $1.createdAt }
                
                print("   - ItemResponses for this task: \(taskResponses.count)")
                
                if !taskResponses.isEmpty || attempt == 3 {
                    await MainActor.run {
                        self.languageResults = taskResponses
                        print("✅ TaskViewModel: Language results loaded and published (\(taskResponses.count) responses)")
                    }
                    return
                } else {
                    print("   ⏳ Attempt \(attempt): No results yet, retrying in 1 second...")
                    try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)
                }
            } catch {
                print("❌ TaskViewModel: Failed to load language results (attempt \(attempt)): \(error)")
                if attempt < 3 {
                    try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
        
        print("⚠️ TaskViewModel: No language results found after 3 attempts")
    }
    
    func loadAbstractionResults() async {
        print("📊 TaskViewModel: Loading abstraction task results...")
        print("   - DataController instance: \(ObjectIdentifier(dataController as AnyObject))")
        
        guard let currentTask = taskRunner.currentTask else {
            print("⚠️ TaskViewModel: No current task available")
            return
        }
        
        print("   - Current task ID: \(currentTask.id)")
        print("   - Current task title: \(currentTask.title)")
        
        // Try loading with retries
        for attempt in 1...3 {
            do {
                let allResponses = try await dataController.fetchAllItemResponses()
                print("   - Attempt \(attempt): Total ItemResponses in database: \(allResponses.count)")
                
                let taskResponses = allResponses
                    .filter { $0.taskId == currentTask.id }
                    .sorted { $0.createdAt < $1.createdAt }
                
                print("   - ItemResponses for this task: \(taskResponses.count)")
                
                if !taskResponses.isEmpty || attempt == 3 {
                    await MainActor.run {
                        self.abstractionResults = taskResponses
                        print("✅ TaskViewModel: Abstraction results loaded and published (\(taskResponses.count) responses)")
                    }
                    return
                } else {
                    print("   ⏳ Attempt \(attempt): No results yet, retrying in 1 second...")
                    try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)
                }
            } catch {
                print("❌ TaskViewModel: Failed to load abstraction results (attempt \(attempt)): \(error)")
                if attempt < 3 {
                    try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
        
        print("⚠️ TaskViewModel: No abstraction results found after 3 attempts")
    }
    
    func loadDelayedRecallResults() async {
        print("📊 TaskViewModel: Loading delayed recall task results...")
        print("   - DataController instance: \(ObjectIdentifier(dataController as AnyObject))")
        
        guard let currentTask = taskRunner.currentTask else {
            print("⚠️ TaskViewModel: No current task available")
            return
        }
        
        print("   - Current task ID: \(currentTask.id)")
        print("   - Current task title: \(currentTask.title)")
        
        // Try loading with retries
        for attempt in 1...3 {
            do {
                let allResponses = try await dataController.fetchAllItemResponses()
                print("   - Attempt \(attempt): Total ItemResponses in database: \(allResponses.count)")
                
                let taskResponses = allResponses
                    .filter { $0.taskId == currentTask.id }
                    .sorted { $0.createdAt < $1.createdAt }
                
                print("   - ItemResponses for this task: \(taskResponses.count)")
                
                if !taskResponses.isEmpty || attempt == 3 {
                    await MainActor.run {
                        self.delayedRecallResults = taskResponses
                        print("✅ TaskViewModel: Delayed recall results loaded and published (\(taskResponses.count) responses)")
                    }
                    return
                } else {
                    print("   ⏳ Attempt \(attempt): No results yet, retrying in 1 second...")
                    try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)
                }
            } catch {
                print("❌ TaskViewModel: Failed to load delayed recall results (attempt \(attempt)): \(error)")
                if attempt < 3 {
                    try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
        
        print("⚠️ TaskViewModel: No delayed recall results found after 3 attempts")
    }
    
    func loadOrientationResults() async {
        print("📊 TaskViewModel: Loading orientation task results...")
        print("   - DataController instance: \(ObjectIdentifier(dataController as AnyObject))")
        
        guard let currentTask = taskRunner.currentTask else {
            print("⚠️ TaskViewModel: No current task available")
            return
        }
        
        print("   - Current task ID: \(currentTask.id)")
        print("   - Current task title: \(currentTask.title)")
        
        // Try loading with retries
        for attempt in 1...3 {
            do {
                let allResponses = try await dataController.fetchAllItemResponses()
                print("   - Attempt \(attempt): Total ItemResponses in database: \(allResponses.count)")
                
                let taskResponses = allResponses
                    .filter { $0.taskId == currentTask.id }
                    .sorted { $0.createdAt < $1.createdAt }
                
                print("   - ItemResponses for this task: \(taskResponses.count)")
                
                if !taskResponses.isEmpty || attempt == 3 {
                    await MainActor.run {
                        self.orientationResults = taskResponses
                        print("✅ TaskViewModel: Orientation results loaded and published (\(taskResponses.count) responses)")
                    }
                    return
                } else {
                    print("   ⏳ Attempt \(attempt): No results yet, retrying in 1 second...")
                    try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)
                }
            } catch {
                print("❌ TaskViewModel: Failed to load orientation results (attempt \(attempt)): \(error)")
                if attempt < 3 {
                    try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
        
        print("⚠️ TaskViewModel: No orientation results found after 3 attempts")
    }
    
    /// Load results for a specific session and task ID (for viewing completed sessions)
    func loadResultsForSession(sessionId: UUID, taskId: UUID, taskTitle: String) async {
        print("📊 TaskViewModel: Loading results for session \(sessionId), task \(taskId)")
        
        // Set the task title so the view knows which type to show
        await MainActor.run {
            self.currentTaskTitle = taskTitle
        }
        
        // Determine task type from title
        let isWorkingMemory = taskTitle == "Working Memory Task"
        let isAttention = taskTitle == "Attention Task"
        let isLanguage = taskTitle == "Language Task"
        let isAbstraction = taskTitle == "Abstraction Task"
        let isDelayedRecall = taskTitle == "Delayed Recall Task"
        let isOrientation = taskTitle == "Orientation Task"
        
        do {
            let sessionResponses = try await dataController.fetchItemResponses(for: sessionId)
            let taskResponses = sessionResponses
                .filter { $0.taskId == taskId }
                .sorted { $0.createdAt < $1.createdAt }
            
            print("   - Found \(taskResponses.count) responses for this task")
            
            await MainActor.run {
                if isWorkingMemory {
                    self.workingMemoryResults = taskResponses
                } else if isAttention {
                    self.attentionResults = taskResponses
                } else if isLanguage {
                    self.languageResults = taskResponses
                } else if isAbstraction {
                    self.abstractionResults = taskResponses
                } else if isDelayedRecall {
                    self.delayedRecallResults = taskResponses
                } else if isOrientation {
                    self.orientationResults = taskResponses
                }
            }
        } catch {
            print("❌ TaskViewModel: Failed to load results for session: \(error)")
        }
    }
}

