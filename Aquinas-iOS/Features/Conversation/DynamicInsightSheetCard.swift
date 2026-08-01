//
//  DynamicInsightSheetCard.swift
//  Aquinas-iOS
//
//  The Insight card shown when a concept link in a model response is tapped. It matches the
//  loaded card on other pages, but shows a simple loading state while the definition is generated.
//

import SwiftUI

struct DynamicInsightSheetCard: View {
    let word: String
    /// nil while the definition is generating; set once ready.
    let concept: ConceptDefinition?
    let isSaved: Bool
    var funStatusText: String? = nil
    var onQuote: () -> Void
    var onFork: () -> Void
    var onToggleSaved: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let concept {
                loadedHeader

                InsightDefinitionsContent(
                    definitions: concept.contextualDefinitions
                )
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AquinasTheme.Colors.lightGreen)

                    Text(funStatusText ?? "Generating relevant definition...")
                        .font(.figtreeParagraph)
                        .foregroundColor(AquinasTheme.Colors.placeholderText)
                        .accessibilityLabel("Generating relevant definition")
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AquinasTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AquinasTheme.Colors.brownBorder, lineWidth: 1)
        )
        .shadow(color: Color(red: 0.13, green: 0.06, blue: 0).opacity(0.15), radius: 24, x: 0, y: 0)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var loadedHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(AquinasTheme.Colors.darkGreen)

            Text(word.capitalized)
                .font(.custom("Figtree-Bold", size: 18))
                .foregroundColor(AquinasTheme.Colors.lightGreen)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer()

            ResponseButtons(
                isSaved: isSaved,
                canQuote: true,
                canFork: true,
                tintColor: AquinasTheme.Colors.placeholderText,
                saveTintColor: AquinasTheme.Colors.accentRed,
                onSave: onToggleSaved,
                onQuote: onQuote,
                onFork: onFork
            )
        }
    }
}

struct InsightDefinitionsContent: View {
    let definitions: [InsightDefinition]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(definitions) { definition in
                InsightDefinitionEntry(
                    context: definition.context,
                    meaning: definition.meaning,
                    showsDistinction: definitions.count > 1
                )
            }
        }
    }
}

private struct InsightDefinitionEntry: View {
    let context: String
    let meaning: String
    let showsDistinction: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsDistinction && !context.isEmpty {
                Text(
                    "In regards to \(context)",
                    comment: "Label describing the subject that gives an Insight definition its meaning."
                )
                .font(.figtreeParagraph)
                .bold()
                .italic()
                .foregroundColor(AquinasTheme.Colors.headingText)
                .fixedSize(horizontal: false, vertical: true)
            }

            Text(meaning)
                .font(.figtreeParagraph)
                .lineSpacing(12)
                .foregroundColor(AquinasTheme.Colors.paragraphText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
