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
                    .font(.figtreeDisplay)
                    .lineSpacing(8)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AquinasTheme.Colors.darkGreen)
                    .sfSymbolDrawOn()

                Text(insight.title)
                    .font(.custom("Figtree-Bold", size: 18))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer()
            }

            Text(insight.definition)
                .font(.figtreeParagraph)
                .lineSpacing(12)
                .foregroundColor(AquinasTheme.Colors.paragraphText)
                .fixedSize(horizontal: false, vertical: true)

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
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(AquinasTheme.Colors.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AquinasTheme.Colors.brownBorder, lineWidth: 1)
        )
        .shadow(color: Color(red: 0.13, green: 0.06, blue: 0).opacity(0.15), radius: 24, x: 0, y: 16)
    }
}
