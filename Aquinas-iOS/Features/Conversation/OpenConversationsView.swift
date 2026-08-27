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
    let modelTasks: ModelTaskQueue
    let modelTasksPopupState: ModelTasksPopupState
    var onOpenMenu: () -> Void
    var onSelectConversation: (InquiryConversation) -> Void
    var onNewChat: () -> Void
    var onRenameConversation: (InquiryConversation, String) -> Void
    var onPinConversation: (InquiryConversation) -> Void
    var onUnpinConversation: (InquiryConversation) -> Void
    var onAddConversationToStudyTopic: (InquiryConversation, UUID) -> Void
    var onRemoveConversationFromStudyTopic: (InquiryConversation) -> Void
    var onDeleteConversation: (InquiryConversation) -> Void
    var onRefresh: () -> Void = {}

    @State private var searchText = ""
    @State private var activeInsight: ConceptDefinition? = nil
    @State private var conversationBeingRenamed: InquiryConversation? = nil
    @State private var conversationBeingAddedToStudyTopic: InquiryConversation? = nil
    @State private var deletingConversationIDs: Set<UUID> = []
    @State private var renameDraft = ""
    @State private var activeFilter: ConversationFilter = .recent
    @State private var isGrouped = false
    @State private var studyTopics: [StudyTopic] = []

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var searchFilteredConversations: [InquiryConversation] {
        conversations.filter(conversationMatchesSearch)
    }

    private var visibleConversations: [InquiryConversation] {
        let filtered = searchFilteredConversations.filter { activeFilter.matches($0) }
        guard activeFilter == .recent else { return filtered }
        return filtered.sorted { $0.createdAt > $1.createdAt }
    }

    /// When grouped by Study Topics, the active filter applies to whole groups
    /// (which groups show, and in what order) rather than reordering individual
    /// cards inside a group. `nil` when the Study Topics toggle is off.
    private var displaySections: [ConversationSection]? {
        guard isGrouped else { return nil }
        return groupedSections(searchFilteredConversations, filter: activeFilter)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AquinasTheme.Colors.canvas
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Spacer so the title doesn't sit under the sticky button.
                    Color.clear.frame(height: 72)

                    VStack(alignment: .center, spacing: 8) {
                        Text(todayString())
                            .font(AquinasTheme.Typography.uiLabel)
                            .foregroundColor(AquinasTheme.Colors.lightGreen)

                        Text("Open Conversations")
                            .font(.custom("LibreBaskerville-Regular", size: 30))
                            .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 28)

                    OpenConversationsSearchField(searchText: $searchText)
                        .padding(.top, 28)

                    HStack(spacing: 12) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 24) {
                                ForEach(ConversationFilter.allCases) { filter in
                                    Button(action: {
                                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                            activeFilter = filter
                                        }
                                    }) {
                                        Text(filter.label)
                                            .font(AquinasTheme.Typography.uiSubheading)
                                            .foregroundColor(
                                                activeFilter == filter
                                                    ? AquinasTheme.Colors.lightGreen
                                                    : AquinasTheme.Colors.placeholderText
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Spacer(minLength: 8)

                        if !studyTopics.isEmpty {
                            Button(action: {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                    isGrouped.toggle()
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.stack")
                                        .font(.system(size: 12, weight: .bold))

                                    Text("Study Topics")
                                        .font(AquinasTheme.Typography.uiSubheading)
                                }
                                .foregroundColor(isGrouped ? AquinasTheme.Colors.lightGreen : AquinasTheme.Colors.placeholderText)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isGrouped ? "Study topic grouping enabled" : "Enable study topic grouping")
                        }
                    }
                    .padding(.top, 16)

                    VStack(alignment: .leading, spacing: 16) {
                        if let sections = displaySections {
                            if sections.isEmpty {
                                OpenConversationsEmptyState(hasAnyConversations: !conversations.isEmpty)
                                    .padding(.top, 8)
                            } else {
                                sectionedList(sections)
                            }
                        } else if visibleConversations.isEmpty {
                            OpenConversationsEmptyState(hasAnyConversations: !conversations.isEmpty)
                                .padding(.top, 8)
                        } else if activeFilter == .date {
                            sectionedList(dateGroupedSections(visibleConversations))
                        } else {
                            ForEach(visibleConversations) { conversation in
                                conversationCard(conversation)
                            }
                        }
                    }
                    .padding(.top, 48)
                    .animation(.spring(response: 0.34, dampingFraction: 0.86), value: normalizedSearchText)
                    .animation(.spring(response: 0.34, dampingFraction: 0.86), value: activeFilter)
                    .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isGrouped)

                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .refreshable {
                refreshContent()
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

        }
        .onAppear {
            studyTopics = StudyTopicStore.load()
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

    @ViewBuilder
    private func conversationCard(_ conversation: InquiryConversation) -> some View {
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
            }
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

    /// Builds Study Topic sections and applies `filter` at the group level — deciding
    /// which whole groups appear and in what order — rather than reordering or
    /// dropping individual cards inside a group.
    private func groupedSections(_ list: [InquiryConversation], filter: ConversationFilter) -> [ConversationSection] {
        let pinned = list.filter { $0.isPinned }
        let unpinned = list.filter { !$0.isPinned }

        var sections: [ConversationSection] = []
        if !pinned.isEmpty {
            sections.append(ConversationSection(id: "pinned", title: "Pinned", conversations: pinned))
        }

        let topicGroups = Dictionary(grouping: unpinned.filter { $0.studyTopicID != nil }) { $0.studyTopicID! }
        for topicID in topicGroups.keys {
            guard let topicConversations = topicGroups[topicID] else { continue }
            sections.append(
                ConversationSection(
                    id: "topic-\(topicID.uuidString)",
                    title: studyTopicTitle(for: topicID),
                    conversations: topicConversations
                )
            )
        }

        let recent = unpinned.filter { $0.studyTopicID == nil }
        if !recent.isEmpty {
            sections.append(ConversationSection(id: "recent", title: "Recent", conversations: recent))
        }

        if filter == .pinned {
            // Treat "pinned" as a whole-group property: keep entire groups that contain
            // at least one pinned conversation, instead of filtering individual cards.
            sections = sections.filter { section in section.conversations.contains { $0.isPinned } }
        }

        // "Recent"/"Date" sort groups themselves by their most recently created
        // conversation, so the filter reorders Study Topics as whole units.
        return sections.sorted { lhs, rhs in
            let lhsDate = lhs.conversations.map(\.createdAt).max() ?? .distantPast
            let rhsDate = rhs.conversations.map(\.createdAt).max() ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.title < rhs.title
        }
    }

    @ViewBuilder
    private func sectionedList(_ sections: [ConversationSection]) -> some View {
        ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
            VStack(alignment: .leading, spacing: 16) {
                AquinasSectionTitle(section.title)

                ForEach(section.conversations) { conversation in
                    conversationCard(conversation)
                }
            }

            if index < sections.count - 1 {
                AquinasSectionDivider()
                    .padding(.vertical, 8)
            }
        }
    }

    /// Groups conversations by the calendar day they were created, most recent day first.
    private func dateGroupedSections(_ list: [InquiryConversation]) -> [ConversationSection] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: list) { calendar.startOfDay(for: $0.createdAt) }
        return groups.keys.sorted(by: >).map { day in
            ConversationSection(
                id: "date-\(day.timeIntervalSince1970)",
                title: dayLabel(for: day),
                conversations: (groups[day] ?? []).sorted { $0.createdAt > $1.createdAt }
            )
        }
    }

    private func dayLabel(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.month(.wide).day().year())
    }

    private func studyTopicTitle(for id: UUID) -> String {
        let title = studyTopics.first(where: { $0.id == id })?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Study Topic" : title
    }

    private func todayString(date: Date = Date()) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }

    private func refreshContent() {
        studyTopics = StudyTopicStore.load()
        onRefresh()
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
        // Only surface insights the user actually saved *within* this conversation —
        // i.e. concepts embedded in its branches — not every saved insight whose
        // word happens to appear somewhere in the conversation text.
        let conceptWords = Set(embeddedConcepts(in: conversation).map { $0.word.lowercased() })

        return savedInsights.filter { insight in
            conceptWords.contains(insight.word.lowercased())
        }
        .uniquedByWord()
    }

    private func embeddedConcepts(in conversation: InquiryConversation) -> [ConceptDefinition] {
        var concepts: [ConceptDefinition] = []

        for branch in conversation.branches {
            concepts.append(contentsOf: [
                branch.startingConcept,
                branch.attachedConcept,
                branch.branchContextConcept
            ].compactMap { $0 })

            for block in branch.activeChatBlocks {
                if case .user(_, let concept?, _) = block {
                    concepts.append(concept)
                }
            }
        }

        return concepts
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

private struct ConversationSection: Identifiable {
    let id: String
    let title: String
    let conversations: [InquiryConversation]
}

private enum ConversationFilter: String, CaseIterable, Identifiable, Equatable {
    case recent, pinned, date

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: return "Recent"
        case .pinned: return "Pinned"
        case .date: return "Date"
        }
    }

    func matches(_ conversation: InquiryConversation) -> Bool {
        switch self {
        case .recent, .date:
            return true
        case .pinned:
            return conversation.isPinned
        }
    }
}

