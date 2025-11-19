import SwiftUI

/// Home screen of the cognitive assessment app.
/// Provides navigation to main features.
struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel
    
    init(viewModel: HomeViewModel = HomeViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            VStack(spacing: 20) {
                Text("Cognitive Assessment")
                    .font(.largeTitle)
                    .padding()
                
                Button("Start Assessment") {
                    viewModel.navigateToStartAssessment()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Session History") {
                    viewModel.navigateToSessionHistory()
                }
                .buttonStyle(.bordered)
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
        }
    }
}

