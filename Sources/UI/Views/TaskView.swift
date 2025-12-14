import SwiftUI
import Combine

/// Helper function to create a Swift concurrency Task.
/// Uses _Concurrency.Task to explicitly reference Swift's concurrency Task type.
fileprivate func createTask(_ operation: @escaping () async -> Void) {
    _Concurrency.Task {
        await operation()
    }
}

/// Generic container for task presentation.
/// Reacts to TaskRunner state changes.
struct TaskView: View {
    @StateObject private var viewModel: TaskViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var responseText: String = ""
    @State private var scrollProxy: ScrollViewProxy?
    @State private var recordingStartTime: Date?
    @State private var timeRemaining: Double = 10.0
    @State private var countdownTimer: Timer?
    
    private let taskRunner: TaskRunnerProtocol?
    
    init(taskRunner: TaskRunnerProtocol? = nil, dataController: DataControllerProtocol? = nil) {
        self.taskRunner = taskRunner
        // CRITICAL: Use the provided taskRunner and dataController to ensure we use the same instances
        // that were used to start the task and save the data
        guard let providedTaskRunner = taskRunner else {
            print("❌ TaskView: CRITICAL ERROR - taskRunner is nil!")
            print("   TaskView must be initialized with the same TaskRunner instance that started the task.")
            print("   Creating fallback TaskRunner, but results may not be accessible.")
            // Fallback: create new instances (will have empty data)
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
        
        // Use TaskRunner's DataController to ensure we access the same data
        let dataControllerToUse: DataControllerProtocol
        if let taskRunnerInstance = providedTaskRunner as? TaskRunner {
            dataControllerToUse = taskRunnerInstance.dataController
            print("✅ TaskView: Using TaskRunner's DataController")
            print("   - TaskRunner instance: \(ObjectIdentifier(providedTaskRunner as AnyObject))")
            print("   - DataController instance: \(ObjectIdentifier(dataControllerToUse as AnyObject))")
            
            // Warn if provided DataController differs
            if let providedDataController = dataController, (providedDataController as AnyObject) !== (dataControllerToUse as AnyObject) {
                print("⚠️ TaskView: WARNING - Provided DataController differs from TaskRunner's DataController!")
                print("   - Provided DataController: \(ObjectIdentifier(providedDataController as AnyObject))")
                print("   - TaskRunner's DataController: \(ObjectIdentifier(dataControllerToUse as AnyObject))")
                print("   - Using TaskRunner's DataController to ensure data access")
            }
        } else {
            // Fallback to provided dataController or create new
            dataControllerToUse = dataController ?? DataController()
            print("⚠️ TaskView: TaskRunner is not a TaskRunner instance, using provided/fallback DataController")
        }
        
        _viewModel = StateObject(wrappedValue: TaskViewModel(taskRunner: providedTaskRunner, dataController: dataControllerToUse))
    }
    
    var body: some View {
        Group {
            // Task-specific UI - show full screen
            if viewModel.isWorkingMemoryTask {
                workingMemoryTaskView
            } else if viewModel.isAttentionTask {
                attentionTaskView
            } else if viewModel.isLanguageTask {
                LanguageTaskView(taskRunner: taskRunner, dataController: (taskRunner as? TaskRunner)?.dataController)
            } else {
                // Generic task UI
        VStack(spacing: 20) {
            Text("Task: \(viewModel.currentTaskTitle)")
                .font(.title)
                .padding()
            
            // Display current state
            Text("State: \(viewModel.currentState.description)")
                .foregroundColor(.secondary)
            
                    genericTaskView
                    
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .padding()
                    }
                    
            // End Task button (shown during active phases)
            if viewModel.currentState != .idle && viewModel.currentState != .completed {
                Button("End Task") {
                    createTask {
                        await viewModel.stopTask()
                        // Small delay to ensure state transition completes
                        try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                        // Force load results after stopping
                        if viewModel.isAttentionTask {
                            await viewModel.loadAttentionResults()
                        } else if viewModel.isWorkingMemoryTask {
                            await viewModel.loadWorkingMemoryResults()
                        } else if viewModel.isLanguageTask {
                            await viewModel.loadLanguageResults()
                        }
                    }
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
                .padding(.top, 8)
            }
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // If task is already completed (viewing results), load results immediately
            if viewModel.currentState == .completed {
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
    
    @ViewBuilder
    private var genericTaskView: some View {
            // State-specific UI
            switch viewModel.currentState {
            case .idle:
                Text("No active task")
                    .foregroundColor(.secondary)
            case .presenting:
                Text("Presenting task instructions...")
                    .foregroundColor(.secondary)
            case .recording:
                Text("Recording...")
                    .foregroundColor(.red)
            case .evaluating:
                Text("Evaluating response...")
                    .foregroundColor(.blue)
            case .completed:
                Text("Task completed")
                    .foregroundColor(.green)
            }
            
            // Text response input (for text-based tasks)
            if viewModel.currentState == .presenting || viewModel.currentState == .recording {
                TextField("Enter response", text: $responseText)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                
                Button("Submit Response") {
                    createTask {
                        await viewModel.captureTextResponse(responseText)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
    }
    
    @ViewBuilder
    private var workingMemoryTaskView: some View {
        if viewModel.currentState == .completed {
            workingMemoryResultsView
        } else {
            workingMemoryTaskActiveView
        }
    }
    
    @ViewBuilder
    private var workingMemoryTaskActiveView: some View {
        VStack(spacing: 0) {
            // Header with Back Button
            VStack(spacing: 8) {
                // Back Button and Task Name Row
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
                                // Small delay to ensure state transition completes
                                try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                                await viewModel.loadWorkingMemoryResults()
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
            .padding(.top, 4)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background(
                Color(.systemBackground)
                    .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
            )
            
            // Show countdown during recording, transcript otherwise
            if viewModel.currentState == .recording {
                recordingCountdownView
            } else {
                transcriptScrollViewContent
            }
            
            // Current Word Display (if available)
            if let currentWord = viewModel.currentWord, viewModel.currentState == .presenting {
                VStack(spacing: 6) {
                    Text("Current Word")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    Text(currentWord.uppercased())
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.blue.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.blue.opacity(0.3), lineWidth: 1.5)
                                )
                        )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .top)
        .onChange(of: viewModel.currentState) { newState in
            if newState == .recording {
                // Start countdown when recording begins
                recordingStartTime = Date()
                timeRemaining = 10.0
                startCountdown()
            } else {
                // Stop countdown immediately when not recording
                stopCountdown()
                recordingStartTime = nil
                timeRemaining = 10.0 // Reset to avoid showing 0
            }
        }
        .onDisappear {
            stopCountdown()
        }
    }
    
    // MARK: - Countdown Timer
    
    private func startCountdown() {
        stopCountdown() // Stop any existing timer
        
        // Only start if we're still in recording state
        guard viewModel.currentState == .recording else {
            return
        }
        
        let startTime = recordingStartTime ?? Date()
        let initialDuration = timeRemaining // Store the initial duration
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [self] _ in
            // Check if we're still in recording state
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
        // Reset time remaining to avoid showing 0 when state changes
        if viewModel.currentState != .recording {
            timeRemaining = 10.0
        }
    }
    
    @ViewBuilder
    private var recordingCountdownView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Text("Start Speaking Now")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text("\(Int(timeRemaining))")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundColor(.red)
                .monospacedDigit()
            
            Text("seconds remaining")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemBackground))
    }
    
    // MARK: - Helper Views
    
    @ViewBuilder
    private var transcriptScrollViewContent: some View {
        TranscriptScrollViewWrapper(viewModel: viewModel, scrollProxy: $scrollProxy, itemView: transcriptItemView)
    }
    
    private struct TranscriptScrollViewWrapper: View {
        @ObservedObject var viewModel: TaskViewModel
        @Binding var scrollProxy: ScrollViewProxy?
        let itemView: (TranscriptItem) -> AnyView
        
        init(viewModel: TaskViewModel, scrollProxy: Binding<ScrollViewProxy?>, itemView: @escaping (TranscriptItem) -> some View) {
            self.viewModel = viewModel
            self._scrollProxy = scrollProxy
            self.itemView = { item in AnyView(itemView(item)) }
        }
        
        var body: some View {
            let transcript = _viewModel.wrappedValue.transcript
            let currentWord = _viewModel.wrappedValue.currentWord
            return TranscriptScrollView(
                transcript: transcript,
                currentWord: currentWord,
                onScrollProxySet: { proxy in
                    scrollProxy = proxy
                },
                onTranscriptChange: {
                    handleTranscriptChange()
                },
                onCurrentWordChange: {
                    handleCurrentWordChange()
                },
                itemView: itemView
            )
        }
        
        private func handleTranscriptChange() {
            guard let proxy = scrollProxy else { return }
            let transcript = _viewModel.wrappedValue.transcript
            scrollToHighlighted(proxy: proxy, transcript: transcript)
        }
        
        private func handleCurrentWordChange() {
            guard let word = _viewModel.wrappedValue.currentWord, let proxy = scrollProxy else { return }
            let transcript = _viewModel.wrappedValue.transcript
            scrollToCurrentWord(proxy: proxy, word: word, transcript: transcript)
        }
        
        private func scrollToHighlighted(proxy: ScrollViewProxy, transcript: [TranscriptItem]) {
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
        
        private func scrollToCurrentWord(proxy: ScrollViewProxy, word: String, transcript: [TranscriptItem]) {
            for item in transcript.reversed() {
                if item.text == word, case .word = item.type {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(item.id, anchor: .center)
                    }
                    break
                }
            }
        }
    }
    
    private struct TranscriptScrollView: View {
        let transcript: [TranscriptItem]
        let currentWord: String?
        let onScrollProxySet: (ScrollViewProxy) -> Void
        let onTranscriptChange: () -> Void
        let onCurrentWordChange: () -> Void
        let itemView: (TranscriptItem) -> AnyView
        
        init(
            transcript: [TranscriptItem],
            currentWord: String?,
            onScrollProxySet: @escaping (ScrollViewProxy) -> Void,
            onTranscriptChange: @escaping () -> Void,
            onCurrentWordChange: @escaping () -> Void,
            itemView: @escaping (TranscriptItem) -> some View
        ) {
            self.transcript = transcript
            self.currentWord = currentWord
            self.onScrollProxySet = onScrollProxySet
            self.onTranscriptChange = onTranscriptChange
            self.onCurrentWordChange = onCurrentWordChange
            self.itemView = { item in AnyView(itemView(item)) }
        }
        
        var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if transcript.isEmpty {
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
                            ForEach(transcript) { item in
                                itemView(item)
                                    .id(item.id)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .background(Color(.secondarySystemBackground))
                .onAppear {
                    onScrollProxySet(proxy)
                }
                .onChange(of: transcript.count) { _ in
                    onTranscriptChange()
                }
                .onChange(of: currentWord) { _ in
                    onCurrentWordChange()
                }
            }
        }
    }
    
    @ViewBuilder
    private func transcriptItemView(item: TranscriptItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Type indicator
            Circle()
                .fill(typeColor(for: item.type))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            
            // Text content
            Text(item.text)
                .font(fontForType(item.type))
                .foregroundColor(item.isHighlighted ? .primary : .secondary)
                .lineLimit(nil)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(backgroundColor(for: item))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(borderColor(for: item.type), lineWidth: item.isHighlighted ? 2 : 0)
                        )
                )
                .shadow(color: shadowColor(for: item.type).opacity(item.isHighlighted ? 1 : 0), radius: item.isHighlighted ? 8 : 0, x: 0, y: 2)
                .scaleEffect(item.isHighlighted ? 1.02 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: item.isHighlighted)
        }
    }
    
    @ViewBuilder
    private func trialResultCard(trialNumber: Int, response: ItemResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Trial \(trialNumber)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    if let score = response.score {
                        let percentage = score * 100
                        Text("\(String(format: "%.0f", percentage))% Correct")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(scoreColor(score))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                
                Spacer()
                
                // Score Badge
                if let score = response.score {
                    let correctCount = response.correctWords?.count ?? 0
                    let totalCount = response.expectedWords?.count ?? 5
                    
                    VStack(spacing: 2) {
                        Text("\(correctCount)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(scoreColor(score))
                        Text("/ \(totalCount)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(scoreColor(score).opacity(0.15))
                    )
                }
            }
            
            Divider()
            
            // Expected Words
            if let expectedWords = response.expectedWords {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Expected Words")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(expectedWords.enumerated()), id: \.offset) { index, word in
                            wordBadge(word: word, isCorrect: response.correctWords?.contains(word) ?? false)
                        }
                    }
                }
            }
            
            // User Response
            if let transcription = response.responseText, !transcription.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your Response")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    Text(transcription)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(nil)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.secondarySystemBackground))
                        )
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your Response")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    Text("No transcription available")
                        .font(.system(size: 13))
                        .foregroundColor(.orange)
                        .italic()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        )
    }
    
