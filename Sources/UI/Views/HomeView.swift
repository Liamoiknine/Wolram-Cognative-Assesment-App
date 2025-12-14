import SwiftUI

/// Helper function to create a Swift concurrency Task.
/// Uses _Concurrency.Task to explicitly reference Swift's concurrency Task type.
fileprivate func createTask(_ operation: @escaping () async -> Void) {
    _Concurrency.Task {
        await operation()
    }
}

/// Home screen of the cognitive assessment app.
/// Provides navigation to main features.
struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel
    
    init(viewModel: HomeViewModel = HomeViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            ZStack {
                // Background gradient
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
                    VStack(spacing: 0) {
                        // Header Section
                        VStack(spacing: 16) {
                            // App Icon/Logo
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.2)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 70, height: 70)
                                
                                Image(systemName: "brain.head.profile")
                                    .font(.system(size: 35, weight: .medium))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.blue, .purple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                            
                            Text("Cognitive Assessment")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            
                            Text("Evaluate working memory and cognitive function")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        .padding(.bottom, 32)
                        
                        // Action Cards
                        VStack(spacing: 16) {
                            // Start Assessment Card
                            Button(action: {
                                viewModel.navigateToStartAssessment()
                            }) {
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Start Assessment")
                                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                        
                                        Text("Begin a new cognitive test")
                                            .font(.system(size: 13, weight: .regular))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(Color(.systemBackground))
                                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
                                )
                            }
                            .buttonStyle(.plain)
                            
                            // Session History Card
                            Button(action: {
                                viewModel.navigateToSessionHistory()
                            }) {
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Session History")
                                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                        
                                        Text("View past assessment results")
                                            .font(.system(size: 13, weight: .regular))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(Color(.systemBackground))
                                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationDestination(for: NavigationDestination.self) { destination in
                switch destination {
                case .startAssessment:
                    StartAssessmentView()
                case .sessionHistory:
                    SessionHistoryView()
                case .taskView:
                    TaskView()
                }
            }
            .onAppear {
                print("✅ HomeView: View appeared")
            }
        }
    }
}

