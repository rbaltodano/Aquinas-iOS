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
    var onPinConversation: (InquiryConversation) -> Void
    var onUnpinConversation: (InquiryConversation) -> Void
    var onAddConversationToStudyTopic: (InquiryConversation, UUID) -> Void
    var onRemoveConversationFromStudyTopic: (InquiryConversation) -> Void
    var onDeleteConversation: (InquiryConversation) -> Void

    @State private var searchText = ""
    @State private var activeInsight: ConceptDefinition? = nil
    @State private var conversationBeingRenamed: InquiryConversation? = nil
    @State private var conversationBeingAddedToStudyTopic: InquiryConversation? = nil
    @State private var deletingConversationIDs: Set<UUID> = []
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
                                    },
                                    onPin: { conversation in
                                        onPinConversation(conversation)
                                    },
                                    onUnpin: { conversation in
                                        onUnpinConversation(conversation)
                                    },
                                    onAddToStudyTopic: { conversation in
                                        conversationBeingAddedToStudyTopic = conversation
                                    },
                                    onRemoveFromStudyTopic: { conversation in
                                        onRemoveConversationFromStudyTopic(conversation)
                                    },
                                    onDelete: { conversation in
                                        deleteConversationCard(conversation)
                                    },
                                )
                                .opacity(deletingConversationIDs.contains(conversation.id) ? 0 : 1)
                                .blur(radius: deletingConversationIDs.contains(conversation.id) ? 12 : 0)
                                .scaleEffect(deletingConversationIDs.contains(conversation.id) ? 0.96 : 1)
                                .allowsHitTesting(!deletingConversationIDs.contains(conversation.id))
                                .animation(
                                    .easeInOut(duration: 0.22),
                                    value: deletingConversationIDs.contains(conversation.id)
                                )
                                .transition(
                                    .asymmetric(
                                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                                        removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
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

            LinearGradient(
                colors: [AquinasTheme.Colors.canvas.opacity(0), AquinasTheme.Colors.canvas],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 350)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
            .ignoresSafeArea()

            // Sticky side-menu trigger — floats above the scroll content.
            VStack {
                HStack {
                    AquinasNavButton(onMenuTap: onOpenMenu)
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

                    Text("New Conversation")
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
                .presentationDetents([.height(340), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(AquinasTheme.Colors.canvas)
        }
        .sheet(item: $conversationBeingAddedToStudyTopic) { conversation in
            SideMenuStudyTopicPickerSheet(
                conversation: conversation,
                onSelectTopic: { topic in
                    onAddConversationToStudyTopic(conversation, topic.id)
                    conversationBeingAddedToStudyTopic = nil
                }
            )
            .presentationDetents([.height(420), .large])
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

    private func deleteConversationCard(_ conversation: InquiryConversation) {
        guard !deletingConversationIDs.contains(conversation.id) else { return }

        deletingConversationIDs.insert(conversation.id)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                onDeleteConversation(conversation)
            }
            deletingConversationIDs.remove(conversation.id)
        }
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

struct OpenConversationCard: View {
    let conversation: InquiryConversation
    let isActive: Bool
    let latestAnswer: String
    let insights: [ConceptDefinition]
    var onSelect: () -> Void
    var onOpenInsight: (ConceptDefinition) -> Void
    var onRename: ((InquiryConversation) -> Void)? = nil
    var onPin: ((InquiryConversation) -> Void)? = nil
    var onUnpin: ((InquiryConversation) -> Void)? = nil
    var onAddToStudyTopic: ((InquiryConversation) -> Void)? = nil
    var onRemoveFromStudyTopic: ((InquiryConversation) -> Void)? = nil
    var onDelete: ((InquiryConversation) -> Void)? = nil

    @State private var isExpanded = false

    private var visibleInsights: [ConceptDefinition] {
        isExpanded ? insights : Array(insights.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text(conversation.title)
                    .font(AquinasTheme.Typography.uiHeading)
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                if hasConversationOptions {
                    Menu {
                        if let onRename {
                            Button("Rename", systemImage: "pencil.line") { onRename(conversation) }
                        }

                        if conversation.isPinned {
                            if let onUnpin {
                                Button("Unpin", systemImage: "pin.slash") { onUnpin(conversation) }
                            }
                        } else if let onPin {
                            Button("Pin", systemImage: "pin") { onPin(conversation) }
                        }

                        if conversation.studyTopicID != nil {
                            if let onRemoveFromStudyTopic {
                                Button("Remove from Study Topic", systemImage: "book.closed") {
                                    onRemoveFromStudyTopic(conversation)
                                }
                            }
                        } else if let onAddToStudyTopic {
                            Button("Add to Study Topic", systemImage: "book.closed") {
                                onAddToStudyTopic(conversation)
                            }
                        }

                        if let onDelete {
                            Divider()
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                onDelete(conversation)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AquinasTheme.Colors.paragraphText)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .padding(11)
                    .contentShape(Rectangle())
                    .padding(-11)
                    .accessibilityLabel("Conversation options")
                }
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
        .background(AquinasTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture(perform: onSelect)
    }

    private var hasConversationOptions: Bool {
        onRename != nil ||
        onPin != nil ||
        onUnpin != nil ||
        onAddToStudyTopic != nil ||
        onRemoveFromStudyTopic != nil ||
        onDelete != nil
    }
}

struct InsightLine: View {
    let word: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AquinasTheme.Colors.lightGreen)
                .frame(width: 14, height: 14)

            Text(word)
                .font(.figtreeHeading2)
                .foregroundColor(AquinasTheme.Colors.lightGreen)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
