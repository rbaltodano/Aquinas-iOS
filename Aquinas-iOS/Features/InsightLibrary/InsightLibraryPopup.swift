//
//  InsightLibraryPopup.swift
//  Aquinas-iOS
//

import SwiftUI

// MARK: - Insight Library Popup

struct InsightLibraryPopup: View {
    let currentConversationInsights: [ConceptDefinition]
    let allInsights: [ConceptDefinition]
    @Binding var savedInsights: [ConceptDefinition]
    var onQuote: (ConceptDefinition) -> Void
    var onFork: (ConceptDefinition) -> Void
    var onToggleSaved: (ConceptDefinition) -> Void

    @State private var selectedScope: InsightLibraryScope = .currentConversation
    @State private var selectedIndex: Int = 0
    @State private var dragOffset: CGFloat = 0

    private var visibleInsights: [ConceptDefinition] {
        switch selectedScope {
        case .currentConversation:
            return currentConversationInsights
        case .all:
            return allInsights
        }
    }

    private var pageCount: Int {
        visibleInsights.count
    }

    var body: some View {
        VStack(spacing: 24) {
            InsightLibraryScopeTabs(selectedScope: $selectedScope)

            if visibleInsights.isEmpty {
                InsightLibraryEmptyState(scope: selectedScope)
                    .frame(maxWidth: .infinity)
            } else {
                ZStack {
                    ForEach(Array(visibleInsights.enumerated()), id: \.element.id) { index, insight in
                        InsightLibraryCard(
                            insight: insight,
                            isSaved: isSaved(insight),
                            onQuote: { onQuote(insight) },
                            onFork: { onFork(insight) },
                            onToggleSaved: { onToggleSaved(insight) }
                        )
                        .frame(maxWidth: 315)
                        .offset(x: CGFloat(index - selectedIndex) * 339 + dragOffset)
                        .opacity(abs(index - selectedIndex) <= 1 ? 1 : 0)
                        .allowsHitTesting(index == selectedIndex)
                    }
                }
                .frame(maxWidth: .infinity)
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            dragOffset = value.translation.width
                        }
                        .onEnded { value in
                            if value.translation.width < -42 {
                                showNextInsight()
                            } else if value.translation.width > 42 {
                                showPreviousInsight()
                            }
                            withAnimation(.insightCardBounce) {
                                dragOffset = 0
                            }
                        }
                )
                .animation(.insightCardBounce, value: selectedIndex)

                InsightLibraryPager(
                    selectedIndex: selectedIndex,
                    pageCount: pageCount,
                    onPrevious: showPreviousInsight,
                    onNext: showNextInsight
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(AquinasTheme.Colors.canvas)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: InsightLibraryPopupHeightKey.self,
                    value: geometry.size.height
                )
            }
        )
        .onChange(of: selectedScope) { oldValue, newValue in
            selectedIndex = 0
            dragOffset = 0
        }
        .onChange(of: pageCount) { oldValue, newValue in
            selectedIndex = min(selectedIndex, max(0, newValue - 1))
        }
    }

    private func isSaved(_ insight: ConceptDefinition) -> Bool {
        savedInsights.contains { $0.word.caseInsensitiveCompare(insight.word) == .orderedSame }
    }

    private func showPreviousInsight() {
        guard pageCount > 0 else { return }
        withAnimation(.insightCardBounce) {
            selectedIndex = max(0, selectedIndex - 1)
        }
    }

    private func showNextInsight() {
        guard pageCount > 0 else { return }
        withAnimation(.insightCardBounce) {
            selectedIndex = min(pageCount - 1, selectedIndex + 1)
        }
    }
}

private enum InsightLibraryScope {
    case currentConversation
    case all
}

private struct InsightLibraryScopeTabs: View {
    @Binding var selectedScope: InsightLibraryScope
    @Namespace private var selectedTabNamespace

