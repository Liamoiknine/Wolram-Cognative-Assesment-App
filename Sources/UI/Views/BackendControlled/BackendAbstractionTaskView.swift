import SwiftUI

struct BackendAbstractionTaskView: View {
    @StateObject private var viewModel = BackendAbstractionViewModel()
    
    var body: some View {
        BaseBackendTaskView(
            viewModel: viewModel,
            taskTitle: "Abstraction Task",
            showResults: $viewModel.showResults,
            taskContent: {
                VStack(spacing: 20) {
                    // Trial indicator (only show if trial > 0)
                    if viewModel.trialNumber > 0 {
                        Text("Trial \(viewModel.trialNumber)/2")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    
                    // Content area - show recording countdown or default state
                    if viewModel.isRecording {
                        // Recording countdown (full screen)
                        VStack(spacing: 16) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.red)
                            
                            Text("\(Int(ceil(viewModel.timeRemaining)))")
                                .font(.system(size: 64, weight: .bold, design: .rounded))
                                .foregroundColor(.red)
                                .monospacedDigit()
                            
                            Text("seconds remaining")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Default state - show waveform icon when not recording
                        VStack(spacing: 12) {
                            Image(systemName: "waveform")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                                .opacity(0.3)
                            
                            if !viewModel.statusMessage.isEmpty {
                                Text(viewModel.statusMessage)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            },
            resultsView: { vm in
                BackendAbstractionResultsView(viewModel: vm as! BackendAbstractionViewModel)
            }
        )
    }
}

