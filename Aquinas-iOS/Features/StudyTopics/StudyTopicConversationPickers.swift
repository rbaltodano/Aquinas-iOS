//
//  StudyTopicConversationPickers.swift
//  Aquinas-iOS
//

import SwiftUI

struct InsightConversationPickerSheet: View {
    let title: String
    let searchPrompt: String
    let emptyMessage: String
    let conversations: [InquiryConversation]
    let activeConversationID: UUID?
    let savedInsights: [ConceptDefinition]
    let onSelect: (InquiryConversation) -> Void
    let onCancel: () -> Void

    @State private var searchText = ""

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredConversations: [InquiryConversation] {
        conversations.filter { conversation in
            guard !normalizedSearchText.isEmpty else { return true }
            let text = [
                conversation.title,
                latestAnswer(in: conversation),
                insights(for: conversation).map(\.word).joined(separator: " ")
            ]
                .joined(separator: " ")
                .lowercased()
            return text.contains(normalizedSearchText)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Spacer(minLength: 32)

                    Text(title)
                        .font(.custom("LibreBaskerville-Regular", size: 24))
                        .foregroundColor(AquinasTheme.Colors.primaryReadable)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer()

                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AquinasTheme.Colors.paragraphText)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel choosing a Conversation")
                }
                .padding(.top, 32)

                StudyTopicsSearchField(
                    searchText: $searchText,
                    prompt: Text(searchPrompt)
                )