    @ViewBuilder
    private func wordBadge(word: String, isCorrect: Bool) -> some View {
        HStack(spacing: 6) {
            Text(word.capitalized)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isCorrect ? .white : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            if isCorrect {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCorrect ? Color.green : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isCorrect ? Color.green : Color.clear, lineWidth: 2)
        )
    }
    
    // MARK: - Helper Functions
    
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
    
    
    @ViewBuilder
    private var workingMemoryResultsView: some View {
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
                
                if viewModel.workingMemoryResults.isEmpty {
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
                            await viewModel.loadWorkingMemoryResults()
                        }
                    }
                } else {
                    // Results Cards
                    VStack(spacing: 16) {
                        ForEach(Array(viewModel.workingMemoryResults.enumerated()), id: \.element.id) { index, response in
                            trialResultCard(trialNumber: index + 1, response: response)
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
    
    // MARK: - Helper Functions
    
    private func typeColor(for type: TranscriptItemType) -> Color {
        switch type {
        case .instruction: return .blue
        case .word: return .purple
        case .prompt: return .orange
        case .trialAnnouncement: return .green
        case .phaseAnnouncement: return .indigo
        case .digit: return .cyan
        case .letter: return .pink
        case .calculationPrompt: return .orange
        case .sentence: return .orange
        case .fluencyPrompt: return .orange
        }
    }
    
    private func fontForType(_ type: TranscriptItemType) -> Font {
        switch type {
        case .instruction: return .system(size: 14, weight: .regular)
        case .word: return .system(size: 20, weight: .semibold, design: .rounded)
        case .prompt: return .system(size: 15, weight: .medium)
        case .trialAnnouncement: return .system(size: 16, weight: .semibold)
        case .phaseAnnouncement: return .system(size: 16, weight: .semibold)
        case .digit: return .system(size: 24, weight: .semibold, design: .rounded)
        case .letter: return .system(size: 24, weight: .semibold, design: .rounded)
        case .calculationPrompt: return .system(size: 15, weight: .medium)
        case .sentence: return .system(size: 18, weight: .semibold, design: .rounded)
        case .fluencyPrompt: return .system(size: 15, weight: .medium)
        }
    }
    
    private func backgroundColor(for item: TranscriptItem) -> Color {
        if item.isHighlighted {
            switch item.type {
            case .instruction: return Color.blue.opacity(0.15)
            case .word: return Color.purple.opacity(0.2)
            case .prompt: return Color.orange.opacity(0.15)
            case .trialAnnouncement: return Color.green.opacity(0.15)
            case .phaseAnnouncement: return Color.indigo.opacity(0.15)
            case .digit: return Color.cyan.opacity(0.2)
            case .letter: return Color.pink.opacity(0.2)
            case .calculationPrompt: return Color.orange.opacity(0.15)
            case .sentence: return Color.orange.opacity(0.2)
            case .fluencyPrompt: return Color.orange.opacity(0.15)
            }
        } else {
            return Color(.systemBackground)
        }
    }
    
    private func borderColor(for type: TranscriptItemType) -> Color {
        switch type {
        case .instruction: return .blue
        case .word: return .purple
        case .prompt: return .orange
        case .trialAnnouncement: return .green
        case .phaseAnnouncement: return .indigo
        case .digit: return .cyan
        case .letter: return .pink
        case .calculationPrompt: return .orange
        case .sentence: return .orange
        case .fluencyPrompt: return .orange
        }
    }
    
    private func shadowColor(for type: TranscriptItemType) -> Color {
        switch type {
        case .instruction: return .blue
        case .word: return .purple
        case .prompt: return .orange
        case .trialAnnouncement: return .green
        case .phaseAnnouncement: return .indigo
        case .digit: return .cyan
        case .letter: return .pink
        case .calculationPrompt: return .orange
        case .sentence: return .orange
        case .fluencyPrompt: return .orange
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
    
    private func scrollToHighlighted(proxy: ScrollViewProxy, transcript: [TranscriptItem]) {
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
    
    private func scrollToCurrentWord(proxy: ScrollViewProxy, word: String, transcript: [TranscriptItem]) {
        for item in transcript.reversed() {
            if item.text == word, case .word = item.type {
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(item.id, anchor: .center)
                }
                break
            }
        }
    }
    
    // MARK: - Attention Task Views
    
    @ViewBuilder
    private var attentionTaskView: some View {
        if viewModel.currentState == .completed {
            attentionResultsView
        } else {
            attentionTaskActiveView
        }
    }
    
    @ViewBuilder
    private var attentionTaskActiveView: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header with End Task and Back buttons
                VStack(spacing: 12) {
                    HStack {
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
                        
                        Spacer()
                        
                        // End Task Button
                        if viewModel.currentState != .idle && viewModel.currentState != .completed {
                            Button(action: {
                                createTask {
                                    await viewModel.stopTask()
                                    // Small delay to ensure state transition completes
                                    try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
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
                    // Start countdown when recording begins
                    recordingStartTime = Date()
                    // For Serial 7s, use longer duration (5 answers * 8-10 seconds = ~40-50 seconds)
                    // For other phases, use 10 seconds
                    // We'll detect Serial 7s by checking if we're in that phase via transcript
                    let isSerial7s = viewModel.transcript.contains { $0.type == .calculationPrompt }
                    timeRemaining = isSerial7s ? 50.0 : 10.0
                    startCountdown()
                } else {
                    // Stop countdown immediately when not recording
                    stopCountdown()
                    recordingStartTime = nil
                    // Reset based on what phase we might be in
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
                        // Record tap
                        if let attentionTask = taskRunnerInstance.currentTask as? AttentionTask {
                            attentionTask.recordTap(timestamp: Date())
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var isLetterTappingPhase: Bool {
        // Check if we're in letter tapping phase by looking at transcript
        return viewModel.transcript.contains { $0.type == .letter }
    }
    
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
            // Calculate expected A positions from the letter sequence
            let expectedAPositions = expectedWords.enumerated().compactMap { $0.element == "A" ? $0.offset : nil }
            
            // Parse tapped positions from correctWords (stored as strings of indices)
            let tappedPositions = Set(correctWords.compactMap { Int($0) })
            
            // Identify errors:
            // - Missing A's: positions where letter is "A" but not tapped
            // - Incorrect taps: positions that were tapped but letter is not "A"
            let missingAPositions = Set(expectedAPositions).subtracting(tappedPositions)
            let incorrectTapPositions = tappedPositions.subtracting(Set(expectedAPositions))
            let errorPositions = missingAPositions.union(incorrectTapPositions)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Letter Sequence")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                // Show letters with A's highlighted and errors in red - wrap to multiple lines
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
    
    // Helper struct for letter items in ForEach
    private struct LetterItem: Identifiable {
        let id: Int
        let letter: String
        
        init(index: Int, letter: String) {
            self.id = index
            self.letter = letter
        }
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
}

extension TaskRunnerState {
    var description: String {
        switch self {
        case .idle: return "Idle"
        case .presenting: return "Presenting"
        case .recording: return "Recording"
        case .evaluating: return "Evaluating"
        case .completed: return "Completed"
        }
    }
}

