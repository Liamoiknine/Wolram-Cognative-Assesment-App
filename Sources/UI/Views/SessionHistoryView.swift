import SwiftUI

/// View displaying past assessment sessions.
struct SessionHistoryView: View {
    @StateObject private var viewModel: SessionHistoryViewModel
    
    init(dataController: DataControllerProtocol? = nil) {
        // In a real app, this would be injected via environment
        let dataController = dataController ?? DataController()
        _viewModel = StateObject(wrappedValue: SessionHistoryViewModel(dataController: dataController))
    }
    
    var body: some View {
        VStack {
            if viewModel.isLoading {
                ProgressView()
                    .padding()
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            } else if viewModel.sessions.isEmpty {
                Text("No sessions found")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                List(viewModel.sessions) { session in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Session \(session.id.uuidString.prefix(8))")
                            .font(.headline)
                        Text("Started: \(session.startTime.formatted())")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let endTime = session.endTime {
                            Text("Ended: \(endTime.formatted())")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text("Status: \(session.status.rawValue)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Session History")
        .task {
            await viewModel.loadSessions()
        }
    }
}

