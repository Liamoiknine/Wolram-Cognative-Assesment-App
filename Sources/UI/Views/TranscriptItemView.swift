import SwiftUI

@available(iOS 13.0, *)
struct TranscriptItemView: View {
    let item: TranscriptItem
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Type indicator
            Circle()
                .fill(typeColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            
            // Text content
            Text(item.text)
                .font(fontForType)
                .foregroundColor(item.isHighlighted ? .primary : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(backgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(borderColor, lineWidth: item.isHighlighted ? 2 : 0)
                        )
                )
                .shadow(color: shadowColor, radius: item.isHighlighted ? 8 : 0, x: 0, y: 2)
                .scaleEffect(item.isHighlighted ? 1.02 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: item.isHighlighted)
        }
    }
    
    private var typeColor: Color {
        switch item.type {
        case .instruction:
            return .blue
        case .word:
            return .purple
        case .prompt:
            return .orange
        case .trialAnnouncement:
            return .green
        case .phaseAnnouncement:
            return .indigo
        case .digit:
            return .cyan
        case .letter:
            return .pink
        case .calculationPrompt:
            return .orange
        case .sentence:
            return .orange
        case .fluencyPrompt:
            return .orange
        }
    }
    
    private var fontForType: Font {
        switch item.type {
        case .instruction:
            return .system(size: 15, weight: .regular)
        case .word:
            return .system(size: 24, weight: .semibold, design: .rounded)
        case .prompt:
            return .system(size: 16, weight: .medium)
        case .trialAnnouncement:
            return .system(size: 17, weight: .semibold)
        case .phaseAnnouncement:
            return .system(size: 16, weight: .semibold)
        case .digit:
            return .system(size: 24, weight: .semibold, design: .rounded)
        case .letter:
            return .system(size: 24, weight: .semibold, design: .rounded)
        case .calculationPrompt:
            return .system(size: 16, weight: .medium)
        case .sentence:
            return .system(size: 18, weight: .semibold, design: .rounded)
        case .fluencyPrompt:
            return .system(size: 16, weight: .medium)
        }
    }
    
    private var backgroundColor: Color {
        if item.isHighlighted {
            switch item.type {
            case .instruction:
                return Color.blue.opacity(0.15)
            case .word:
                return Color.purple.opacity(0.2)
            case .prompt:
                return Color.orange.opacity(0.15)
            case .trialAnnouncement:
                return Color.green.opacity(0.15)
            case .phaseAnnouncement:
                return Color.indigo.opacity(0.15)
            case .digit:
                return Color.cyan.opacity(0.2)
            case .letter:
                return Color.pink.opacity(0.2)
            case .calculationPrompt:
                return Color.orange.opacity(0.15)
            case .sentence:
                return Color.orange.opacity(0.2)
            case .fluencyPrompt:
                return Color.orange.opacity(0.15)
            }
        } else {
            return Color(.systemBackground)
        }
    }
    
    private var borderColor: Color {
        switch item.type {
        case .instruction:
            return .blue
        case .word:
            return .purple
        case .prompt:
            return .orange
        case .trialAnnouncement:
            return .green
        case .phaseAnnouncement:
            return .indigo
        case .digit:
            return .cyan
        case .letter:
            return .pink
        case .calculationPrompt:
            return .orange
        case .sentence:
            return .orange
        case .fluencyPrompt:
            return .orange
        }
    }
    
    private var shadowColor: Color {
        switch item.type {
        case .instruction:
            return .blue.opacity(0.3)
        case .word:
            return .purple.opacity(0.3)
        case .prompt:
            return .orange.opacity(0.3)
        case .trialAnnouncement:
            return .green.opacity(0.3)
        case .phaseAnnouncement:
            return .indigo.opacity(0.3)
        case .digit:
            return .cyan.opacity(0.3)
        case .letter:
            return .pink.opacity(0.3)
        case .calculationPrompt:
            return .orange.opacity(0.3)
        case .sentence:
            return .orange.opacity(0.3)
        case .fluencyPrompt:
            return .orange.opacity(0.3)
        }
    }
}

