import SwiftUI

/// Main SwiftUI App entry point.
/// Sets up dependency injection for all subsystems.
@main
struct CognitiveAssessmentApp: App {
    // Dependency injection setup
    private let dataController: DataControllerProtocol
    private let fileStorage: FileStorageProtocol
    private let audioManager: AudioManagerProtocol
    private let transcriptionManager: TranscriptionManagerProtocol
    private let taskRunner: TaskRunner
    
    init() {
        // Initialize dependencies
        let fileStorage = FileStorage()
        let dataController = DataController()
        let audioManager = AudioManager(fileStorage: fileStorage)
        let transcriptionManager = TranscriptionManager(fileStorage: fileStorage)
        let taskRunner = TaskRunner(
            dataController: dataController,
            audioManager: audioManager,
            transcriptionManager: transcriptionManager,
            fileStorage: fileStorage
        )
        
        self.fileStorage = fileStorage
        self.dataController = dataController
        self.audioManager = audioManager
        self.transcriptionManager = transcriptionManager
        self.taskRunner = taskRunner
    }
    
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(taskRunner)
        }
    }
}