private struct OpenConversationsEmptyState: View {
    let hasAnyConversations: Bool

    var body: some View {
        if hasAnyConversations {
            AquinasEmptyState(
                systemImage: "magnifyingglass",
                title: "No Matches Found",
                message: "Try a different search term or filter."
            )
        } else {
            AquinasEmptyState(
                systemImage: "bubble.left.and.text.bubble.right",
                title: "Begin a line of inquiry",
                message: "Start a conversation and it will appear here, ready to resume anytime."
            )
        }
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

            TextField("Search Conversations", text: $searchText)
                .font(AquinasTheme.Typography.body)
                .foregroundColor(AquinasTheme.Colors.paragraphText)
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
    /// When true, shows a light-green selection border instead of the default
    /// hairline border — used by multi-select pickers (e.g. adding conversations
    /// to a Study Topic).
    var isSelected: Bool = false

    @State private var isExpanded = false

    private var visibleInsights: [ConceptDefinition] {
        isExpanded ? insights : Array(insights.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                if conversation.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AquinasTheme.Colors.lightGreen)
                }

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
                                Button("Remove from Study Topic", systemImage: "square.stack") {
                                    onRemoveFromStudyTopic(conversation)
                                }
                            }
                        } else if let onAddToStudyTopic {
                            Button("Add to Study Topic", systemImage: "square.stack") {
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

            ConversationCardAnswerText(answer: latestAnswer)

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
                .stroke(
                    isSelected ? AquinasTheme.Colors.lightGreen : AquinasTheme.Colors.controlBorder,
                    lineWidth: isSelected ? 2 : 1
                )
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

/// Renders the short answer preview without exposing persisted `aq://` Markdown or the local
/// model's `{{term}}` generation markers. Conversation cards are intentionally non-interactive;
/// highlighted terms communicate the same Insight affordance while the card tap opens the full
/// conversation.
private struct ConversationCardAnswerText: View {
    let answer: String

    var body: some View {
        Text(
            ConversationCardAnswerFormatting.attributedText(
                from: answer,
                highlightColor: AquinasTheme.Colors.lightGreen
            )
        )
        .font(.custom("Figtree-Regular", size: 14))
        .foregroundColor(AquinasTheme.Colors.paragraphText)
        .lineSpacing(5)
        .lineLimit(2)
        .truncationMode(.tail)
    }
}

enum ConversationCardAnswerFormatting {
    enum Segment: Equatable {
        case plain(String)
        case insight(String)
    }

    private static let insightMarkup = try! NSRegularExpression(
        pattern: #"\*{0,2}\[([^\]]+)\]\(aq://[^)]+\)\*{0,2}|\*{0,2}\{\{([^{}]+)\}\}\*{0,2}"#
    )

    static func segments(from answer: String) -> [Segment] {
        let visibleAnswer = InlineInsightMarkup.plainText(from: answer)
        let fullRange = NSRange(visibleAnswer.startIndex..., in: visibleAnswer)
        let matches = insightMarkup.matches(in: visibleAnswer, range: fullRange)
        var segments: [Segment] = []
        var cursor = visibleAnswer.startIndex

        for match in matches {
            guard let matchRange = Range(match.range(at: 0), in: visibleAnswer) else {
                continue
            }
            appendPlain(String(visibleAnswer[cursor..<matchRange.lowerBound]), to: &segments)

            let titleRange = match.range(at: 1).location != NSNotFound
                ? match.range(at: 1)
                : match.range(at: 2)
            if let titleRange = Range(titleRange, in: visibleAnswer) {
                segments.append(.insight(String(visibleAnswer[titleRange])))
            }
            cursor = matchRange.upperBound
        }

        appendPlain(String(visibleAnswer[cursor...]), to: &segments)
        return segments
    }

    static func attributedText(from answer: String, highlightColor: Color) -> AttributedString {
        var result = AttributedString()
        for segment in segments(from: answer) {
            switch segment {
            case .plain(let text):
                result.append(AttributedString(text))
            case .insight(let text):
                var highlighted = AttributedString(text)
                highlighted.foregroundColor = highlightColor
                highlighted.underlineStyle = .single
                result.append(highlighted)
            }
        }
        return result
    }

    private static func appendPlain(_ text: String, to segments: inout [Segment]) {
        let cleaned = text
            .replacingOccurrences(of: "{{", with: "")
            .replacingOccurrences(of: "}}", with: "")
        guard !cleaned.isEmpty else { return }
        if case .plain(let previous) = segments.last {
            segments[segments.count - 1] = .plain(previous + cleaned)
        } else {
            segments.append(.plain(cleaned))
        }
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
