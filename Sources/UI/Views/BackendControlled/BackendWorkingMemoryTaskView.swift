import SwiftUI

struct BackendWorkingMemoryTaskView: View {
    @StateObject private var viewModel = BackendWorkingMemoryViewModel()
    @State private var scrollProxy: ScrollViewProxy?
    
    var body: some View {
        BaseBackendTaskView(
            viewModel: viewModel,
            taskTitle: "Working Memory Task",
            showResults: $viewModel.showResults,
            taskContent: {
                VStack(spacing: 0) {
                    // Trial number indicator (shown when not in instruction phase)
                    if viewModel.trialNumber > 0 {
                        Text("Trial \(viewModel.trialNumber)/2")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    }
                    
                    // Content area - show recording countdown or messages
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
                        // Scrollable message list
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(spacing: 12) {
                                    if viewModel.messages.isEmpty {
                                        // Empty state
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
                                        // Display all messages
                                        ForEach(viewModel.messages) { message in
                                            MessageBubble(text: message.text)
                                                .id(message.id)
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                            }
                            .onAppear {
                                scrollProxy = proxy
                            }
                            .onChange(of: viewModel.messages.count) { _ in
                                // Auto-scroll to latest message when new one appears
                                if let lastMessage = viewModel.messages.last {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            },
            resultsView: { vm in
                BackendWorkingMemoryResultsView(viewModel: vm as! BackendWorkingMemoryViewModel)
            }
        )
    }
}

/// Unified message bubble component
struct MessageBubble: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Message content
            Text(text)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                )
        }
    }
}
