import Foundation
import SwiftUI
import AVFoundation

@MainActor
class BackendAbstractionViewModel: BaseBackendTaskViewModel {
    @Published var results: [EvaluationResult] = []
    @Published var showResults: Bool = false  // Navigate to results when true
    
    // Task-specific configuration
    override var webSocketURL: String {
        return BackendConfig.abstractionURL
    }
    
    override var uploadURL: String {
        return BackendConfig.uploadURL
    }
    
    // MARK: - Task-Specific Methods
    
    override func handleTTSReceived(audio: Data, trialNumber: Int?) {
        print("🔊 BackendAbstractionViewModel: Received TTS audio (trial: \(trialNumber ?? -1))")
        
        // Update trial number
        if let trialNumber = trialNumber {
            self.trialNumber = trialNumber
            self.currentTrialNumber = trialNumber
        }
        
        // Play audio
        _Concurrency.Task {
            do {
                // Don't show "Playing audio..." - just play silently
                try await self.playAudio(audio)
                
                // Signal to backend that audio playback is complete
                await self.signalAudioComplete()
                
                // After audio finishes:
                // - If trial_number is 0 (instruction), signal ready without recording
                // - Otherwise, record and upload actual response
                if self.currentTrialNumber == 0 {
                    print("✅ BackendAbstractionViewModel: Instruction played, signaling ready for trial 1...")
                    // Signal instruction is done by uploading empty data (backend will proceed to trial 1)
                    await self.signalInstructionComplete()
                } else {
                    // Record and upload for actual trials
                    await self.recordAndUpload(trialNumber: self.currentTrialNumber)
                }
                
            } catch {
                print("❌ BackendAbstractionViewModel: Error playing audio: \(error)")
                statusMessage = "Error playing audio: \(error.localizedDescription)"
            }
        }
    }
    
    override func handleEvaluationResult(_ result: EvaluationResult) {
        // Store individual result (backup in case all_results doesn't arrive)
        if !results.contains(where: { $0.trialNumber == result.trialNumber }) {
            results.append(result)
            results.sort { $0.trialNumber < $1.trialNumber }
        }
    }
    
    override func handleAllResults(_ results: [EvaluationResult]) {
        // Store all results
        self.results = results.sorted { $0.trialNumber < $1.trialNumber }
        print("✅ BackendAbstractionViewModel: Stored \(results.count) evaluation results")
        
        // Navigate to results if task is complete
        if currentState == .complete {
            showResults = true
        }
    }
    
    // Override hook method to handle completion navigation
    override func handleTaskStateChanged(state: TaskState, trialNumber: Int?, message: String?) {
        // Navigate to results immediately if we have results and task is complete
        if state == .complete && !results.isEmpty {
            showResults = true
        }
    }
}

// WebSocketClientDelegate is implemented in BaseBackendTaskViewModel
// Task-specific handling is done via handleTTSReceived, handleEvaluationResult, handleAllResults
