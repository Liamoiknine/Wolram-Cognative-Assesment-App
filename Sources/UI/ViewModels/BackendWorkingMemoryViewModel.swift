import Foundation
import SwiftUI
import AVFoundation

/// State machine for Working Memory task
/// Only one state can be active at a time
enum WorkingMemoryState: String, Equatable {
    case idle = "idle"
    case instructionDisplay = "instruction_display"
    case instructionPlaying = "instruction_playing"
    case trialIntroPlaying = "trial_intro_playing"
    case wordsDisplaying = "words_displaying"
    case wordsPlaying = "words_playing"
    case promptPlaying = "prompt_playing"
    case beepStart = "beep_start"
    case recording = "recording"
    case beepEnd = "beep_end"
    case recordingComplete = "recording_complete"
    case completionPlaying = "completion_playing"
    case complete = "complete"
}

/// Message model for Working Memory task
struct WorkingMemoryMessage: Identifiable, Equatable {
    let id: UUID
    let text: String
    let timestamp: Date
    
    init(text: String) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
    }
}

@MainActor
class BackendWorkingMemoryViewModel: BaseBackendTaskViewModel {
    @Published var results: [EvaluationResult] = []
    @Published var showResults: Bool = false
    @Published var messages: [WorkingMemoryMessage] = []  // All messages in order
    @Published var workingMemoryState: WorkingMemoryState = .idle  // State machine tracking
    
    // Guards to prevent duplicate actions
    private var hasPlayedStartBeep: Bool = false
    private var hasPlayedEndBeep: Bool = false
    private var hasStartedRecording: Bool = false
    
    // Task-specific configuration
    override var webSocketURL: String {
        return BackendConfig.workingMemoryURL
    }
    
    override var uploadURL: String {
        return BackendConfig.workingMemoryUploadURL
    }
    
    // MARK: - State Transition Handler
    
    func handleStateTransition(phase: String, trialNumber: Int?, message: String?) {
        guard let newState = WorkingMemoryState(rawValue: phase) else {
            print("⚠️ BackendWorkingMemoryViewModel: Unknown state phase: \(phase)")
            return
        }
        
        print("🔄 BackendWorkingMemoryViewModel: State transition: \(workingMemoryState.rawValue) → \(newState.rawValue)")
        
        // Only transition if we're in a valid previous state (or idle)
        let previousState = workingMemoryState
        workingMemoryState = newState
        
        // Handle state-specific actions
        switch newState {
        case .instructionDisplay:
            // Add instruction message
            if let message = message {
                messages.append(WorkingMemoryMessage(text: message))
            }
            
        case .instructionPlaying:
            // Instruction message already added, just wait for TTS
            break
            
        case .trialIntroPlaying:
            // Add trial intro message (trial 2 only)
            if let message = message {
                messages.append(WorkingMemoryMessage(text: message))
            }
            
        case .wordsDisplaying:
            // Words will be added via word_display messages
            break
            
        case .wordsPlaying:
            // Words are being played, wait for audio_complete
            break
            
        case .promptPlaying:
            // Add prompt message
            if let message = message {
                messages.append(WorkingMemoryMessage(text: message))
            }
            break
            
        case .beepStart:
            // Play start beep (only once)
            if !hasPlayedStartBeep {
                hasPlayedStartBeep = true
                _Concurrency.Task {
                    await self._playStartBeep()
                    // Signal beep complete to backend (via audio_complete)
                    await self.signalAudioComplete()
                }
            }
            
        case .recording:
            // Start recording (only once, only if we just transitioned from beep_start)
            if previousState == .beepStart && !hasStartedRecording {
                hasStartedRecording = true
                if let trialNumber = trialNumber {
                    _Concurrency.Task {
                        await self.recordAndUpload(trialNumber: trialNumber)
                    }
                }
            }
            
        case .beepEnd:
            // Play end beep (only once) - this happens after recording completes
            if !hasPlayedEndBeep {
                hasPlayedEndBeep = true
                _Concurrency.Task {
                    await self._playEndBeep()
                    // Signal beep complete to backend
                    await self.signalAudioComplete()
                }
            }
            
        case .recordingComplete:
            // Recording is complete, reset guards for next trial
            // CRITICAL: Reset all guards here to allow next trial to proceed
            print("🔄 BackendWorkingMemoryViewModel: Resetting guards for next trial")
            hasPlayedStartBeep = false
            hasPlayedEndBeep = false
            hasStartedRecording = false
            
        case .completionPlaying:
            // Add completion message
            if let message = message {
                messages.append(WorkingMemoryMessage(text: message))
            }
            break
            
        case .complete:
            // Task complete - update base class currentState
            currentState = .complete
            // Navigate immediately - all_results should arrive right after this
            // But if results are already available, navigate now
            if !results.isEmpty {
                showResults = true
                print("✅ BackendWorkingMemoryViewModel: Task complete state transition received, navigating to results (results already available)")
            } else {
                // Wait for all_results - it will trigger navigation
                print("⚠️ BackendWorkingMemoryViewModel: Task complete state transition received, waiting for all_results message to navigate...")
            }
            break
            
        case .idle:
            // Reset all guards
            hasPlayedStartBeep = false
            hasPlayedEndBeep = false
            hasStartedRecording = false
            messages = []
        }
    }
    
    // MARK: - Task-Specific Methods
    
