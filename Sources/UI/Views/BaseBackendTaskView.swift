import SwiftUI

/// Base view for backend-controlled tasks
/// Provides common UI patterns (header, timer, status) while allowing task-specific content
struct BaseBackendTaskView<ViewModel: BaseBackendTaskViewModel, Content: View, ResultsView: View>: View {
    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss
    
    let taskTitle: String
    let showResults: Binding<Bool>
    @ViewBuilder var taskContent: () -> Content
    @ViewBuilder var resultsView: (ViewModel) -> ResultsView
    
    var body: some View {
        GeometryReader { geometry in
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
                
                VStack(spacing: 0) {
                    // Header - starts at absolute top
                    headerView
                        .padding(.horizontal, 24)
                        .padding(.top, geometry.safeAreaInsets.top)
                        .padding(.bottom, 16)
                        .frame(maxWidth: .infinity)
                        .background(
                            Color(.systemBackground)
                                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                        )
                    
                    // Main content area
                    mainContentView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            _Concurrency.Task {
                await viewModel.startTask()
            }
        }
        .onDisappear {
            _Concurrency.Task {
                await viewModel.stopTask()
            }
        }
        .fullScreenCover(isPresented: showResults) {
            resultsView(viewModel)
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: {
                    _Concurrency.Task {
                        await viewModel.stopTask()
                        dismiss()
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
                
                // Connection status
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isConnected ? "Connected" : "Disconnected")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            
            Text(taskTitle)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
        }
    }
    
    // MARK: - Main Content View
    
    private var mainContentView: some View {
        VStack(spacing: 24) {
            // Don't show completion view if we're navigating to results
            // The fullScreenCover will handle the navigation
            if viewModel.currentState == .complete && !showResults.wrappedValue {
                // Completion view (shown only if navigation hasn't been triggered)
                completionView
            } else {
                // Active task view (or results navigation is in progress)
                activeTaskView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var completionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            
            Text("Task Completed")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            
            Text("You've completed the task.")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var activeTaskView: some View {
        // Task-specific content (handles all UI including recording, status, etc.)
        taskContent()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
    }
}

