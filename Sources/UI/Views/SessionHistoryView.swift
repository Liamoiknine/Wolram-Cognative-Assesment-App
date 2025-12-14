import SwiftUI

/// View displaying past assessment sessions.
struct SessionHistoryView: View {
    @EnvironmentObject private var dataController: DataController
    
    init(dataController: DataControllerProtocol? = nil) {
        // This init is for testing - in normal use, environment object is used
    }
    
    var body: some View {
        SessionHistoryViewWrapper(dataController: dataController)
    }
}

/// Wrapper that creates the viewModel from environment object
private struct SessionHistoryViewWrapper: View {
    let dataController: DataController
    @StateObject private var viewModel: SessionHistoryViewModel
    
    init(dataController: DataController) {
        self.dataController = dataController
        _viewModel = StateObject(wrappedValue: SessionHistoryViewModel(dataController: dataController))
    }
    
    var body: some View {
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
                    if viewModel.isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(0.9)
                            Text("Loading sessions...")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if let errorMessage = viewModel.errorMessage {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.red)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.red.opacity(0.1))
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    } else if viewModel.sessions.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text("No sessions found")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(viewModel.sessions) { session in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Session \(session.id.uuidString.prefix(8))")
                                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Text(session.status.rawValue.capitalized)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(
                                                Capsule()
                                                    .fill(session.status == .completed ? Color.green : Color.orange)
                                            )
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "clock.fill")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                            Text("Started: \(session.startTime.formatted())")
                                                .font(.system(size: 13))
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        if let endTime = session.endTime {
                                            HStack(spacing: 6) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.secondary)
                                                Text("Ended: \(endTime.formatted())")
                                                    .font(.system(size: 13))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color(.systemBackground))
                                        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 32)
                    }
                }
            }
        }
        .navigationTitle("Session History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadSessions()
        }
    }
}