    override func handleTTSReceived(audio: Data, trialNumber: Int?) {
        print("🔊 BackendWorkingMemoryViewModel: Received TTS audio (state: \(workingMemoryState.rawValue), trial: \(trialNumber ?? -1))")
        
        // Update trial number
        if let trialNumber = trialNumber {
            self.trialNumber = trialNumber
            self.currentTrialNumber = trialNumber
        }
        
        // Only play audio if we're in a state that expects TTS
        let shouldPlayAudio = workingMemoryState == .instructionPlaying ||
                             workingMemoryState == .trialIntroPlaying ||
                             workingMemoryState == .wordsPlaying ||
                             workingMemoryState == .promptPlaying ||
                             workingMemoryState == .completionPlaying
        
        guard shouldPlayAudio else {
            print("⚠️ BackendWorkingMemoryViewModel: Received TTS but not in audio-playing state (current: \(workingMemoryState.rawValue))")
            return
        }
        
        // Play audio sequentially
        _Concurrency.Task {
            do {
                // Play audio and wait for it to complete
                try await self.playAudio(audio)
                print("✅ BackendWorkingMemoryViewModel: Audio playback finished")
                
                // Signal to backend that audio playback is complete
                await self.signalAudioComplete()
                
                // Special handling for instruction: signal ready for trial 1
                if self.currentTrialNumber == 0 && self.workingMemoryState == .instructionPlaying {
                    print("✅ BackendWorkingMemoryViewModel: Instruction played, signaling ready for trial 1...")
                    await self.signalInstructionComplete()
                }
                
            } catch {
                print("❌ BackendWorkingMemoryViewModel: Error playing audio: \(error)")
                statusMessage = "Error playing audio: \(error.localizedDescription)"
            }
        }
    }
    
    override func handleWordDisplayReceived(word: String, trialNumber: Int, wordIndex: Int) {
        // Only update word display if we're in words_displaying state
        guard workingMemoryState == .wordsDisplaying else {
            print("⚠️ BackendWorkingMemoryViewModel: Received word display but not in words_displaying state (current: \(workingMemoryState.rawValue))")
            return
        }
        
        // Add word as a message
        if !word.isEmpty {
            messages.append(WorkingMemoryMessage(text: word))
            print("📺 BackendWorkingMemoryViewModel: Added word message: '\(word)' (trial: \(trialNumber), index: \(wordIndex))")
        } else {
            print("📺 BackendWorkingMemoryViewModel: Word presentation complete")
        }
    }
    
    override func handleEvaluationResult(_ result: EvaluationResult) {
        // Guard: Only store results for trials 1 and 2, and only once per trial
        guard result.trialNumber >= 1 && result.trialNumber <= 2 else {
            print("⚠️ BackendWorkingMemoryViewModel: Invalid trial number for result: \(result.trialNumber)")
            return
        }
        
        // Check if we already have a result for this trial
        if results.contains(where: { $0.trialNumber == result.trialNumber }) {
            print("⚠️ BackendWorkingMemoryViewModel: Trial \(result.trialNumber) result already stored, skipping duplicate")
            return
        }
        
        // Store individual result (backup in case all_results doesn't arrive)
        results.append(result)
        results.sort { $0.trialNumber < $1.trialNumber }
        print("✅ BackendWorkingMemoryViewModel: Stored result for trial \(result.trialNumber) (total: \(results.count))")
        
        // If task is already complete and we have both trial results, navigate
        if (workingMemoryState == .complete || currentState == .complete) && results.count >= 2 {
            showResults = true
            print("✅ BackendWorkingMemoryViewModel: Task complete and all results received via individual messages, navigating to results")
        }
    }
    
    override func handleAllResults(_ results: [EvaluationResult]) {
        // Guard: Only store results for trials 1 and 2, filter out duplicates and invalid trials
        let validResults = results
            .filter { $0.trialNumber >= 1 && $0.trialNumber <= 2 }
            .reduce(into: [Int: EvaluationResult]()) { dict, result in
                // Only keep the first result for each trial (prevent duplicates)
                if dict[result.trialNumber] == nil {
                    dict[result.trialNumber] = result
                } else {
                    print("⚠️ BackendWorkingMemoryViewModel: Duplicate result for trial \(result.trialNumber), keeping first")
                }
            }
            .values
            .sorted { $0.trialNumber < $1.trialNumber }
        
        self.results = Array(validResults)
        print("✅ BackendWorkingMemoryViewModel: Stored \(self.results.count) evaluation results (filtered from \(results.count))")
        
        // CRITICAL: all_results message means task is complete - navigate immediately
        // This is the definitive completion signal from backend
        // Update state to complete if not already
        if workingMemoryState != .complete {
            workingMemoryState = .complete
            currentState = .complete
        }
        // Navigate immediately regardless of results count (user should see results page even if empty)
        showResults = true
        print("✅ BackendWorkingMemoryViewModel: All results received - NAVIGATING TO RESULTS NOW (results count: \(self.results.count))")
    }
    
    // Override to handle state transitions
    override func handleTaskStateChanged(state: TaskState, trialNumber: Int?, message: String?) {
        // When task_state message arrives with complete, update state
        // Navigation will be triggered by all_results message (definitive signal)
        if state == .complete {
            workingMemoryState = .complete
            if !results.isEmpty {
                showResults = true
                print("✅ BackendWorkingMemoryViewModel: Task state complete, navigating to results (results already available)")
            } else {
                print("⚠️ BackendWorkingMemoryViewModel: Task state complete, waiting for all_results message...")
            }
        }
    }
    
    // Override recordAndUpload to reset guards after recording
    override func recordAndUpload(trialNumber: Int) async {
        // Call parent implementation
        await super.recordAndUpload(trialNumber: trialNumber)
        
        // After recording completes, signal recording_complete state
        // (This will be sent by backend, but we can also handle it here)
        // The backend will send beep_end and recording_complete transitions
    }
    
    // Override to handle state transitions
    override func handleStateTransitionReceived(phase: String, trialNumber: Int?, message: String?) {
        handleStateTransition(phase: phase, trialNumber: trialNumber, message: message)
    }
}
