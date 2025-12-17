import SwiftUI

struct BackendWorkingMemoryResultsView: View {
    @ObservedObject var viewModel: BackendWorkingMemoryViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Working Memory Task")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        
                        Text("Results")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)
                    
                    // Results for each trial
                    if viewModel.results.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Loading results...")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 40)
                    } else {
                        // Show total score summary
                        totalScoreSummary
                            .padding(.bottom, 8)
                        
                        // Results for each trial (sorted by trial number, only trials 1 and 2)
                        ForEach(viewModel.results
                            .filter { $0.trialNumber >= 1 && $0.trialNumber <= 2 }
                            .sorted { $0.trialNumber < $1.trialNumber }, id: \.trialNumber) { result in
                            trialResultCard(trialNumber: result.trialNumber, result: result)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func trialResultCard(trialNumber: Int, result: EvaluationResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Trial header
            HStack {
                Text("Trial \(trialNumber)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                
                Spacer()
                
                // Score badge - use actual correct_words count (most reliable)
                if let words = result.words {
                    let totalWords = words.count
                    let correctCount = result.correctWords?.count ?? 0
                    // Calculate score from actual count if score doesn't match
                    let actualScore = totalWords > 0 ? Double(correctCount) / Double(totalWords) : 0.0
                    let displayScore = result.score ?? actualScore
                    
                    HStack(spacing: 4) {
                        Text("\(correctCount)/\(totalWords)")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(scoreColor(displayScore))
                        
                        Image(systemName: displayScore >= 0.8 ? "checkmark.circle.fill" : displayScore >= 0.5 ? "exclamationmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(scoreColor(displayScore))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(scoreColor(displayScore).opacity(0.1))
                    )
                }
            }
            
            Divider()
            
            // Expected words
            if let words = result.words, !words.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Expected Words")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    Text(words.joined(separator: ", "))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.primary)
                }
            }
            
            // Correct words
            if let correctWords = result.correctWords {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Correctly Recalled")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    if correctWords.isEmpty {
                        Text("None")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        Text(correctWords.joined(separator: ", "))
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.green)
                    }
                }
            }
            
            // Transcript
            if !result.transcript.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Response")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    Text(result.transcript)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.primary)
                        .italic()
                }
            }
            
            // Notes
            if !result.notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    Text(result.notes)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
    
    private func scoreColor(_ score: Double) -> Color {
        if score >= 0.8 {
            return .green
        } else if score >= 0.5 {
            return .orange
        } else {
            return .red
        }
    }
    
    // Total score summary
    private var totalScoreSummary: some View {
        VStack(spacing: 12) {
            Text("Overall Score")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            // Calculate total score using actual correct_words count (most reliable)
            // Filter to only trials 1 and 2 to ensure max score is always 10 (5 words × 2 trials)
            let validResults = viewModel.results.filter { $0.trialNumber >= 1 && $0.trialNumber <= 2 }
            
            let totalCorrect = validResults.compactMap { result -> Int? in
                guard let words = result.words else { return nil }
                // Use actual correct_words count, or calculate from score if not available
                if let correctWords = result.correctWords {
                    return correctWords.count
                } else if let score = result.score {
                    return Int(round(score * Double(words.count)))
                }
                return 0
            }.reduce(0, +)
            
            // Max score should always be 10 (5 words per trial × 2 trials)
            // But calculate from actual results to be safe
            let maxScore = validResults.compactMap { $0.words?.count }.reduce(0, +)
            // Ensure max score is at most 10 (in case of duplicates)
            let finalMaxScore = min(maxScore, 10)
            
            if finalMaxScore > 0 {
                let overallScore = Double(totalCorrect) / Double(finalMaxScore)
                HStack(spacing: 8) {
                    Text("\(totalCorrect)/\(finalMaxScore)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(scoreColor(overallScore))
                    
                    Image(systemName: overallScore >= 0.8 ? "checkmark.circle.fill" : overallScore >= 0.5 ? "exclamationmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(scoreColor(overallScore))
                }
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
}

