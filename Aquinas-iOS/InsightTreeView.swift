//
//  InsightTreeView.swift
//  Aquinas-iOS
//

import SwiftUI
import UIKit

// MARK: - Insight Tree View

struct InsightTreeView: View {
    let insights: [ConceptDefinition]
    var onClose: (() -> Void)?

    @StateObject private var viewModel: InsightTreeViewModel
    @State private var selectedInsight: InsightModel?
    @State private var selectedNode: NodeModel?
    @State private var dockedCardDragY: CGFloat = 0
    @State private var restoreFocusedCameraRequest: Int = 0
    @State private var focusedInsightID: UUID?

    init(insights: [ConceptDefinition], onClose: (() -> Void)? = nil) {
        self.insights = insights
        self.onClose = onClose
        _viewModel = StateObject(wrappedValue: InsightTreeViewModel(insights: insights))
    }

    var body: some View {
        ZStack {
            InsightTreeCanvasView(
                nodes: viewModel.nodes,
                edges: viewModel.edges,
                restoreFocusedCameraRequest: restoreFocusedCameraRequest,
                focusedInsightID: focusedInsightID,
                onNodeTapped: { node in
                    showNodeCard(node)
                },
                onInsightTapped: { insight in
                    showInsightCard(insight)
                },
                onCanvasMoved: {
                    dismissDockedInsight()
                },
                onSuggestConnection: { edge in
                    viewModel.suggestConnection(for: edge)
                },
                onDismissSuggestedNode: { node in
                    viewModel.dismissSuggestedNode(node)
                }
            )
                .ignoresSafeArea()
                .background(AquinasTheme.Colors.canvas)

            if viewModel.nodes.isEmpty {
                EmptyInsightTreeView()
            }

            if let selectedInsight {
                VStack {
                    Spacer()

                    DockedInsightTreeCard(insight: selectedInsight)
                        .offset(y: dockedCardDragY)
                        .gesture(dockedCardDismissGesture)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .transition(.move(edge: .bottom))
                .zIndex(200)
            }

            if let selectedNode {
                VStack {
                    Spacer()

                    DockedNodeTreeCard(
                        node: selectedNode,
                        onSelectInsight: { insight in
                            focusedInsightID = insight.id
                            showInsightCard(insight)
                        }
                    )
                        .offset(y: dockedCardDragY)
                        .gesture(dockedCardDismissGesture)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .transition(.move(edge: .bottom))
                .zIndex(200)
            }

            VStack {
                HStack {
                    if let onClose {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .sfSymbolDrawOn()
                                .aquinasIconControl()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close insights")
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

                Spacer()
            }
        }
        .onChange(of: insights) { oldValue, newValue in
            viewModel.updateInsights(newValue)
            if let selectedInsight,
               !newValue.contains(where: { $0.id == selectedInsight.id }) {
                dismissDockedInsight()
            }
        }
        .sheet(item: $viewModel.selectedSuggestedNode) { node in
            SuggestedInsightSheet(node: node) {
                viewModel.dismissSuggestedNode(node)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(AquinasTheme.Colors.canvas)
        }
    }

    private func showInsightCard(_ insight: InsightModel) {
        playDockedCardHaptic()

        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            dockedCardDragY = 0
            selectedNode = nil
            selectedInsight = insight
        }
    }

    private func showNodeCard(_ node: NodeModel) {
        playDockedCardHaptic()

        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            dockedCardDragY = 0
            selectedInsight = nil
            selectedNode = node
        }
    }

    private var dockedCardDismissGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                dockedCardDragY = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height > 44 || value.predictedEndTranslation.height > 90 {
                    dismissDockedInsight()
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        dockedCardDragY = 0
                    }
                }
            }
    }

    private func dismissDockedInsight() {
        guard selectedInsight != nil || selectedNode != nil else { return }

        playDockedCardHaptic()

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            dockedCardDragY = 0
            selectedInsight = nil
            selectedNode = nil
        }
    }

    private func playDockedCardHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.65)
    }
}

private struct DockedInsightTreeCard: View {
    let insight: InsightModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 8) {
                DockedCardTextBubbleIcon(size: 12, delay: 0.18)

                Text(insight.title)
                    .font(.custom("Figtree-Bold", size: 18))
                    .foregroundColor(AquinasTheme.Colors.darkGreen)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer()

                ResponseButtons(
                    isSaved: true,
                    canCopy: true,
                    canFork: true,
                    copyText: insight.definition,
                    onSave: {},
                    onFork: {}
                )
            }

            Text(insight.definition)
                .font(.figtreeParagraph)
                .lineSpacing(12)
                .foregroundColor(AquinasTheme.Colors.bodyText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 251 / 255, green: 244 / 255, blue: 231 / 255))
        .clipShape(RoundedRectangle(cornerRadius: 48, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .stroke(AquinasTheme.Colors.brownBorder, lineWidth: 1)
        )
    }
}

private struct DockedNodeTreeCard: View {
    let node: NodeModel
    var onSelectInsight: (InsightModel) -> Void

    private var summaryText: String {
        let titles = node.insights.prefix(3).map(\.title)
        guard !titles.isEmpty else {
            return "\(node.conceptLabel) is a developing subject in this insight map."
        }

        return "\(node.conceptLabel) gathers related insights around \(titles.joined(separator: ", "))."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(node.conceptLabel)
                    .font(.custom("Figtree-Bold", size: 18))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)

                Spacer()

                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable.opacity(0.72))
            }

            Text(summaryText)
                .font(.figtreeParagraph)
                .lineSpacing(8)
                .foregroundColor(AquinasTheme.Colors.bodyText)
                .lineLimit(3)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(node.insights.enumerated()), id: \.element.id) { index, insight in
                    Button {
                        onSelectInsight(insight)
                    } label: {
                        HStack(spacing: 12) {
                            DockedCardTextBubbleIcon(size: 14, delay: 0.18 + (Double(index) * 0.04))

                            Text(insight.title)
                                .font(.custom("Figtree-Bold", size: 16))
                                .foregroundColor(AquinasTheme.Colors.darkGreen)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)

                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 251 / 255, green: 244 / 255, blue: 231 / 255))
        .clipShape(RoundedRectangle(cornerRadius: 48, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .stroke(AquinasTheme.Colors.brownBorder, lineWidth: 1)
        )
    }
}

private struct DockedCardTextBubbleIcon: View {
    let size: CGFloat
    var delay: TimeInterval = 0
    @State private var isVisible = false

    var body: some View {
        Image(systemName: "text.bubble.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(AquinasTheme.Colors.darkGreen)
            .scaleEffect(isVisible ? 1 : 0.86)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                isVisible = false
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                        isVisible = true
                    }
                }
            }
    }
}

private struct EmptyInsightTreeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(AquinasTheme.Colors.lightGreen)
                .sfSymbolDrawOn()

            Text("Insights will gather here")
                .font(.baskervilleHeading1)
                .foregroundColor(AquinasTheme.Colors.primaryReadable)

            Text("Save insights from conversations to begin forming Theo's map of connected ideas.")
                .font(.figtreeParagraph)
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .foregroundColor(AquinasTheme.Colors.paragraphText)
                .frame(maxWidth: 280)
        }
        .padding(24)
    }
}
