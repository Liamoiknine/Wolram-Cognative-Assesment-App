import SwiftUI

@available(iOS 13.0, *)
struct TrialResultCard: View {
    let trialNumber: Int
    let response: ItemResponse
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trial \(trialNumber)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    if let score = response.score {
                        let percentage = score * 100
                        Text("\(String(format: "%.0f", percentage))% Correct")
                            .font(.subheadline)
                            .foregroundColor(scoreColor(score))
                    }
                }
                
                Spacer()
                
                // Score Badge
                if let score = response.score {
                    let correctCount = response.correctWords?.count ?? 0
                    let totalCount = response.expectedWords?.count ?? 5
                    
                    VStack(spacing: 4) {
                        Text("\(correctCount)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(scoreColor(score))
                        Text("/ \(totalCount)")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(scoreColor(score).opacity(0.15))
                    )
                }
            }
            
            Divider()
            
            // Expected Words
            if let expectedWords = response.expectedWords {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Expected Words")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    HStack(spacing: 8) {
                        ForEach(Array(expectedWords.enumerated()), id: \.offset) { index, word in
                            WordBadge(
                                word: word,
                                isCorrect: response.correctWords?.contains(word) ?? false,
                                isExpected: true
                            )
                        }
                    }
                }
            }
            
            // User Response
            if let transcription = response.responseText, !transcription.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Response")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    Text(transcription)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.secondarySystemBackground))
                        )
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Response")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    Text("No transcription available")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                        .italic()
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
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
}

@available(iOS 13.0, *)
struct WordBadge: View {
    let word: String
    let isCorrect: Bool
    let isExpected: Bool
    
    var body: some View {
        Text(word.capitalized)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(isCorrect ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCorrect ? Color.green : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isCorrect ? Color.green : Color.clear, lineWidth: 2)
            )
    }
}