    var body: some View {
        HStack(spacing: 0) {
            tabButton(title: "This Conversation", scope: .currentConversation)
            tabButton(title: "All", scope: .all)
        }
        .padding(6)
        .background(AquinasTheme.Colors.surface)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
        )
    }

    private func tabButton(title: String, scope: InsightLibraryScope) -> some View {
        Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                selectedScope = scope
            }
        } label: {
            Text(title)
                .font(.figtreeHeading3)
                .foregroundColor(AquinasTheme.Colors.primaryReadable)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background {
                    if selectedScope == scope {
                        Capsule()
                            .fill(AquinasTheme.Colors.componentBackground)
                            .matchedGeometryEffect(id: "selected-insight-scope-tab", in: selectedTabNamespace)
                    }
                }
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct InsightLibraryCard: View {
    let insight: ConceptDefinition
    let isSaved: Bool
    var maxWidth: CGFloat? = 315
    var shadowOpacity: Double = 0.15
    var onQuote: () -> Void
    var onFork: () -> Void
    var onToggleSaved: () -> Void
    @State private var isConfirmingUnbookmark = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AquinasTheme.Colors.darkGreen)
                    .sfSymbolDrawOn()

                Text(insight.word.capitalized)
                    .font(.custom("Figtree-Bold", size: 18))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer()

                ResponseButtons(
                    isSaved: isSaved,
                    canQuote: true,
                    canFork: true,
                    tintColor: AquinasTheme.Colors.placeholderText,
                    saveTintColor: AquinasTheme.Colors.accentRed,
                    onSave: handleSaveTapped,
                    onQuote: onQuote,
                    onFork: onFork
                )
            }

            InsightDefinitionsContent(
                definitions: insight.contextualDefinitions
            )
        }
        .padding(24)
        .frame(maxWidth: maxWidth)
        .background(AquinasTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AquinasTheme.Colors.brownBorder, lineWidth: 1)
        )
        .shadow(
            color: Color(red: 0.13, green: 0.06, blue: 0)
                .opacity(shadowOpacity),
            radius: 24,
            x: 0,
            y: 16
        )
        .alert("Remove bookmark?", isPresented: $isConfirmingUnbookmark) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                onToggleSaved()
            }
        } message: {
            Text("This insight may still appear in the current conversation, but it will be removed from your saved insights.")
        }
    }

    private func handleSaveTapped() {
        if isSaved {
            isConfirmingUnbookmark = true
        } else {
            onToggleSaved()
        }
    }
}

struct InsightLibraryPopupHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct InsightLibraryPager: View {
    let selectedIndex: Int
    let pageCount: Int
    var onPrevious: () -> Void
    var onNext: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPrevious) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    .frame(width: 48, height: 48)
                    .background(AquinasTheme.Colors.surface)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1))
            }
            .disabled(selectedIndex == 0)
            .opacity(selectedIndex == 0 ? 0.45 : 1)

            Text("\(min(selectedIndex + 1, pageCount))/\(max(pageCount, 1))")
                .font(.custom("LibreBaskerville-Regular", size: 14))
                .foregroundColor(AquinasTheme.Colors.primaryReadable)
                .frame(minWidth: 54)

            Button(action: onNext) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    .frame(width: 48, height: 48)
                    .background(AquinasTheme.Colors.surface)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1))
            }
            .disabled(selectedIndex >= pageCount - 1)
            .opacity(selectedIndex >= pageCount - 1 ? 0.45 : 1)
        }
        .buttonStyle(.plain)
    }
}

private struct InsightLibraryEmptyState: View {
    let scope: InsightLibraryScope

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.bubble")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(AquinasTheme.Colors.darkGreen)
                .sfSymbolDrawOn()

            Text(scope == .currentConversation ? "No insights in this conversation yet" : "No saved insights yet")
                .font(.custom("LibreBaskerville-Regular", size: 22))
                .foregroundColor(AquinasTheme.Colors.primaryReadable)
                .multilineTextAlignment(.center)

            Text(scope == .currentConversation ? "Tap an insight link in a response, then save it to collect it here." : "Saved insights will appear here across conversations.")
                .font(.figtreeParagraph)
                .foregroundColor(AquinasTheme.Colors.bodyText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 34)
        .background(AquinasTheme.Colors.componentBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AquinasTheme.Colors.brownBorder, lineWidth: 1)
        )
    }
}
