import SwiftUI
import Combine

/// Helper function to create a Swift concurrency Task.
fileprivate func createTask(_ operation: @escaping () async -> Void) {
    _Concurrency.Task {
        await operation()
    }
}

/// Independent view for Attention Task.
struct AttentionTaskView: View {
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
            // Verify this is actually an attention task
            if viewModel.isAttentionTask {
                if viewModel.currentState == .completed {
                    attentionResultsView
                } else {
                    attentionTaskActiveView
                }
            } else {
                // If somehow we're showing the wrong task, show error
                VStack(spacing: 16) {
                    Text("Error: Wrong task type")
                        .font(.headline)
                        .foregroundColor(.red)
                    Text("This view is for Attention Task, but a different task is active.")
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
            if !viewModel.isAttentionTask {
                print("⚠️ AttentionTaskView: Warning - current task is not an AttentionTask!")
                print("   Current task title: \(viewModel.currentTaskTitle)")
                print("   Current task type: \(type(of: taskRunner?.currentTask))")
            }
            
            // If task is already completed (viewing results), load results immediately
            if viewModel.currentState == .completed && viewModel.isAttentionTask {
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
    private var attentionTaskActiveView: some View {
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
                                await viewModel.loadAttentionResults()
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
                                    await viewModel.loadAttentionResults()
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
                
                // Current Item Display
                if let currentWord = viewModel.currentWord, viewModel.currentState == .presenting {
                    VStack(spacing: 8) {
                        Text("Current Item")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .tracking(1)
                        
                        Text(currentWord.uppercased())
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 20)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.purple.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.purple.opacity(0.3), lineWidth: 2)
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
                    let isSerial7s = viewModel.transcript.contains { $0.type == .calculationPrompt }
                    timeRemaining = isSerial7s ? 50.0 : 10.0
                    startCountdown()
                } else {
                    stopCountdown()
                    recordingStartTime = nil
                    let isSerial7s = viewModel.transcript.contains { $0.type == .calculationPrompt }
                    timeRemaining = isSerial7s ? 50.0 : 10.0
                }
            }
            .onDisappear {
                stopCountdown()
            }
            
            // Full-screen tap detection overlay for letter tapping phase
            if isLetterTappingPhase, let taskRunnerInstance = taskRunner as? TaskRunner {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let attentionTask = taskRunnerInstance.currentTask as? AttentionTask {
                            attentionTask.recordTap(timestamp: Date())
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var isLetterTappingPhase: Bool {
        return viewModel.transcript.contains { $0.type == .letter }
    }
    
    // MARK: - Results View
    
    @ViewBuilder
    private var attentionResultsView: some View {
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
                    if !viewModel.attentionResults.isEmpty {
                        let totalScore = viewModel.attentionResults.compactMap { $0.score }.reduce(0, +)
                        VStack(spacing: 4) {
                            Text("Total Score")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                            Text("\(Int(totalScore))/6")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(scoreColor(totalScore / 6.0))
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
                .background(Color(.systemBackground))
                
                if viewModel.attentionResults.isEmpty {
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
                            await viewModel.loadAttentionResults()
                        }
                    }
                } else {
                    // Results Cards
                    VStack(spacing: 16) {
                        ForEach(Array(viewModel.attentionResults.enumerated()), id: \.element.id) { index, response in
                            attentionPhaseResultCard(phaseNumber: index + 1, response: response)
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
    private func attentionPhaseResultCard(phaseNumber: Int, response: ItemResponse) -> some View {
        let phaseNames = ["Digit Span Forward", "Digit Span Backward", "Letter Tapping", "Serial 7s"]
        let phaseName = phaseNumber <= phaseNames.count ? phaseNames[phaseNumber - 1] : "Phase \(phaseNumber)"
        let maxScore = phaseNumber <= 2 ? 1 : phaseNumber == 3 ? 1 : 3
        
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
                        Text("/ \(maxScore)")
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
            phaseSpecificContent(phaseNumber: phaseNumber, response: response)
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
    private func phaseSpecificContent(phaseNumber: Int, response: ItemResponse) -> some View {
        if phaseNumber == 1 || phaseNumber == 2 {
            digitSpanContent(response: response)
        } else if phaseNumber == 3 {
            letterTappingContent(response: response)
        } else if phaseNumber == 4 {
            serial7sContent(response: response)
        }
    }
    
    @ViewBuilder
    private func digitSpanContent(response: ItemResponse) -> some View {
        if let expectedWords = response.expectedWords {
            VStack(alignment: .leading, spacing: 8) {
                Text("Expected Digits")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                Text(expectedWords.joined(separator: " "))
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
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
    private func letterTappingContent(response: ItemResponse) -> some View {
        if let expectedWords = response.expectedWords, let correctWords = response.correctWords {
            let expectedAPositions = expectedWords.enumerated().compactMap { $0.element == "A" ? $0.offset : nil }
            let tappedPositions = Set(correctWords.compactMap { Int($0) })
            let missingAPositions = Set(expectedAPositions).subtracting(tappedPositions)
            let incorrectTapPositions = tappedPositions.subtracting(Set(expectedAPositions))
            let errorPositions = missingAPositions.union(incorrectTapPositions)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Letter Sequence")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                letterGrid(
                    expectedWords: expectedWords,
                    errorPositions: errorPositions,
                    tappedPositions: tappedPositions
                )
                
                if let score = response.score {
                    let errors = score == 0 ? "3+" : "≤2"
                    Text("Errors: \(errors)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
        }
    }
    
    @ViewBuilder
    private func letterGrid(expectedWords: [String], errorPositions: Set<Int>, tappedPositions: Set<Int>) -> some View {
        let indices = (0..<expectedWords.count).map { $0 }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 28), spacing: 4)], spacing: 4) {
            ForEach(indices, id: \.self) { idx in
                letterCell(
                    letter: expectedWords[idx],
                    index: idx,
                    isError: errorPositions.contains(idx),
                    isA: expectedWords[idx] == "A",
                    wasTapped: tappedPositions.contains(idx)
                )
            }
        }
    }
    
    private func letterCell(letter: String, index: Int, isError: Bool, isA: Bool, wasTapped: Bool) -> some View {
        let backgroundColor: Color
        let foregroundColor: Color
        
        if isError {
            backgroundColor = Color.red
            foregroundColor = .white
        } else if isA && wasTapped {
            backgroundColor = Color.green
            foregroundColor = .white
        } else if isA {
            backgroundColor = Color.red
            foregroundColor = .white
        } else {
            backgroundColor = Color(.secondarySystemBackground)
            foregroundColor = .primary
        }
        
        return Text(letter)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundColor(foregroundColor)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(backgroundColor)
            )
    }
    
    @ViewBuilder
    private func serial7sContent(response: ItemResponse) -> some View {
        if let expectedWords = response.expectedWords, let transcription = response.responseText {
            VStack(alignment: .leading, spacing: 8) {
                Text("Expected Answers")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                Text(expectedWords.joined(separator: ", "))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                
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

