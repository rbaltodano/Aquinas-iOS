//
//  SuggestedInsightSheet.swift
//  Aquinas-iOS
//

import SwiftUI

// MARK: - Suggested Insight Sheet

struct SuggestedInsightSheet: View {
    let node: NodeModel
    var onDismissSuggestedNode: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(node.conceptLabel)
                            .font(.figtreeDisplay)
                            .lineSpacing(8)
                            .foregroundColor(AquinasTheme.Colors.primaryReadable)

                        Text("Suggested connection")
                            .font(.figtreeParagraph)
                            .foregroundColor(AquinasTheme.Colors.paragraphText)
                    }

                    Spacer()

                    Button(action: onDismissSuggestedNode) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .aquinasIconControl()
                    }
                    .buttonStyle(.plain)
                }

                ForEach(node.suggestedInsights ?? node.insights) { insight in
                    InsightTreeInsightCard(
                        insight: insight,
                        showsStartConversation: true,
                        onStartConversation: {}
                    )
                }
            }
            .padding(24)
        }
        .background(AquinasTheme.Colors.canvas)
    }
}