                if filteredConversations.isEmpty {
                    AquinasEmptyState(
                        systemImage: "bubble.left.and.bubble.right",
                        title: "No Conversations",
                        message: emptyMessage
                    )
                    .padding(.top, 24)
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(filteredConversations) { conversation in
                            OpenConversationCard(
                                conversation: conversation,
                                isActive: conversation.id == activeConversationID,
                                latestAnswer: latestAnswer(in: conversation),
                                insights: insights(for: conversation),
                                onSelect: {
                                    onSelect(conversation)
                                },
                                onOpenInsight: { _ in
                                    onSelect(conversation)
                                }
                            )
                        }
                    }
                }

                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 24)
        }
        .background(AquinasTheme.Colors.canvas)
    }

    private func insights(for conversation: InquiryConversation) -> [ConceptDefinition] {
        let insightIDs = ConversationInsightMembershipStore.insightIDs(for: conversation.id)
        return savedInsights.filter { insightIDs.contains($0.id) }.uniquedByWord()
    }

    private func latestAnswer(in conversation: InquiryConversation) -> String {
        for branch in conversation.branches.reversed() {
            for block in branch.activeChatBlocks.reversed() {
                if case .text(let answer) = block {
                    let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
        }
        for branch in conversation.branches.reversed() {
            let fallback = branch.bottomQuestionText.isEmpty
                ? branch.topQuestionText
                : branch.bottomQuestionText
            let trimmed = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return "Start a new line of inquiry."
    }
}

struct ExistingConversationPickerSheet: View {
    /// Conversations from sideMenuConversations — may be stale or empty if
    /// CurrentConversationView hasn't published its state yet this session.
    let conversations: [InquiryConversation]
    let activeConversationID: UUID?
    @Binding var savedInsights: [ConceptDefinition]
    var onSelectConversation: (InquiryConversation) -> Void
    var onOpenInsight: (ConceptDefinition) -> Void
    var onRenameConversation: (InquiryConversation, String) -> Void
    var onPinConversation: (InquiryConversation) -> Void
    var onUnpinConversation: (InquiryConversation) -> Void
    var onRemoveConversationFromStudyTopic: (InquiryConversation) -> Void
    var onDeleteConversation: (InquiryConversation) -> Void

    @State private var searchText = ""
    @State private var conversationBeingRenamed: InquiryConversation? = nil
    @State private var renameDraft = ""
    @State private var deletingConversationIDs: Set<UUID> = []
    /// Loaded from CurrentConversationsStore on appear as a reliable fallback.
    @State private var storeConversations: [InquiryConversation] = []
    /// Conversations the user has tapped, pending a single "Add" tap to attach them all.
    @State private var selectedConversationIDs: Set<UUID> = []
    @State private var addButtonPulseScale: CGFloat = 1.0

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Merge in-memory conversations (more up-to-date studyTopicID state) with
    /// anything loaded from the store that wasn't in the passed list, then filter
    /// to only unattached ones.
    private var unattachedConversations: [InquiryConversation] {
        let inMemoryIDs = Set(conversations.map(\.id))
        let storeOnly = storeConversations.filter { !inMemoryIDs.contains($0.id) }
        return (conversations + storeOnly).filter { $0.studyTopicID == nil }
    }

    private var filteredConversations: [InquiryConversation] {
        unattachedConversations.filter { conversation in
            guard !normalizedSearchText.isEmpty else { return true }
            let insightWords = insights(for: conversation).map(\.word).joined(separator: " ")
            let text = [
                conversation.title,
                latestAnswer(in: conversation),
                insightWords,
                searchableText(conversation)
            ].joined(separator: " ").lowercased()
            return text.contains(normalizedSearchText)
        }
    }

    private var addButtonSuffix: String {
        selectedConversationIDs.count == 1 ? "Conversation" : "Conversations"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Add Existing Conversation")
                        .font(.custom("LibreBaskerville-Regular", size: 24))
                        .foregroundColor(AquinasTheme.Colors.primaryReadable)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 56)

                    StudyTopicsSearchField(searchText: $searchText)
                        .padding(.top, 24)

                    if filteredConversations.isEmpty {
                        Text("No conversations available.")
                            .font(.custom("Figtree-Regular", size: 14))
                            .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(filteredConversations) { conversation in
                                OpenConversationCard(
                                    conversation: conversation,
                                    isActive: conversation.id == activeConversationID,
                                    latestAnswer: latestAnswer(in: conversation),
                                    insights: insights(for: conversation),
                                    onSelect: {
                                        toggleSelection(conversation)
                                    },
                                    onOpenInsight: onOpenInsight,
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
                                        toggleSelection(conversation)
                                    },
                                    onRemoveFromStudyTopic: { conversation in
                                        onRemoveConversationFromStudyTopic(conversation)
                                    },
                                    onDelete: { conversation in
                                        deleteConversationCard(conversation)
                                    },
                                    isSelected: selectedConversationIDs.contains(conversation.id)
                                )
                                .opacity(deletingConversationIDs.contains(conversation.id) ? 0 : 1)
                                .blur(radius: deletingConversationIDs.contains(conversation.id) ? 12 : 0)
                            }
                        }
                        .padding(.top, 32)
                    }

                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal, 24)
            }
            .background(AquinasTheme.Colors.canvas)

            if !selectedConversationIDs.isEmpty {
                Button(action: addSelectedConversations) {
                    HStack(spacing: 4) {
                        Text("Add")
                        Text("\(selectedConversationIDs.count)")
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(addButtonSuffix)
                    }
                    .font(.custom("Figtree-Regular", size: 14))
                    .foregroundColor(AquinasTheme.Colors.canvas)
                    .padding(.horizontal, 22)
                    .frame(height: 52)
                    .background(AquinasTheme.Colors.secondaryMuted)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
                .shadow(color: AquinasTheme.Colors.dropShadow.opacity(0.16), radius: 16, x: 0, y: 10)
                .scaleEffect(addButtonPulseScale)
                .transition(.addButtonEntrance)
            }
        }
        .onChange(of: selectedConversationIDs.count) { _, _ in
            triggerAddButtonPulse()
        }
        .onAppear {
            // Load from the authoritative store so the list is never empty
            // because sideMenuConversations hasn't been published yet this session.
            if let snapshot = CurrentConversationsStore.load() {
                storeConversations = snapshot.conversations
            }
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

    private func toggleSelection(_ conversation: InquiryConversation) {
        withAnimation(.spring(response: 0.18, dampingFraction: 0.86)) {
            if selectedConversationIDs.contains(conversation.id) {
                selectedConversationIDs.remove(conversation.id)
            } else {
                selectedConversationIDs.insert(conversation.id)
            }
        }
    }

    private func addSelectedConversations() {
        let selected = unattachedConversations.filter { selectedConversationIDs.contains($0.id) }
        for conversation in selected {
            onSelectConversation(conversation)
        }
        withAnimation(.spring(response: 0.18, dampingFraction: 0.86)) {
            selectedConversationIDs.removeAll()
        }
    }

    private func triggerAddButtonPulse() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.52)) {
            addButtonPulseScale = 1.05
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.68)) {
                addButtonPulseScale = 1.0
            }
        }
    }

    private func latestAnswer(in conversation: InquiryConversation) -> String {
        for branch in conversation.branches.reversed() {
            for block in branch.activeChatBlocks.reversed() {
                if case .text(let answer) = block {
                    let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
        }
        for branch in conversation.branches.reversed() {
            let fallback = branch.bottomQuestionText.isEmpty
                ? branch.topQuestionText
                : branch.bottomQuestionText
            let trimmed = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return "Start a new line of inquiry."
    }

    private func insights(for conversation: InquiryConversation) -> [ConceptDefinition] {
        let text = searchableText(conversation).lowercased()
        return savedInsights.filter { text.contains($0.word.lowercased()) }.uniquedByWord()
    }

    private func searchableText(_ conversation: InquiryConversation) -> String {
        var text = conversation.title
        for branch in conversation.branches {
            text += " \(branch.topQuestionText) \(branch.bottomQuestionText) \(branch.duplicatedResponse ?? "")"
            for block in branch.activeChatBlocks {
                switch block {
                case .text(let t): text += " \(t)"
                case .user(let q, let c, _):
                    text += " \(q)"
                    if let c { text += " \(c.word) \(c.meaning)" }
                }
            }
        }
        return text
    }
}
