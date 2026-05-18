//
//  NodeInsightSheet.swift
//  Aquinas-iOS
//

import SwiftUI

// MARK: - Node Insight Sheet

struct NodeInsightSheet: View {
    let node: NodeModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                Text(node.conceptLabel)
                    .font(.baskervilleHeading1)
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(node.insights) { insight in
                    InsightTreeInsightCard(insight: insight)
                }
            }
            .padding(24)
        }
        .background(AquinasTheme.Colors.canvas)
    }
}

struct InsightTreeInsightCard: View {
    let insight: InsightModel
    var showsStartConversation: Bool = false
    var onStartConversation: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AquinasTheme.Colors.lightGreen)
                    .sfSymbolDrawOn()

                Text(insight.title)
                    .font(.figtreeHeading1)
                    .foregroundColor(AquinasTheme.Colors.lightGreen)

                Spacer()
            }

            Text(insight.definition)
                .font(.figtreeParagraphLarge)
                .lineSpacing(10)
                .foregroundColor(AquinasTheme.Colors.paragraphText)

            if showsStartConversation {
                Button(action: { onStartConversation?() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Start Conversation")
                            .font(.figtreeHeading3)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .aquinasCapsuleControl()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .parchmentCard(radius: 24, background: AquinasTheme.Colors.componentBackground, border: AquinasTheme.Colors.controlBorder)
    }
}

