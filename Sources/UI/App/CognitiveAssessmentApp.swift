import SwiftUI

/// Main SwiftUI App entry point.
/// Sets up dependency injection for all subsystems.
@available(iOS 13.0, *)
@main
struct CognitiveAssessmentApp: App {
    // Dependency injection setup
    private let dataController: DataController
    private let fileStorage: FileStorageProtocol
    private let audioManager: AudioManagerProtocol
    private let transcriptionManager: TranscriptionManagerProtocol
    private let taskRunner: TaskRunner
    
    init() {
        print("🚀 CognitiveAssessmentApp: Initializing...")
        do {
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
            
            print("✅ CognitiveAssessmentApp: Initialization complete")
        } catch {
            print("❌ CognitiveAssessmentApp: Initialization failed: \(error)")
            fatalError("Failed to initialize app: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(taskRunner)
                .environmentObject(dataController)
                .environment(\.audioManager, audioManager)
                .task {
                    await seedTestPatient()
                }
                .onAppear {
                    print("✅ CognitiveAssessmentApp: HomeView appeared")
                }
        }
    }
    
    private func seedTestPatient() async {
        // Check if patients already exist to avoid duplicates
        let existingPatients = try? await dataController.fetchAllPatients()
        guard existingPatients?.isEmpty ?? true else { return }
        
        // Create a test patient named "Test"
        let testPatient = Patient(name: "test")
        
        do {
            _ = try await dataController.createPatient(testPatient)
            print("✅ Seeded test patient: \(testPatient.name)")
        } catch {
            print("❌ Failed to seed test patient: \(error)")
        }
    }
}

// Environment key for AudioManager
private struct AudioManagerKey: EnvironmentKey {
    static let defaultValue: AudioManagerProtocol? = nil
}

extension EnvironmentValues {
    var audioManager: AudioManagerProtocol? {
        get { self[AudioManagerKey.self] }
        set { self[AudioManagerKey.self] = newValue }
    }
}

