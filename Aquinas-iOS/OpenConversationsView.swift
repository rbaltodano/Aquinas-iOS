//
//  OpenConversationsView.swift
//  Aquinas-iOS
//

import SwiftUI

// MARK: - Open Conversations

struct OpenConversationsView: View {
    let conversations: [InquiryConversation]
    let activeConversationID: UUID?
    @Binding var savedInsights: [ConceptDefinition]
    var onOpenMenu: () -> Void
    var onSelectConversation: (InquiryConversation) -> Void
    var onNewChat: () -> Void
    var onRenameConversation: (InquiryConversation, String) -> Void

    @State private var searchText = ""
    @State private var activeInsight: ConceptDefinition? = nil
    @State private var conversationBeingRenamed: InquiryConversation? = nil
    @State private var renameDraft = ""

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AquinasTheme.Colors.canvas
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Spacer so the title doesn't sit under the sticky button.
                    Color.clear.frame(height: 72)

                    Text("Open Conversations")
                        .font(.custom("LibreBaskerville-Regular", size: 30))
                        .foregroundColor(AquinasTheme.Colors.primaryReadable)
                        .padding(.top, 28)
                        .frame(maxWidth: .infinity, alignment: .center)

                    OpenConversationsSearchField(searchText: $searchText)
                        .padding(.top, 28)

                    LazyVStack(spacing: 16) {
                        ForEach(conversations) { conversation in
                            if conversationMatchesSearch(conversation) {
                                OpenConversationCard(
                                    conversation: conversation,
                                    isActive: conversation.id == activeConversationID,
                                    latestAnswer: latestAnswer(in: conversation),
                                    insights: insights(for: conversation),
                                    onSelect: {
                                        onSelectConversation(conversation)
                                    },
                                    onOpenInsight: { insight in
                                        activeInsight = insight
                                    },
                                    onRename: { conversation in
                                        renameDraft = conversation.title
                                        conversationBeingRenamed = conversation
                                    }
                                )
                                .transition(
                                    .asymmetric(
                                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                                        removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                                    )
                                )
                            }
                        }
                    }
                    .padding(.top, 48)
                    .padding(.bottom, 120)
                    .animation(.spring(response: 0.34, dampingFraction: 0.86), value: normalizedSearchText)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Sticky side-menu trigger — floats above the scroll content.
            VStack {
                HStack {
                    SideMenuTriggerButton(action: onOpenMenu)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(true)
            .zIndex(10)

            Button(action: onNewChat) {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .sfSymbolDrawOn()

                    Text("New Chat")
                        .font(.custom("Figtree-Regular", size: 14))
                }
                .foregroundColor(AquinasTheme.Colors.canvas)
                .padding(.horizontal, 22)
                .frame(height: 52)
                .background(AquinasTheme.Colors.secondaryMuted)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 24)
            .padding(.bottom, 24)
            .shadow(color: AquinasTheme.Colors.dropShadow.opacity(0.16), radius: 16, x: 0, y: 10)
        }
        .sheet(item: $activeInsight) { insight in
            ConceptSheetContent(concept: insight, collectedDefinitions: $savedInsights)
                .presentationDetents([.fraction(0.45)])
                .presentationDragIndicator(.visible)
                .presentationBackground(AquinasTheme.Colors.canvas)
        }
        .alert("Rename Conversation", isPresented: renamePromptBinding) {
            TextField("Conversation name", text: $renameDraft)
            Button("Cancel", role: .cancel) {
                conversationBeingRenamed = nil
                renameDraft = ""
            }
            Button("Save") {
                guard let conversationBeingRenamed else { return }
                let title = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    onRenameConversation(conversationBeingRenamed, title)
                }
                self.conversationBeingRenamed = nil
                renameDraft = ""
            }
        }
    }

    private var renamePromptBinding: Binding<Bool> {
        Binding(
            get: { conversationBeingRenamed != nil },
            set: { isPresented in
                if !isPresented {
                    conversationBeingRenamed = nil
                    renameDraft = ""
                }
            }
        )
    }

    private func latestAnswer(in conversation: InquiryConversation) -> String {
        for branch in conversation.branches.reversed() {
            for block in branch.activeChatBlocks.reversed() {
                if case .text(let answer) = block {
                    let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedAnswer.isEmpty {
                        return trimmedAnswer
                    }
                }
            }
        }

        for branch in conversation.branches.reversed() {
            let fallbackText = branch.bottomQuestionText.isEmpty ? branch.topQuestionText : branch.bottomQuestionText
            let trimmedFallback = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedFallback.isEmpty {
                return trimmedFallback
            }
        }

        return "Start a new line of inquiry."
    }

    private func insights(for conversation: InquiryConversation) -> [ConceptDefinition] {
        let conversationText = searchableConversationText(conversation).lowercased()

        return savedInsights.filter { insight in
            conversationText.contains(insight.word.lowercased())
        }
        .uniquedByWord()
    }

    private func conversationMatchesSearch(_ conversation: InquiryConversation) -> Bool {
        guard !normalizedSearchText.isEmpty else { return true }

        let insightWords = insights(for: conversation).map(\.word).joined(separator: " ")
        let searchableText = [
            conversation.title,
            latestAnswer(in: conversation),
            insightWords,
            searchableConversationText(conversation)
        ].joined(separator: " ").lowercased()

        return searchableText.contains(normalizedSearchText)
    }

    private func searchableConversationText(_ conversation: InquiryConversation) -> String {
        var text = conversation.title

        for branch in conversation.branches {
            text += " \(branch.topQuestionText) \(branch.bottomQuestionText) \(branch.duplicatedResponse ?? "")"

            if let startingConcept = branch.startingConcept {
                text += " \(startingConcept.word) \(startingConcept.meaning)"
            }

            if let attachedConcept = branch.attachedConcept {
                text += " \(attachedConcept.word) \(attachedConcept.meaning)"
            }

            if let branchContextConcept = branch.branchContextConcept {
                text += " \(branchContextConcept.word) \(branchContextConcept.meaning)"
            }

            for block in branch.activeChatBlocks {
                switch block {
                case .text(let answer):
                    text += " \(answer)"
                case .user(let question, let concept, _):
                    text += " \(question)"
                    if let concept {
                        text += " \(concept.word) \(concept.meaning)"
                    }
                }
            }
        }

        return text
    }
}

