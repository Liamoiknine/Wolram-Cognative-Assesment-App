import SwiftUI
import Combine

/// Helper function to create a Swift concurrency Task.
fileprivate func createTask(_ operation: @escaping () async -> Void) {
    _Concurrency.Task {
        await operation()
    }
}

/// Independent view for Language Task.
struct LanguageTaskView: View {
    @StateObject private var viewModel: TaskViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var recordingStartTime: Date?
    @State private var timeRemaining: Double = 10.0
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
            // Verify this is actually a language task
            if viewModel.isLanguageTask {
                if viewModel.currentState == .completed {
                    languageResultsView
                } else {
                    languageTaskActiveView
                }
            } else {
                // If somehow we're showing the wrong task, show error
                VStack(spacing: 16) {
                    Text("Error: Wrong task type")
                        .font(.headline)
                        .foregroundColor(.red)
                    Text("This view is for Language Task, but a different task is active.")
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
            if !viewModel.isLanguageTask {
                print("⚠️ LanguageTaskView: Warning - current task is not a LanguageTask!")
                print("   Current task title: \(viewModel.currentTaskTitle)")
                print("   Current task type: \(type(of: taskRunner?.currentTask))")
            }
            
            // If task is already completed (viewing results), load results immediately
            if viewModel.currentState == .completed && viewModel.isLanguageTask {
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
    private var languageTaskActiveView: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header with End Task and Back buttons
                VStack(spacing: 12) {
                    HStack {
                        // Back Button
                        Button(action: {
                            createTask {
                                // Stop the task immediately before dismissing
                                await viewModel.stopTask()
                                // Small delay to ensure state transition
                                try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
                                // Load results from partial data
                                await viewModel.loadLanguageResults()
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
                        
                        Spacer()
                        
                        // End Task Button
                        if viewModel.currentState != .idle && viewModel.currentState != .completed {
                            Button(action: {
                                createTask {
                                    await viewModel.stopTask()
                                    try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000)
                                    await viewModel.loadLanguageResults()
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
                    
                    // Task Name
                    Text(viewModel.currentTaskTitle)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    // Current Phase/Status
                    HStack(spacing: 8) {
                        Circle()
                            .fill(phaseColor)
                            .frame(width: 10, height: 10)
                        
                        Text(phaseDescription)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
                .background(
                    Color(.systemBackground)
                        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                )
                
                // Show countdown during recording, transcript otherwise
                if viewModel.currentState == .recording {
                    recordingCountdownView
                } else {
                    // Scrollable Transcript Window
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                if viewModel.transcript.isEmpty {
                                    VStack(spacing: 8) {
                                        ProgressView()
                                            .scaleEffect(1.2)
                                        Text("Preparing task...")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 40)
                                } else {
                                    ForEach(viewModel.transcript) { item in
                                        transcriptItemView(item: item)
                                            .id(item.id)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                        .onChange(of: viewModel.transcript.count) { _ in
                            let transcript = viewModel.transcript
                            if let lastHighlighted = transcript.lastIndex(where: { $0.isHighlighted }) {
                                let item = transcript[lastHighlighted]
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(item.id, anchor: .center)
                                }
                            } else if let lastItem = transcript.last {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(lastItem.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    .background(Color(.secondarySystemBackground))
                }
                
                // Current Sentence Display
                if let currentWord = viewModel.currentWord, viewModel.currentState == .presenting {
                    VStack(spacing: 8) {
                        Text("Current Sentence")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .tracking(1)
                        
                        Text(currentWord)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 20)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.orange.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.orange.opacity(0.3), lineWidth: 2)
                                    )
                            )
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(Color(.systemBackground))
                }
            }
            .onChange(of: viewModel.currentState) { newState in
                if newState == .recording {
                    recordingStartTime = Date()
                    // Check if fluency phase (30 seconds) or sentence phase (10 seconds)
                    let isFluency = viewModel.transcript.contains { $0.type == .fluencyPrompt }
                    timeRemaining = isFluency ? 30.0 : 10.0
                    startCountdown()
                } else {
                    stopCountdown()
                    recordingStartTime = nil
                    let isFluency = viewModel.transcript.contains { $0.type == .fluencyPrompt }
                    timeRemaining = isFluency ? 30.0 : 10.0
                }
            }
            .onDisappear {
                stopCountdown()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Results View
    
    @ViewBuilder
    private var languageResultsView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header with Back Button
                VStack(spacing: 12) {
                    HStack {
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
                        
                        Spacer()
                    }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.green)
                        
                        Text("Task Completed")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    
                    Text("Review your results below")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // Total Score
                    if !viewModel.languageResults.isEmpty {
                        let totalScore = viewModel.languageResults.compactMap { $0.score }.reduce(0, +)
                        VStack(spacing: 4) {
                            Text("Total Score")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                            Text("\(Int(totalScore))/3")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(scoreColor(totalScore / 3.0))
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
                .background(Color(.systemBackground))
                
                if viewModel.languageResults.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading results...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                    .onAppear {
                        _Concurrency.Task {
                            await viewModel.loadLanguageResults()
                        }
                    }
                } else {
                    // Results Cards
                    VStack(spacing: 16) {
                        ForEach(Array(viewModel.languageResults.enumerated()), id: \.element.id) { index, response in
                            languagePhaseResultCard(phaseNumber: index + 1, response: response)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 20)
                    
                    // Back Button at Bottom
                    Button(action: {
                        dismiss()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Back to Dashboard")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
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
    
    @ViewBuilder
    private func transcriptItemView(item: TranscriptItem) -> some View {
        TranscriptItemView(item: item)
    }
    
    @ViewBuilder
    private func languagePhaseResultCard(phaseNumber: Int, response: ItemResponse) -> some View {
        let phaseNames = ["Sentence 1", "Sentence 2", "Fluency"]
        let phaseName = phaseNumber <= phaseNames.count ? phaseNames[phaseNumber - 1] : "Phase \(phaseNumber)"
        let maxScore = 1.0
        
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(phaseName)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    
                    if let score = response.score {
                        Text("Score: \(Int(score)) point\(Int(score) == 1 ? "" : "s")")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(scoreColor(score))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Score Badge
                if let score = response.score {
                    VStack(spacing: 3) {
                        Text("\(Int(score))")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(scoreColor(score))
                        Text("/ \(Int(maxScore))")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(scoreColor(score).opacity(0.15))
                    )
                }
            }
            
            Divider()
            
            // Phase-specific details
            if phaseNumber <= 2 {
                sentenceContent(response: response)
            } else {
                fluencyContent(response: response)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
    }
    
    @ViewBuilder
    private func sentenceContent(response: ItemResponse) -> some View {
        if let expectedWords = response.expectedWords {
            VStack(alignment: .leading, spacing: 8) {
                Text("Expected Sentence")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                Text(expectedWords.joined(separator: " "))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        
        if let transcription = response.responseText, !transcription.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Response")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .padding(.top, 8)
                
                Text(transcription)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.secondarySystemBackground))
                    )
            }
        }
    }
    
    @ViewBuilder
    private func fluencyContent(response: ItemResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fluency Test")
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            // Extract word count from response
            let wordCount = extractWordCount(from: response)
            let threshold = 10
            let passed = wordCount > threshold
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Words starting with F:")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(wordCount)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(passed ? .green : .red)
                }
                
                HStack {
                    Text("Threshold:")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("> \(threshold) words")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                
                Divider()
                    .padding(.vertical, 4)
                
                HStack {
                    Text("Result:")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                    Spacer()
                    Text(passed ? "Passed" : "Failed")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(passed ? .green : .red)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemBackground))
            )
            
            if let transcription = response.responseText, !transcription.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Response")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .padding(.top, 8)
                    
                    Text(transcription)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.primary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.secondarySystemBackground).opacity(0.5))
                        )
                }
            }
        }
    }
    
    private func extractWordCount(from response: ItemResponse) -> Int {
        // Try to extract word count from responseText
        if let responseText = response.responseText {
            let normalized = responseText.lowercased()
                .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            let words = normalized.split(separator: " ").map { String($0) }
            let fWords = words.filter { word in
                !word.isEmpty && word.first == "f"
            }
            return Set(fWords).count
        }
        return 0
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

