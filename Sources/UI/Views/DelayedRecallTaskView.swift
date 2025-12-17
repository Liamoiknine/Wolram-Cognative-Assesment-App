import SwiftUI
import Combine

/// Helper function to create a Swift concurrency Task.
fileprivate func createTask(_ operation: @escaping () async -> Void) {
    _Concurrency.Task {
        await operation()
    }
}

/// Independent view for Delayed Recall Task.
struct DelayedRecallTaskView: View {
    @StateObject private var viewModel: TaskViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var scrollProxy: ScrollViewProxy?
    @State private var recordingStartTime: Date?
    @State private var timeRemaining: Double = 15.0
    @State private var countdownTimer: Timer?
    
    private let taskRunner: TaskRunnerProtocol?
    
    init(taskRunner: TaskRunnerProtocol? = nil, dataController: DataControllerProtocol? = nil) {
        self.taskRunner = taskRunner
        guard let providedTaskRunner = taskRunner else {
            let fallbackDataController = DataController()
            let fileStorage = FileStorage()
            let audioManager = AudioManager(fileStorage: fileStorage)
            let transcriptionManager = TranscriptionManager(fileStorage: fileStorage)
            let fallbackTaskRunner = TaskRunner(
                dataController: fallbackDataController,
                audioManager: audioManager,
                transcriptionManager: transcriptionManager,
                fileStorage: fileStorage
            )
            _viewModel = StateObject(wrappedValue: TaskViewModel(taskRunner: fallbackTaskRunner, dataController: fallbackDataController))
            return
        }
        
        let dataControllerToUse: DataControllerProtocol
        if let taskRunnerInstance = providedTaskRunner as? TaskRunner {
            dataControllerToUse = taskRunnerInstance.dataController
        } else {
            dataControllerToUse = dataController ?? DataController()
        }
        
        _viewModel = StateObject(wrappedValue: TaskViewModel(taskRunner: providedTaskRunner, dataController: dataControllerToUse))
    }
    