private struct OpenConversationsSearchField: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AquinasTheme.Colors.lightGreen)
                .frame(width: 16, height: 16)

            TextField("Search", text: $searchText)
                .font(.custom("LibreBaskerville-Regular", size: 14))
                .foregroundColor(AquinasTheme.Colors.primaryReadable)
                .tint(AquinasTheme.Colors.secondaryMuted)
                .submitLabel(.search)
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
        .background(AquinasTheme.Colors.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AquinasTheme.Colors.sideMenuSearchBorder, lineWidth: 1)
        )
    }
}

private struct OpenConversationCard: View {
    let conversation: InquiryConversation
    let isActive: Bool
    let latestAnswer: String
    let insights: [ConceptDefinition]
    var onSelect: () -> Void
    var onOpenInsight: (ConceptDefinition) -> Void
    var onRename: (InquiryConversation) -> Void

    @State private var isExpanded = false
    @State private var isOptionsMenuOpen = false

    private var visibleInsights: [ConceptDefinition] {
        isExpanded ? insights : Array(insights.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text(conversation.title)
                    .font(.custom("Figtree-Bold", size: 14))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.76)) {
                        isOptionsMenuOpen.toggle()
                    }
                }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AquinasTheme.Colors.paragraphText)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Conversation options")
            }

            Text(latestAnswer)
                .font(.custom("Figtree-Regular", size: 14))
                .foregroundColor(AquinasTheme.Colors.paragraphText)
                .lineSpacing(5)
                .lineLimit(2)
                .truncationMode(.tail)

            if !insights.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(visibleInsights) { insight in
                        Button(action: {
                            onOpenInsight(insight)
                        }) {
                            InsightLine(word: insight.word)
                        }
                        .buttonStyle(.plain)
                    }

                    if insights.count > 3 {
                        Button(action: {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                isExpanded.toggle()
                            }
                        }) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(AquinasTheme.Colors.lightGreen)
                                .frame(width: 32, height: 18)
                                .background(AquinasTheme.Colors.canvas.opacity(0.72))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AquinasTheme.Colors.componentBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onSelect)
        .overlay(alignment: .topTrailing) {
            if isOptionsMenuOpen {
                ZStack(alignment: .topTrailing) {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: 345, height: 700)
                        .offset(x: 24, y: -260)
                        .onTapGesture {
                            closeOptionsMenu()
                        }
                        .zIndex(0)

                    ConversationOptionsMenu(
                        onRename: {
                            closeOptionsMenu()
                            onRename(conversation)
                        },
                        onPin: {
                            closeOptionsMenu()
                        },
                        onDelete: {
                            closeOptionsMenu()
                        }
                    )
                    .offset(x: -24, y: 52)
                    .zIndex(1)
                }
                .zIndex(120)
            }
        }
        .zIndex(isOptionsMenuOpen ? 120 : 0)
    }

    private func closeOptionsMenu() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.76)) {
            isOptionsMenuOpen = false
        }
    }
}

private struct InsightLine: View {
    let word: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AquinasTheme.Colors.lightGreen)
                .frame(width: 13, height: 13)

            Text(word)
                .font(.custom("Figtree-Bold", size: 12))
                .foregroundColor(AquinasTheme.Colors.lightGreen)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
