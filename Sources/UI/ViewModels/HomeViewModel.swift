import Foundation
import SwiftUI

/// ViewModel for the home screen.
/// Manages navigation state and basic app flow.
class HomeViewModel: ObservableObject {
    @Published var navigationPath = NavigationPath()
    
    func navigateToStartAssessment() {
        navigationPath.append(NavigationDestination.startAssessment)
    }
    
    func navigateToSessionHistory() {
        navigationPath.append(NavigationDestination.sessionHistory)
    }
}

enum NavigationDestination: Hashable {
    case startAssessment
    case sessionHistory
    case taskView
}