    var body: some View {
        Group {
            // Verify this is actually a delayed recall task
            if viewModel.isDelayedRecallTask {
                if viewModel.currentState == .completed {
                    delayedRecallResultsView
                } else {
                    delayedRecallTaskActiveView
                }
            } else {
                // If somehow we're showing the wrong task, show error
                VStack(spacing: 16) {
                    Text("Error: Wrong task type")
                        .font(.headline)
                        .foregroundColor(.red)
                    Text("This view is for Delayed Recall Task, but a different task is active.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("Go Back") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
        }
        .onAppear {
            // Verify task type on appear
            if !viewModel.isDelayedRecallTask {
                print("⚠️ DelayedRecallTaskView: Warning - current task is not a DelayedRecallTask!")
                print("   Current task title: \(viewModel.currentTaskTitle)")
                print("   Current task type: \(type(of: taskRunner?.currentTask))")
            }
            
            // If task is already completed (viewing results), load results immediately
            if viewModel.currentState == .completed && viewModel.isDelayedRecallTask {
                if let task = taskRunner?.currentTask,
                   let taskRunnerInstance = taskRunner as? TaskRunner,
                   let sessionId = taskRunnerInstance.currentSessionId {
                    createTask {
                        await viewModel.loadResultsForSession(
                            sessionId: sessionId,
                            taskId: task.id,
                            taskTitle: task.title
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Active Task View
    
    @ViewBuilder
    private var delayedRecallTaskActiveView: some View {
        VStack(spacing: 0) {
            // Header with Back Button
            VStack(spacing: 8) {
                // Back Button and Task Name Row
                HStack(spacing: 12) {
                    // Back Button
                    Button(action: {
                        createTask {
                            // Stop the task immediately before dismissing
                            await viewModel.stopTask()
                            // Small delay to ensure state transition
                            try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
                            // Load results from partial data
                            await viewModel.loadDelayedRecallResults()
                            // Dismiss after stopping
                            await MainActor.run {
                                dismiss()
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // Task Name
                    Text(viewModel.currentTaskTitle)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    Spacer()
                    
                    // End Task Button
                    if viewModel.currentState != .idle && viewModel.currentState != .completed {
                        Button(action: {
                            createTask {
                                await viewModel.stopTask()
                                try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000)
                                await viewModel.loadDelayedRecallResults()
                            }
                        }) {
                            Text("End Task")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.red)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.red.opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Current Phase/Status
                HStack(spacing: 6) {
                    Circle()
                        .fill(phaseColor)
                        .frame(width: 8, height: 8)
                    
                    Text(phaseDescription)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.top, 0)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background(
                Color(.systemBackground)
                    .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
            )
            .safeAreaInset(edge: .top) {
                Color.clear.frame(height: 0)
            }
            
            // Show countdown during recording, transcript otherwise
            if viewModel.currentState == .recording {
                recordingCountdownView
            } else {
                transcriptScrollViewContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .top)
        .onChange(of: viewModel.currentState) { newState in
            if newState == .recording {
                recordingStartTime = Date()
                timeRemaining = 15.0
                startCountdown()
            } else {
                stopCountdown()
                recordingStartTime = nil
                timeRemaining = 15.0
            }
        }
        .onDisappear {
            stopCountdown()
        }
    }
    
    // MARK: - Results View
    
    @ViewBuilder
    private var delayedRecallResultsView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header with Back Button
                VStack(spacing: 8) {
                    // Back Button and Title Row
                    HStack(spacing: 12) {
                        // Back Button
                        Button(action: {
                            dismiss()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Back")
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.blue.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)
                        
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.green)
                            
                            Text("Task Completed")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        
                        Spacer()
                    }
                    
                    Text("Review your results below")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
                .background(Color(.systemBackground))
                
                if viewModel.delayedRecallResults.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.9)
                        Text("Loading results...")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("Results may still be processing")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .onAppear {
                        _Concurrency.Task {
                            await viewModel.loadDelayedRecallResults()
                        }
                    }
                } else {
                    // Results Card
                    VStack(spacing: 16) {
                        if let response = viewModel.delayedRecallResults.first {
                            delayedRecallResultCard(response: response)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
        }
        .background(Color(.secondarySystemBackground))
    }
    
    // MARK: - Helper Views
    
    private var phaseColor: Color {
        switch viewModel.currentState {
        case .idle:
            return .gray
        case .presenting:
            return .blue
        case .recording:
            return .red
        case .evaluating:
            return .orange
        case .completed:
            return .green
        }
    }
    
    private var phaseDescription: String {
        switch viewModel.currentState {
        case .idle:
            return "Ready"
        case .presenting:
            return "Reading Instructions"
        case .recording:
            return "Listening for Response"
        case .evaluating:
            return "Processing Results"
        case .completed:
            return "Completed"
        }
    }
    
    private var recordingCountdownView: some View {
        VStack(spacing: 16) {
            Text("Recording...")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.red)
            
            Text("\(Int(timeRemaining))")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundColor(.red)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
    
    private var transcriptScrollViewContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(viewModel.transcript) { item in
                        TranscriptItemView(item: item)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .onAppear {
                scrollProxy = proxy
            }
            .onChange(of: viewModel.transcript.count) { _ in
                if let lastItem = viewModel.transcript.last {
                    withAnimation {
                        proxy.scrollTo(lastItem.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
    }
    
    @ViewBuilder
    private func delayedRecallResultCard(response: ItemResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Delayed Recall")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Spacer()
                
                if let score = response.score {
                    Text("\(Int(score * 5))/5")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(scoreColor(score))
                }
            }
            
            Divider()
            
            // Expected Words
            if let expectedWords = response.expectedWords, !expectedWords.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Expected Words")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    Text(expectedWords.joined(separator: ", "))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.primary)
                }
            }
            
            // Correct Words
            if let correctWords = response.correctWords, !correctWords.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Correct Words")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    Text(correctWords.joined(separator: ", "))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.green)
                }
            }
            
            // Response Text
            if let responseText = response.responseText, !responseText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your Response")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    Text(responseText)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
    
    private func scoreColor(_ score: Double) -> Color {
        if score >= 0.8 {
            return .green
        } else if score >= 0.5 {
            return .orange
        } else {
            return .red
        }
    }
    
    // MARK: - Countdown Timer
    
    private func startCountdown() {
        stopCountdown()
        guard viewModel.currentState == .recording else { return }
        
        let startTime = recordingStartTime ?? Date()
        let initialDuration = timeRemaining
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [self] _ in
            guard self.viewModel.currentState == .recording else {
                self.stopCountdown()
                return
            }
            
            let elapsed = Date().timeIntervalSince(startTime)
            self.timeRemaining = max(0, initialDuration - elapsed)
            if self.timeRemaining <= 0 {
                self.stopCountdown()
            }
        }
    }
    
    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }
}

