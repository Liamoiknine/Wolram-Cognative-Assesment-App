import SwiftUI

struct BackendAbstractionResultsView: View {
    @ObservedObject var viewModel: BackendAbstractionViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    // Header - starts at absolute top
                    VStack(spacing: 12) {
                        HStack {
                            Button(action: {
                                dismiss()
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
                        }
                        
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.green)
                            
                            Text("Task Completed")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        
                        Text("Review your results below")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        // Total Score
                        if !viewModel.results.isEmpty {
                            let correctCount = viewModel.results.filter { $0.isCorrect }.count
                            VStack(spacing: 4) {
                                Text("Total Score")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                Text("\(correctCount)/\(viewModel.results.count)")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(scoreColor(Double(correctCount) / Double(viewModel.results.count)))
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, geometry.safeAreaInsets.top)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground))
                
                if viewModel.results.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading results...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    // Results Cards
                    VStack(spacing: 16) {
                        ForEach(Array(viewModel.results.enumerated()), id: \.element.trialNumber) { index, result in
                            resultCard(trialNumber: result.trialNumber, result: result)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 20)
                    
                    // Back Button at Bottom
                    Button(action: {
                        dismiss()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Back to Dashboard")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.green)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(.secondarySystemBackground))
    }
    
    private func resultCard(trialNumber: Int, result: EvaluationResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trial \(trialNumber)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Group {
                        if let word1 = result.word1, let word2 = result.word2 {
                            Text("Words: \(word1) and \(word2)")
                        } else {
                            Text("Words: N/A")
                        }
                    }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Score Badge
                VStack(spacing: 3) {
                    Image(systemName: result.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(result.isCorrect ? .green : .red)
                    Text(result.isCorrect ? "Correct" : "Incorrect")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // Response Details
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Response")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                Text(result.transcript)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Category
            VStack(alignment: .leading, spacing: 8) {
                Text("Category Identified")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                Text((result.category ?? "").isEmpty ? "None" : (result.category ?? "").capitalized)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
            }
            
            // Confidence
            if result.confidence > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Confidence")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    HStack(spacing: 8) {
                        ProgressView(value: result.confidence, total: 1.0)
                            .tint(confidenceColor(result.confidence))
                        Text("\(Int(result.confidence * 100))%")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Notes
            if !result.notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    Text(result.notes)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
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
    
    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.8 {
            return .green
        } else if confidence >= 0.5 {
            return .orange
        } else {
            return .red
        }
    }
}

