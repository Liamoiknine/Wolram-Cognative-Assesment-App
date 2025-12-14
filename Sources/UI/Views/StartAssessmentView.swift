import SwiftUI

/// Helper function to create a Swift concurrency Task.
/// Uses _Concurrency.Task to explicitly reference Swift's concurrency Task type.
fileprivate func createTask(_ operation: @escaping () async -> Void) {
    _Concurrency.Task {
        await operation()
    }
}

/// View for starting a new assessment.
/// Launches the TaskRunner when ready.
struct StartAssessmentView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var taskRunner: TaskRunner
    @Environment(\.dismiss) private var dismiss
    
    init(
        dataController: DataControllerProtocol? = nil,
        taskRunner: TaskRunnerProtocol? = nil
    ) {
        // This init is for testing - in normal use, environment objects are used
        // Store for later use if needed
    }
    
    var body: some View {
        StartAssessmentViewWrapper(
            dataController: dataController,
            taskRunner: taskRunner
        )
    }
}

/// Wrapper that creates the viewModel from environment objects
private struct StartAssessmentViewWrapper: View {
    let dataController: DataController
    let taskRunner: TaskRunner
    @Environment(\.audioManager) private var audioManager
    @StateObject private var viewModel: StartAssessmentViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(dataController: DataController, taskRunner: TaskRunner) {
        self.dataController = dataController
        self.taskRunner = taskRunner
        
        // AudioManager will be injected via environment in body
        // For init, we'll use a placeholder that gets replaced
        let fileStorage = FileStorage()
        let placeholderAudioManager = AudioManager(fileStorage: fileStorage)
        
        _viewModel = StateObject(wrappedValue: StartAssessmentViewModel(
            dataController: dataController,
            taskRunner: taskRunner,
            audioManager: placeholderAudioManager
        ))
    }
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.secondarySystemBackground).opacity(0.3)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Working Memory Test Card
                    testCard(for: .workingMemory)
                    
                    // Attention Task Card
                    testCard(for: .attention)
                    
                    // Language Task Card
                    testCard(for: .language)
                    
                    // Abstraction Task Card
                    testCard(for: .abstraction)
                    
                    // Error Message
                    if let errorMessage = viewModel.errorMessage {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.red)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.red.opacity(0.1))
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .padding(.top, 0)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadPatients()
        }
        .fullScreenCover(isPresented: $viewModel.shouldNavigateToWorkingMemory) {
            WorkingMemoryTaskView(taskRunner: taskRunner, dataController: dataController)
        }
        .fullScreenCover(isPresented: $viewModel.shouldNavigateToAttention) {
            AttentionTaskView(taskRunner: taskRunner, dataController: dataController)
        }
        .fullScreenCover(isPresented: $viewModel.shouldNavigateToLanguage) {
            LanguageTaskView(taskRunner: taskRunner, dataController: dataController)
        }
        .fullScreenCover(isPresented: $viewModel.shouldNavigateToAbstraction) {
            AbstractionTaskView(taskRunner: taskRunner, dataController: dataController)
        }
        .onAppear {
            // Update viewModel with environment AudioManager if available
            if let audioManager = audioManager {
                viewModel.updateAudioManager(audioManager)
            }
        }
    }
    
    // MARK: - Test Card View
    
    @ViewBuilder
    private func testCard(for testType: TestType) -> some View {
        Button(action: {
            createTask {
                await viewModel.startTest(testType)
            }
        }) {
            HStack(spacing: 16) {
                // Content
                VStack(alignment: .leading, spacing: 6) {
                    Text(testType.displayName)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    Text(testType.description)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                
                Spacer()
                
                // Arrow
                if viewModel.isStartingAssessment {
                    ProgressView()
                        .tint(testType.color)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isStartingAssessment)
    }
}
