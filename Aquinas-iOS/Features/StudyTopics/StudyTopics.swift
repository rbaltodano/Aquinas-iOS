//
//  StudyTopics.swift
//  Aquinas-iOS
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Study Topic Model

struct StudyTopic: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var description: String
    var files: [UploadedFile]
    /// When this topic was created — drives the "Date" filter's day-based grouping.
    /// Defaults so existing persisted data without this field decodes safely.
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        title: String = "",
        description: String = "",
        files: [UploadedFile] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.files = files
        self.createdAt = createdAt
    }
}

enum StudyTopicStore {
    private static let key = "aquinas.study-topics.v1"

    /// Decoded topics, kept in memory because many screens reload topics every time they appear.
    /// `save` is the only writer of this key, so it keeps the cache current.
    private static var cachedTopics: [StudyTopic]?

    static func load() -> [StudyTopic] {
        if let cachedTopics { return cachedTopics }
        let topics = UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([StudyTopic].self, from: $0) } ?? []
        cachedTopics = topics
        return topics
    }

    static func save(_ topics: [StudyTopic]) {
        cachedTopics = topics
        guard let data = try? JSONEncoder().encode(topics) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

/// Persists the last user-approved aggregate Insight Tree input for each Study Topic.
/// Keeping this snapshot separate from the live Insight Library ensures a topic tree changes
/// only after the user accepts the refresh prompt shown when entering that topic.
enum StudyTopicInsightTreeStore {
    private static let key = "aquinas.study-topic.insight-trees.v1"

    static func load() -> [String: [ConceptDefinition]] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let snapshots = try? JSONDecoder().decode(
                [String: [ConceptDefinition]].self,
                from: data
              ) else {
            return [:]
        }
        return snapshots
    }

    static func save(_ snapshots: [String: [ConceptDefinition]]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

@MainActor
enum StudyTopicInsightTreeBuilder {
    static func snapshot(
        topicID: UUID,
        conversations: [InquiryConversation],
        savedInsights: [ConceptDefinition],
        insightIDs: @MainActor (UUID) -> Set<UUID> = ConversationInsightMembershipStore.insightIDs(for:)
    ) -> [ConceptDefinition] {
        let topicConversationIDs = conversations
            .filter { $0.studyTopicID == topicID }
            .map(\.id)
        let topicInsightIDs = topicConversationIDs.reduce(into: Set<UUID>()) {
            $0.formUnion(insightIDs($1))
        }

        return savedInsights
            .filter { topicInsightIDs.contains($0.id) }
            .uniquedByWord()
            .sorted {
                $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending
            }
    }
}

// MARK: - New Study Topic Prompt

struct NewStudyTopicSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var description: String = ""
    @FocusState private var isTitleFocused: Bool
    var onCreate: (String, String) -> Void

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Summer Bible Study", text: $title)
                        .focused($isTitleFocused)
                }
                Section("Description") {
                    TextField("Briefly describe this topic", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Study Topic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", systemImage: "checkmark") {
                        onCreate(trimmedTitle, description.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedTitle.isEmpty)
                }
            }
            .onAppear { isTitleFocused = true }
        }
    }
}

// MARK: - Study Topics List

/// Reported up to the app shell so the global, persistent Model Controls bar can render this
/// page's bottom pill from outside the page-transition animation, while all of the state that
/// decides its content (selected topic, canvas mode, pending tree-update confirmation) stays
/// owned locally here exactly as before.
struct StudyTopicsPageControls {
    var isVisible: Bool = false
    var actionTitle: String? = nil
    var secondaryActionTitle: String? = nil
    var action: () -> Void = {}
    var secondaryAction: () -> Void = {}
    var confirmationTitle: String? = nil
    var onConfirm: () -> Void = {}
    var onDecline: () -> Void = {}
}

struct StudyTopicsView: View {
    let conversations: [InquiryConversation]
    let activeConversationID: UUID?
    @Binding var savedInsights: [ConceptDefinition]
    let modelTasks: ModelTaskQueue
    let modelTasksPopupState: ModelTasksPopupState
    @Environment(\.aquinasModel) private var model
    @Environment(\.embeddingProvider) private var embeddingProvider
    private let insightTreeService: InsightTreeService = BackendInsightTreeService()
    var onOpenMenu: () -> Void
    var onSelectConversation: (InquiryConversation) -> Void
    var onNewChat: () -> Void
    /// Called when the user taps "New Conversation" inside a topic's detail view.
    var onNewChatInTopic: (UUID) -> Void = { _ in }
    var onQuoteInsightIntoNewConversation:
        (ConceptDefinition, UUID) -> Void = { _, _ in }
    var onQuoteInsightIntoConversation:
        (InquiryConversation, ConceptDefinition, UUID) -> Void = { _, _, _ in }
    var onAttachConversationToTopic: (InquiryConversation, UUID) -> Void
    var onRenameConversation: (InquiryConversation, String) -> Void
    var onPinConversation: (InquiryConversation) -> Void
    var onUnpinConversation: (InquiryConversation) -> Void
    var onRemoveConversationFromStudyTopic: (InquiryConversation) -> Void
    var onDeleteConversation: (InquiryConversation) -> Void
    /// When set, the view automatically opens this topic's detail on appear.
    var requestedTopicID: UUID? = nil
    var requestedTreeSelection: StudyTopicTreeSelectionRequest? = nil
    var onConsumeTreeSelectionRequest: () -> Void = {}
    var onRefresh: () -> Void = {}
    /// Notifies the parent when a topic's detail view opens/closes, so it can
    /// disable the global edge-swipe-to-open-sidebar gesture while the local
    /// swipe-to-go-back gesture below is active.
    var onDetailVisibilityChange: (Bool) -> Void = { _ in }
    /// Reports this page's current Model Controls configuration to the app shell, which renders
    /// the shared persistent bar. Called whenever the underlying selection/canvas/confirmation
    /// state changes.
    var onControlsChange: (StudyTopicsPageControls) -> Void = { _ in }

    @State private var searchText = ""
    @State private var topics: [StudyTopic] = StudyTopicStore.load()
    @State private var activeFilter: StudyTopicFilter = .recent
    @State private var selectedTopicID: UUID? = nil
    /// Shared with StudyTopicDetailView so the external back button (below) can close
    /// the Insight Tree first, before closing the topic detail itself.
    @State private var topicCanvasMode = CanvasModeModel()
    @State private var topicBeingRenamed: StudyTopic? = nil
    @State private var topicRenameDraft: String = ""
    @State private var isExistingConversationPickerOpen = false
    @State private var pendingTreeUpdateTopicID: UUID? = nil
    @State private var topicTreeSnapshots = StudyTopicInsightTreeStore.load()
    @State private var restoredTreeInsightID: UUID? = nil
    @State private var restoredTreeTopicID: UUID? = nil
    /// Set to a newly-created topic's ID so the detail view can auto-focus its title field.
    @State private var autoFocusTopicID: UUID? = nil
    // File/photo pickers live here (not on the conditionally-shown detail view)
    // so SwiftUI can reliably present them.
    @State private var showTopicPhotoPicker = false
    @State private var showTopicFilePicker = false
    @State private var topicPhotoItems: [PhotosPickerItem] = []
    @State private var discardableNewTopicID: UUID? = nil

    private var selectedTopic: StudyTopic? {
        guard let selectedTopicID else { return nil }
        return topics.first { $0.id == selectedTopicID }
    }

    private var visibleTopics: [StudyTopic] {
        let filtered = topics
            .filter { activeFilter.matches($0) }
            .filter { topicMatchesSearch($0) }
        guard activeFilter == .recent else { return filtered }
        return filtered.sorted { $0.createdAt > $1.createdAt }
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var body: some View {
        ZStack {
            listBody

            if let topic = selectedTopic {
                StudyTopicDetailView(
                    topic: topic,
                    conversations: conversations,
                    activeConversationID: activeConversationID,
                    savedInsights: $savedInsights,
                    treeInsights: topicTreeSnapshots[topic.id.uuidString, default: []],
                    restoredTreeInsightID: restoredTreeInsightID,
                    isExistingConversationPickerOpen: $isExistingConversationPickerOpen,
                    canvasMode: topicCanvasMode,
                    modelTasks: modelTasks,
                    modelTasksPopupState: modelTasksPopupState,
                    model: model,
                    embeddingProvider: embeddingProvider,
                    insightTreeService: insightTreeService,
                    autoFocusTitle: topic.id == autoFocusTopicID,
                    onUpdateTopic: updateTopic,
                    onTopicTouched: {
                        markTopicAsTouched(topic.id)
                    },
                    onSelectConversation: onSelectConversation,
                    onNewChat: {
                        markTopicAsTouched(topic.id)
                        onNewChatInTopic(topic.id)
                    },
                    onQuoteInsightIntoNewConversation: { insight in
                        markTopicAsTouched(topic.id)
                        onQuoteInsightIntoNewConversation(insight, topic.id)
                    },
                    onQuoteInsightIntoConversation: { conversation, insight in
                        onQuoteInsightIntoConversation(conversation, insight, topic.id)
                    },
                    onAttachConversation: { conversation in
                        markTopicAsTouched(topic.id)
                        onAttachConversationToTopic(conversation, topic.id)
                    },
                    onRenameConversation: onRenameConversation,
                    onPinConversation: onPinConversation,
                    onUnpinConversation: onUnpinConversation,
                    onRemoveConversationFromStudyTopic: onRemoveConversationFromStudyTopic,
                    onDeleteConversation: onDeleteConversation,
                    onDeleteTopic: {
                        deleteTopic(topic)
                    },
                    onRemoveTreeInsight: { insight in
                        removeInsight(insight, fromTreeFor: topic.id)
                    },
                    onRestoreTreeInsight: { insight in
                        restoreInsight(insight, toTreeFor: topic.id)
                    },
                    onBack: {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                            selectedTopicID = nil
                        }
                    },
                    onRequestPhotoPicker: { showTopicPhotoPicker = true },
                    onRequestFilePicker:  { showTopicFilePicker  = true }
                )
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }

            // Single morphing nav button that floats above both layers.
            VStack {
                HStack(spacing: 8) {
                    AquinasNavButton(onMenuTap: onOpenMenu)
                    if selectedTopicID != nil && !topicCanvasMode.isCanvasStudyMode {
                        NavBackCapsuleButton(title: "Study Topics") {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                if topicCanvasMode.isTopicCanvasVisible {
                                    topicCanvasMode.isTopicCanvasVisible = false
                                } else {
                                    selectedTopicID = nil
                                }
                            }
                        }
                        .transition(.studyExitGrow)
                    }
                    if topicCanvasMode.isCanvasStudyMode {
                        StudyExitButton {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                topicCanvasMode.canvasStudyExitRequest += 1
                            }
                        }
                        .transition(.studyExitGrow)
                    }
                    Spacer()
                }
                .animation(.spring(response: 0.42, dampingFraction: 0.84), value: topicCanvasMode.isCanvasStudyMode)
                .animation(.spring(response: 0.42, dampingFraction: 0.84), value: selectedTopicID)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(true)
            .zIndex(20)
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: selectedTopicID)
        .onChange(of: selectedTopicID) { oldValue, newValue in
            if oldValue != newValue {
                discardNewTopicIfNeeded(oldValue)
            }
            modelTasksPopupState.reset()
            pendingTreeUpdateTopicID = restoredTreeTopicID == newValue ? nil : newValue
            if newValue == nil {
                isExistingConversationPickerOpen = false
            }
            onDetailVisibilityChange(newValue != nil)
            reportControls()
        }
        .onChange(of: topicCanvasMode.isTopicCanvasVisible) { _, _ in
            reportControls()
        }
        .onChange(of: pendingTreeUpdateTopicID) { _, _ in
            reportControls()
        }
        .onAppear {
            reportControls()
            let selectionRequest = requestedTreeSelection
            let targetTopicID = selectionRequest?.topicID ?? requestedTopicID
            guard let id = targetTopicID,
                  topics.contains(where: { $0.id == id }) else { return }
            restoredTreeTopicID = selectionRequest?.topicID
            restoredTreeInsightID = selectionRequest?.insightID
            if selectionRequest != nil {
                onConsumeTreeSelectionRequest()
            }
            // Brief delay so the page-in transition finishes before the detail slides in.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                    selectedTopicID = id
                    if selectionRequest != nil {
                        topicCanvasMode.isTopicCanvasVisible = true
                    }
                }
            }
        }
        .onDisappear {
            discardNewTopicIfNeeded(selectedTopicID)
        }
        .photosPicker(
            isPresented: $showTopicPhotoPicker,
            selection: $topicPhotoItems,
            maxSelectionCount: 8,
            matching: .images
        )
        .onChange(of: topicPhotoItems) { _, newItems in
            guard !newItems.isEmpty, let topic = selectedTopic else { return }
            Task {
                var added: [UploadedFile] = []
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       UploadedFile.isImageData(data) {
                        added.append(UploadedFile(
                            name: "Photo",
                            imageData: data,
                            rotationDegrees: Double.random(in: -5...5)
                        ))
                    }
                }
                await MainActor.run {
                    var updated = topic
                    updated.files.append(contentsOf: added)
                    markTopicAsTouched(topic.id)
                    updateTopic(updated)
                    topicPhotoItems.removeAll()
                }
            }
        }
        .fileImporter(
            isPresented: $showTopicFilePicker,
            allowedContentTypes: [.image, .pdf, .audio, .plainText],
            allowsMultipleSelection: true
        ) { result in
            guard let topic = selectedTopic else { return }
            switch result {
            case .success(let urls):
                var added: [UploadedFile] = []
                for url in urls {
                    let hasAccess = url.startAccessingSecurityScopedResource()
                    defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                    let data = try? Data(contentsOf: url)
                    let imageData = data.flatMap { UploadedFile.isImageData($0) ? $0 : nil }
                    added.append(UploadedFile(
                        name: url.lastPathComponent,
                        imageData: imageData,
                        rotationDegrees: Double.random(in: -5...5)
                    ))
                }
                var updated = topic
                updated.files.append(contentsOf: added)
                markTopicAsTouched(topic.id)
                updateTopic(updated)
            case .failure(let error):
                print("Failed to select file: \(error.localizedDescription)")
            }
        }
        .alert("Rename Study Topic", isPresented: topicRenameAlertBinding) {
            TextField("Topic name", text: $topicRenameDraft)
            Button("Cancel", role: .cancel) {
                topicBeingRenamed = nil
                topicRenameDraft = ""
            }
            Button("Save") {
                guard let topic = topicBeingRenamed else { return }
                let trimmed = topicRenameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    updateTopic(StudyTopic(id: topic.id, title: trimmed, description: topic.description, files: topic.files))
                }
                topicBeingRenamed = nil
                topicRenameDraft = ""
            }
        }
    }

    private var topicRenameAlertBinding: Binding<Bool> {
        Binding(
            get: { topicBeingRenamed != nil },
            set: { isPresented in
                if !isPresented {
                    topicBeingRenamed = nil
                    topicRenameDraft = ""
                }
            }
        )
    }

    @ViewBuilder private var listBody: some View {
        ZStack(alignment: .bottomTrailing) {
            AquinasTheme.Colors.canvas
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 72)

                    VStack(alignment: .center, spacing: 8) {
                        Text(todayString())
                            .font(AquinasTheme.Typography.uiLabel)
                            .foregroundColor(AquinasTheme.Colors.lightGreen)

                        Text("Study Topics")
                            .font(.custom("LibreBaskerville-Regular", size: 30))
                            .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 28)

                    StudyTopicsSearchField(
                        searchText: $searchText,
                        prompt: Text("Search Study Topcis")
                    )
                        .padding(.top, 28)

                    HStack(spacing: 24) {
                        ForEach(StudyTopicFilter.allCases) { filter in
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

                        Spacer(minLength: 8)
                    }
                    .padding(.top, 16)

                    LazyVStack(alignment: .leading, spacing: 16) {
                        if visibleTopics.isEmpty {
                            StudyTopicsEmptyState(hasAnyTopics: !topics.isEmpty)
                                .padding(.top, 8)
                        } else if activeFilter == .date {
                            sectionedTopicList(dateGroupedTopicSections(visibleTopics))
                                .id("date")
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        } else {
                            ForEach(visibleTopics) { topic in
                                topicCard(topic)
                            }
                            .id("recent")
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }
                    }
                    .padding(.top, 48)
                    .padding(.bottom, 120)
                    .animation(.spring(response: 0.34, dampingFraction: 0.86), value: normalizedSearchText)
                    .animation(.spring(response: 0.34, dampingFraction: 0.86), value: activeFilter)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .refreshable {
                refreshContent()
            }

        }
    }

    @ViewBuilder
    private func topicCard(_ topic: StudyTopic) -> some View {
        StudyTopicCard(
            topic: topic,
            subItems: topicSubItems(for: topic),
            subItemTitle: { conversationTitle($0) },
            onSelect: {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                    selectedTopicID = topic.id
                }
            },
            onRename: {
                topicRenameDraft = topic.title
                topicBeingRenamed = topic
            },
            onDelete: { deleteTopic(topic) },
            onSelectSubItem: { conversation in
                onSelectConversation(conversation)
            }
        )
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .bottom)),
                removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
            )
        )
    }

    @ViewBuilder
    private func sectionedTopicList(_ sections: [StudyTopicSection]) -> some View {
        ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
            VStack(alignment: .leading, spacing: 16) {
                AquinasSectionTitle(section.title)

                ForEach(section.topics) { topic in
                    topicCard(topic)
                }
            }

            if index < sections.count - 1 {
                AquinasSectionDivider()
                    .padding(.vertical, 8)
            }
        }
    }

    /// Groups topics by the calendar day they were created, most recent day first.
    private func dateGroupedTopicSections(_ list: [StudyTopic]) -> [StudyTopicSection] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: list) { calendar.startOfDay(for: $0.createdAt) }
        return groups.keys.sorted(by: >).map { day in
            StudyTopicSection(
                id: "date-\(day.timeIntervalSince1970)",
                title: dayLabel(for: day),
                topics: (groups[day] ?? []).sorted { $0.createdAt > $1.createdAt }
            )
        }
    }

    private func dayLabel(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.month(.wide).day().year())
    }

    private func refreshContent() {
        topics = StudyTopicStore.load()
        onRefresh()
    }

    private func createStudyTopic() {
        let topic = StudyTopic()
        topics.insert(topic, at: 0)
        StudyTopicStore.save(topics)
        autoFocusTopicID = topic.id
        discardableNewTopicID = topic.id
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            selectedTopicID = topic.id
        }
    }

    private func performPrimaryControlAction() {
        if let selectedTopicID {
            markTopicAsTouched(selectedTopicID)
            onNewChatInTopic(selectedTopicID)
        } else {
            createStudyTopic()
        }
    }

    private func reportControls() {
        onControlsChange(
            StudyTopicsPageControls(
                isVisible: !topicCanvasMode.isTopicCanvasVisible,
                actionTitle: selectedTopicID == nil ? "New Study Topic" : "New Conversation",
                secondaryActionTitle: selectedTopicID == nil ? nil : "Add Conversation",
                action: performPrimaryControlAction,
                secondaryAction: {
                    if let selectedTopicID {
                        markTopicAsTouched(selectedTopicID)
                    }
                    isExistingConversationPickerOpen = true
                },
                confirmationTitle: treeUpdateConfirmationTitle,
                onConfirm: updateSelectedTopicTree,
                onDecline: dismissTreeUpdateConfirmation
            )
        )
    }

    private var treeUpdateConfirmationTitle: String? {
        guard let pendingTreeUpdateTopicID,
              pendingTreeUpdateTopicID == selectedTopicID,
              let topic = topics.first(where: { $0.id == pendingTreeUpdateTopicID }) else {
            return nil
        }
        return "Update Tree for \(displayTitle(for: topic))?"
    }

    private func updateSelectedTopicTree() {
        guard let topicID = pendingTreeUpdateTopicID,
              topicID == selectedTopicID else {
            return
        }

        let aggregatedInsights = StudyTopicInsightTreeBuilder.snapshot(
            topicID: topicID,
            conversations: reconciledConversations,
            savedInsights: savedInsights
        )

        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            topicTreeSnapshots[topicID.uuidString] = aggregatedInsights
            pendingTreeUpdateTopicID = nil
        }
        StudyTopicInsightTreeStore.save(topicTreeSnapshots)
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
    }

    private func removeInsight(_ insight: ConceptDefinition, fromTreeFor topicID: UUID) {
        savedInsights.removeAll { $0.id == insight.id }
        topicTreeSnapshots[topicID.uuidString, default: []].removeAll { $0.id == insight.id }
        StudyTopicInsightTreeStore.save(topicTreeSnapshots)
    }

    private func restoreInsight(_ insight: ConceptDefinition, toTreeFor topicID: UUID) {
        if !savedInsights.contains(where: { $0.id == insight.id }) {
            savedInsights.append(insight)
        }
        if !topicTreeSnapshots[topicID.uuidString, default: []].contains(where: { $0.id == insight.id }) {
            topicTreeSnapshots[topicID.uuidString, default: []].append(insight)
        }
        StudyTopicInsightTreeStore.save(topicTreeSnapshots)
    }

    private func dismissTreeUpdateConfirmation() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            pendingTreeUpdateTopicID = nil
        }
    }

    /// Prefer the live shell copy, then fill any gaps from the persisted conversation store.
    private var reconciledConversations: [InquiryConversation] {
        let persisted = CurrentConversationsStore.load()?.conversations ?? []
        var byID: [UUID: InquiryConversation] = [:]
        for conversation in persisted {
            byID[conversation.id] = conversation
        }
        for conversation in conversations {
            byID[conversation.id] = conversation
        }
        return Array(byID.values)
    }

    private func updateTopic(_ topic: StudyTopic) {
        guard let index = topics.firstIndex(where: { $0.id == topic.id }) else { return }
        topics[index] = topic
        StudyTopicStore.save(topics)
    }

    private func markTopicAsTouched(_ topicID: UUID) {
        if discardableNewTopicID == topicID {
            discardableNewTopicID = nil
        }
    }

    private func discardNewTopicIfNeeded(_ topicID: UUID?) {
        guard let topicID,
              discardableNewTopicID == topicID,
              let topic = topics.first(where: { $0.id == topicID }) else {
            return
        }

        discardableNewTopicID = nil
        guard isBlankTopic(topic), !hasConversations(in: topic) else { return }

        topics.removeAll { $0.id == topicID }
        StudyTopicStore.save(topics)
        topicTreeSnapshots.removeValue(forKey: topicID.uuidString)
        StudyTopicInsightTreeStore.save(topicTreeSnapshots)
        if autoFocusTopicID == topicID {
            autoFocusTopicID = nil
        }
        if selectedTopicID == topicID {
            selectedTopicID = nil
        }
    }

    private func isBlankTopic(_ topic: StudyTopic) -> Bool {
        topic.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && topic.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && topic.files.isEmpty
    }

    private func deleteTopic(_ topic: StudyTopic) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            topics.removeAll { $0.id == topic.id }
        }
        StudyTopicStore.save(topics)
        if discardableNewTopicID == topic.id {
            discardableNewTopicID = nil
        }
        topicTreeSnapshots.removeValue(forKey: topic.id.uuidString)
        StudyTopicInsightTreeStore.save(topicTreeSnapshots)
        // If the deleted topic was selected, close the detail view.
        if selectedTopicID == topic.id {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                selectedTopicID = nil
            }
        }
    }

    private func hasConversations(in topic: StudyTopic) -> Bool {
        conversations.contains { $0.studyTopicID == topic.id }
    }

    private func topicSubItems(for topic: StudyTopic) -> [InquiryConversation] {
        conversations
            .filter { $0.studyTopicID == topic.id }
            .filter { !conversationTitle($0).isEmpty }
    }

    private func topicMatchesSearch(_ topic: StudyTopic) -> Bool {
        guard !normalizedSearchText.isEmpty else { return true }
        let subItemTitles = topicSubItems(for: topic).map { conversationTitle($0) }
        let text = ([displayTitle(for: topic), topic.description] + subItemTitles)
            .joined(separator: " ")
            .lowercased()
        return text.contains(normalizedSearchText)
    }

    private func displayTitle(for topic: StudyTopic) -> String {
        let trimmed = topic.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Study Topic" : trimmed
    }

    private func todayString(date: Date = Date()) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }

    private func conversationTitle(_ conversation: InquiryConversation) -> String {
        let trimmedTitle = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle != "New Conversation", !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        for branch in conversation.branches {
            let title = branch.generatedBranchTitle
                ?? branch.topQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { return title }
        }
        return trimmedTitle
    }
}

// MARK: - Study Topic Detail

struct StudyTopicDetailView: View {
    let topic: StudyTopic
    let conversations: [InquiryConversation]
    let activeConversationID: UUID?
    @Binding var savedInsights: [ConceptDefinition]
    let treeInsights: [ConceptDefinition]
    let restoredTreeInsightID: UUID?
    @Binding var isExistingConversationPickerOpen: Bool
    var onUpdateTopic: (StudyTopic) -> Void
    var onTopicTouched: () -> Void
    var onSelectConversation: (InquiryConversation) -> Void
    var onNewChat: () -> Void
    var onQuoteInsightIntoNewConversation: (ConceptDefinition) -> Void
    var onQuoteInsightIntoConversation: (InquiryConversation, ConceptDefinition) -> Void
    var onAttachConversation: (InquiryConversation) -> Void
    var onRenameConversation: (InquiryConversation, String) -> Void
    var onPinConversation: (InquiryConversation) -> Void
    var onUnpinConversation: (InquiryConversation) -> Void
    var onRemoveConversationFromStudyTopic: (InquiryConversation) -> Void
    var onDeleteConversation: (InquiryConversation) -> Void
    var onDeleteTopic: () -> Void
    var onRemoveTreeInsight: (ConceptDefinition) -> Void
    var onRestoreTreeInsight: (ConceptDefinition) -> Void
    var onBack: () -> Void
    /// Owned by the parent StudyTopicsView so its shared back button can close the
    /// Insight Tree before closing this detail view.
    let canvasMode: CanvasModeModel
    let modelTasks: ModelTaskQueue
    let modelTasksPopupState: ModelTasksPopupState
    let model: AquinasModel
    let embeddingProvider: EmbeddingProvider
    let insightTreeService: InsightTreeService

    @State private var activeInsight: ConceptDefinition? = nil
    @State private var pickerActiveInsight: ConceptDefinition? = nil
    @State private var quotePickerInsight: ConceptDefinition? = nil
    @State private var isInsightAskMode: Bool = false
    @State private var conversationBeingRenamed: InquiryConversation? = nil
    @State private var deletingConversationIDs: Set<UUID> = []
    @State private var renameDraft = ""
    @State private var titleDraft: String
    @State private var descriptionDraft: String
    @State private var topicSearchText = ""
    @State private var localFiles: [UploadedFile]
    @State private var isTitleFocused: Bool = false

    // MARK: Insight Tree (Canvas Mode, scoped to this topic's saved insights)
    @State private var insightSelectedPersonality = "Balanced"
    @State private var insightIsPersonalityMenuOpen = false
    @State private var insightShowFilePicker = false
    @State private var insightShowPhotoPicker = false
    @State private var insightShowCamera = false
    @State private var insightContextCardState = ContextCardState()
    @State private var persistedTreeRefreshRequest = 0

    init(
        topic: StudyTopic,
        conversations: [InquiryConversation],
        activeConversationID: UUID?,
        savedInsights: Binding<[ConceptDefinition]>,
        treeInsights: [ConceptDefinition],
        restoredTreeInsightID: UUID?,
        isExistingConversationPickerOpen: Binding<Bool>,
        canvasMode: CanvasModeModel,
        modelTasks: ModelTaskQueue,
        modelTasksPopupState: ModelTasksPopupState,
        model: AquinasModel,
        embeddingProvider: EmbeddingProvider,
        insightTreeService: InsightTreeService,
        autoFocusTitle: Bool = false,
        onUpdateTopic: @escaping (StudyTopic) -> Void,
        onTopicTouched: @escaping () -> Void = {},
        onSelectConversation: @escaping (InquiryConversation) -> Void,
        onNewChat: @escaping () -> Void,
        onQuoteInsightIntoNewConversation:
            @escaping (ConceptDefinition) -> Void,
        onQuoteInsightIntoConversation:
            @escaping (InquiryConversation, ConceptDefinition) -> Void,
        onAttachConversation: @escaping (InquiryConversation) -> Void,
        onRenameConversation: @escaping (InquiryConversation, String) -> Void,
        onPinConversation: @escaping (InquiryConversation) -> Void,
        onUnpinConversation: @escaping (InquiryConversation) -> Void,
        onRemoveConversationFromStudyTopic: @escaping (InquiryConversation) -> Void,
        onDeleteConversation: @escaping (InquiryConversation) -> Void,
        onDeleteTopic: @escaping () -> Void,
        onRemoveTreeInsight: @escaping (ConceptDefinition) -> Void,
        onRestoreTreeInsight: @escaping (ConceptDefinition) -> Void,
        onBack: @escaping () -> Void,
        onRequestPhotoPicker: @escaping () -> Void = {},
        onRequestFilePicker: @escaping () -> Void = {}
    ) {
        self.topic = topic
        self.conversations = conversations
        self.activeConversationID = activeConversationID
        self._savedInsights = savedInsights
        self.treeInsights = treeInsights
        self.restoredTreeInsightID = restoredTreeInsightID
        self._isExistingConversationPickerOpen = isExistingConversationPickerOpen
        self.canvasMode = canvasMode
        self.modelTasks = modelTasks
        self.modelTasksPopupState = modelTasksPopupState
        self.model = model
        self.embeddingProvider = embeddingProvider
        self.insightTreeService = insightTreeService
        self.autoFocusTitle = autoFocusTitle
        self.onUpdateTopic = onUpdateTopic
        self.onTopicTouched = onTopicTouched
        self.onSelectConversation = onSelectConversation
        self.onNewChat = onNewChat
        self.onQuoteInsightIntoNewConversation = onQuoteInsightIntoNewConversation
        self.onQuoteInsightIntoConversation = onQuoteInsightIntoConversation
        self.onAttachConversation = onAttachConversation
        self.onRenameConversation = onRenameConversation
        self.onPinConversation = onPinConversation
        self.onUnpinConversation = onUnpinConversation
        self.onRemoveConversationFromStudyTopic = onRemoveConversationFromStudyTopic
        self.onDeleteConversation = onDeleteConversation
        self.onDeleteTopic = onDeleteTopic
        self.onRemoveTreeInsight = onRemoveTreeInsight
        self.onRestoreTreeInsight = onRestoreTreeInsight
        self.onBack = onBack
        self.onRequestPhotoPicker = onRequestPhotoPicker
        self.onRequestFilePicker = onRequestFilePicker
        self._titleDraft = State(initialValue: topic.title)
        self._descriptionDraft = State(initialValue: topic.description)
        self._localFiles = State(initialValue: topic.files)
    }

    let autoFocusTitle: Bool
    let onRequestPhotoPicker: () -> Void
    let onRequestFilePicker: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            AquinasTheme.Colors.canvas
                .ignoresSafeArea()

            let topicConversations = filteredTopicConversations

            GeometryReader { geometry in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Spacer behind the floating hamburger button.
                        Color.clear.frame(height: 72)

                        VStack(alignment: .leading, spacing: 48) {
                            VStack(alignment: .leading, spacing: 8) {
                                StudyTopicTitleTextView(
                                    placeholder: "New Study Topic",
                                    text: $titleDraft,
                                    isFocused: $isTitleFocused,
                                    lineSpacing: 18
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .onChange(of: titleDraft) { _, _ in persistDrafts() }

                                /*
                                Menu {
                                    Button("Rename", systemImage: "pencil.line") {
                                        isTitleFocused = true
                                    }
                                    Button("Upload Image", systemImage: "photo") {
                                        onRequestPhotoPicker()
                                    }
                                    Button("Upload File", systemImage: "doc") {
                                        onRequestFilePicker()
                                    }
                                    Divider()
                                    Button("Delete Topic", systemImage: "trash", role: .destructive) {
                                        onDeleteTopic()
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
                                .accessibilityLabel("Topic options")
                                */

                                placeholderTextField(
                                    placeholder: "Briefly describe the topic of this study",
                                    text: $descriptionDraft,
                                    font: .custom("Figtree-Regular", size: 14),
                                    color: AquinasTheme.Colors.paragraphText,
                                    emptyOpacity: 0.5,
                                    lineLimit: 1...4,
                                    lineSpacing: 7
                                )
                                .onChange(of: descriptionDraft) { _, _ in persistDrafts() }

                                StudyTopicsSearchField(
                                    searchText: $topicSearchText,
                                    prompt: Text("Search in \(Text(displayTopicTitle).italic())")
                                )
                                .padding(.top, 8)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            // Files section — only shown when at least one file has been uploaded.
                            if !localFiles.isEmpty {
                                StudyTopicFilesSection(
                                    files: localFiles,
                                    onRemove: { file in
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                            localFiles.removeAll { $0.id == file.id }
                                        }
                                        persistDrafts()
                                    }
                                )
                            }

                            if !topicConversations.isEmpty {
                                LazyVStack(spacing: 16) {
                                    ForEach(topicConversations) { conversation in
                                        OpenConversationCard(
                                            conversation: conversation,
                                            isActive: conversation.id == activeConversationID,
                                            latestAnswer: latestAnswer(in: conversation),
                                            insights: insights(for: conversation),
                                            onSelect: { onSelectConversation(conversation) },
                                            onOpenInsight: { insight in activeInsight = insight },
                                            onRename: { conv in
                                                renameDraft = conv.title
                                                conversationBeingRenamed = conv
                                            },
                                            onPin: { conv in
                                                onPinConversation(conv)
                                            },
                                            onUnpin: { conv in
                                                onUnpinConversation(conv)
                                            },
                                            onRemoveFromStudyTopic: { conv in
                                                onRemoveConversationFromStudyTopic(conv)
                                            },
                                            onDelete: { conv in
                                                deleteConversationCard(conv)
                                            }
                                        )
                                        .opacity(deletingConversationIDs.contains(conversation.id) ? 0 : 1)
                                        .blur(radius: deletingConversationIDs.contains(conversation.id) ? 12 : 0)
                                        .transition(
                                            .asymmetric(
                                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                                removal: .blurFade
                                            )
                                        )
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .animation(.spring(response: 0.34, dampingFraction: 0.86), value: normalizedTopicSearchText)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 24)

                        Color.clear.frame(height: 120)
                    }
                    .frame(width: max(0, geometry.size.width - 48), alignment: .leading)
                    .padding(.horizontal, 24)
                    .frame(width: geometry.size.width, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollClipDisabled()
            }

            // Insight Tree: saved insights from this topic's conversations.
            if canvasMode.isTopicCanvasVisible {
                topicInsightTreeLayer
            }

            // Top-right entry into the topic's Insight Tree. Fades/scales/blurs away once
            // inside — the shared back button (top-left) handles exiting, so there's no
            // second "back" affordance competing for the same corner.
            if !canvasMode.isTopicCanvasVisible {
                VStack {
                    HStack {
                        Spacer()
                        CanvasModeToggleButton(isActive: false, action: enterInsightTree)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    Spacer()
                }
                .zIndex(7)
                .transition(.canvasToggleFade)
            }

        }
        .task(id: autoFocusTitle) {
            guard autoFocusTitle else { return }
            // Wait for the slide-in transition to finish before stealing first responder.
            try? await Task.sleep(for: .milliseconds(550))
            isTitleFocused = true
        }
        // Swipe right to go back, swipe left to enter the Insight Tree.
        .simultaneousGesture(
            DragGesture(minimumDistance: 18)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width > 60 {
                        if canvasMode.isTopicCanvasVisible {
                            closeInsightTree()
                        } else {
                            onBack()
                        }
                    } else if value.translation.width < -60 && !canvasMode.isTopicCanvasVisible {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        enterInsightTree()
                    }
                }
        )
        .safeAreaInset(edge: .bottom) {
            if canvasMode.isTopicCanvasVisible {
                insightControlDock
            }
        }
        .sheet(item: $activeInsight) { insight in
            ConceptSheetContent(concept: insight, collectedDefinitions: $savedInsights)
                .presentationDetents([.height(340), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(AquinasTheme.Colors.canvas)
        }
        .sheet(item: $quotePickerInsight) { insight in
            InsightConversationPickerSheet(
                title: "Existing Conversations",
                searchPrompt: "Search in \(displayTopicTitle)",
                emptyMessage: "This Study Topic does not have a matching conversation.",
                conversations: topicConversationsForQuote,
                activeConversationID: activeConversationID,
                savedInsights: savedInsights,
                onSelect: { conversation in
                    quotePickerInsight = nil
                    onQuoteInsightIntoConversation(conversation, insight)
                },
                onCancel: {
                    quotePickerInsight = nil
                }
            )
            .presentationDetents([.height(520), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(AquinasTheme.Colors.canvas)
        }
        .sheet(isPresented: $isExistingConversationPickerOpen) {
            ExistingConversationPickerSheet(
                // Only offer conversations that aren't already attached to a topic.
                conversations: conversations.filter { $0.studyTopicID == nil },
                activeConversationID: activeConversationID,
                savedInsights: $savedInsights,
                onSelectConversation: { conversation in
                    onAttachConversation(conversation)
                    isExistingConversationPickerOpen = false
                },
                onOpenInsight: { insight in
                    pickerActiveInsight = insight
                },
                onRenameConversation: { conversation, title in
                    onRenameConversation(conversation, title)
                },
                onPinConversation: onPinConversation,
                onUnpinConversation: onUnpinConversation,
                onRemoveConversationFromStudyTopic: onRemoveConversationFromStudyTopic,
                onDeleteConversation: onDeleteConversation
            )
            .presentationDetents([.height(420), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(AquinasTheme.Colors.canvas)
        }
        .sheet(item: $pickerActiveInsight) { insight in
            ConceptSheetContent(concept: insight, collectedDefinitions: $savedInsights)
                .presentationDetents([.height(340), .large])
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
        // Sync localFiles when the parent pushes new files in (e.g. after a photo/file pick).
        .onChange(of: topic.files) { _, newFiles in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                localFiles = newFiles
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

    private var displayTopicTitle: String {
        let trimmedDraft = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDraft.isEmpty { return trimmedDraft }

        let trimmedTitle = topic.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "Study Topic" : trimmedTitle
    }

    private var normalizedTopicSearchText: String {
        topicSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var topicConversationsForQuote: [InquiryConversation] {
        conversations
            .filter { $0.studyTopicID == topic.id }
            .sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.createdAt > $1.createdAt
            }
    }

    private var filteredTopicConversations: [InquiryConversation] {
        let topicConversations = conversations.filter { $0.studyTopicID == topic.id }
        guard !normalizedTopicSearchText.isEmpty else { return topicConversations }

        return topicConversations.filter { conversation in
            let insightWords = insights(for: conversation).map(\.word).joined(separator: " ")
            let text = [
                conversation.title,
                latestAnswer(in: conversation),
                insightWords,
                searchableText(conversation)
            ].joined(separator: " ").lowercased()

            return text.contains(normalizedTopicSearchText)
        }
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

    private func placeholderTextField(
        placeholder: String,
        text: Binding<String>,
        font: Font,
        color: Color,
        emptyOpacity: Double,
        lineLimit: ClosedRange<Int>,
        lineSpacing: CGFloat = 0,
        minimumHeight: CGFloat? = nil,
        focusBinding: FocusState<Bool>.Binding? = nil
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Text(text.wrappedValue.isEmpty ? placeholder : text.wrappedValue)
                .font(font)
                .lineSpacing(lineSpacing)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .allowsHitTesting(false)

            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(font)
                    .lineSpacing(lineSpacing)
                    .foregroundColor(color.opacity(emptyOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .allowsHitTesting(false)
            }

            if let focusBinding {
                TextField("", text: text, axis: .vertical)
                    .font(font)
                    .foregroundColor(color)
                    .tint(AquinasTheme.Colors.secondaryMuted)
                    .lineSpacing(lineSpacing)
                    .lineLimit(lineLimit)
                    .scrollDisabled(true)
                    .fixedSize(horizontal: false, vertical: true)
                    .focused(focusBinding)
                    .onChange(of: text.wrappedValue) { _, newValue in
                        guard newValue.contains("\n") else { return }
                        text.wrappedValue = newValue.replacingOccurrences(of: "\n", with: "")
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
            } else {
                TextField("", text: text, axis: .vertical)
                    .font(font)
                    .foregroundColor(color)
                    .tint(AquinasTheme.Colors.secondaryMuted)
                    .lineSpacing(lineSpacing)
                    .lineLimit(lineLimit)
                    .scrollDisabled(true)
                    .fixedSize(horizontal: false, vertical: true)
                    .onChange(of: text.wrappedValue) { _, newValue in
                        guard newValue.contains("\n") else { return }
                        text.wrappedValue = newValue.replacingOccurrences(of: "\n", with: "")
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
            }
        }
        .frame(minHeight: minimumHeight, alignment: .topLeading)
    }

    private func persistDrafts() {
        onTopicTouched()
        onUpdateTopic(
            StudyTopic(
                id: topic.id,
                title: titleDraft,
                description: descriptionDraft,
                files: localFiles
            )
        )
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

    // MARK: Insight Tree

    private func enterInsightTree() {
        onTopicTouched()
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            canvasMode.isTopicCanvasVisible = true
        }
    }

    private func closeInsightTree() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            canvasMode.isTopicCanvasVisible = false
        }
    }

    /// Forking an insight from the topic canvas starts a new conversation in this topic.
    private func forkTopicInsight(_ concept: ConceptDefinition) {
        closeInsightTree()
        onNewChat()
    }

    private func toggleSavedInsight(_ concept: ConceptDefinition) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if savedInsights.contains(where: { $0.id == concept.id }) {
                removeTopicTreeInsight(concept)
            } else {
                restoreTopicTreeInsight(concept)
            }
        }
    }

    private func removeTopicTreeInsight(_ concept: ConceptDefinition) {
        onRemoveTreeInsight(concept)
        modelTasks.enqueue(
            kind: .refreshInsightTree,
            originPage: .studyTopics,
            conversationID: topic.id,
            priority: .background
        ) {
            guard AquinasBackendConfiguration.canRecoverFromCurrentDevice else { return }
            do {
                try await insightTreeService.remove(insightID: concept.id, from: topic.id)
                guard !Task.isCancelled else { return }
                persistedTreeRefreshRequest += 1
                await Task.yield()
            } catch {
                // The accepted topic snapshot is durable and will reconcile on the next load.
            }
        }
    }

    private func restoreTopicTreeInsight(_ concept: ConceptDefinition) {
        onRestoreTreeInsight(concept)
        modelTasks.enqueue(
            kind: .refreshInsightTree,
            originPage: .studyTopics,
            conversationID: topic.id,
            priority: .background
        ) {
            guard AquinasBackendConfiguration.canRecoverFromCurrentDevice else { return }
            do {
                let suggestedNodeLabel = try await model.labelSubject(
                    forTitles: ["\(concept.word): \(concept.semanticDefinition)"]
                )
                _ = try await insightTreeService.save(
                    concept,
                    to: topic.id,
                    suggestedNodeLabel: suggestedNodeLabel
                )
                guard !Task.isCancelled else { return }
                persistedTreeRefreshRequest += 1
                await Task.yield()
            } catch {
                // The accepted topic snapshot is durable and will reconcile on the next load.
            }
        }
    }

    @ViewBuilder
    private var topicInsightTreeLayer: some View {
        InsightTreeView(
            insights: treeInsights,
            conversationID: topic.id,
            selectionRequest: canvasMode.canvasSelectionRequest,
            persistedTreeRefreshRequest: persistedTreeRefreshRequest,
            clearSelectionRequest: canvasMode.canvasClearSelectionRequest,
            dismissHoverRequest: canvasMode.canvasDismissHoverRequest,
            createConceptRequest: canvasMode.canvasCreateConceptRequest,
            studyRequest: canvasMode.canvasStudyRequest,
            studyExitRequest: canvasMode.canvasStudyExitRequest,
            studyToolsToggleRequest: canvasMode.canvasStudyToolsToggleRequest,
            studyBranchCount: canvasMode.canvasStudyBranchCount,
            onStudyModeChange: { canvasMode.isCanvasStudyMode = $0 },
            onStudyToolsActiveChange: { canvasMode.isCanvasStudyToolsActive = $0 },
            onStudyBranchCountChange: { canvasMode.canvasStudyBranchCount = $0 },
            restoreSelectedInsightID: restoredTreeInsightID,
            promotedInsightIDs: canvasMode.promotedCanvasInsightIDs,
            onRemoveInsight: removeTopicTreeInsight,
            onRestoreInsight: restoreTopicTreeInsight,
            onForkInsight: forkTopicInsight,
            onQuoteInsight: { insight in
                canvasMode.canvasQuoteTarget = insight
                if insight == nil { isInsightAskMode = false }
            },
            onSelectionStateChange: { canvasMode.hasCanvasHover = $0 },
            onInsightSelectionStateChange: { canvasMode.hasHoveredCanvasInsight = $0 },
            onSelectedCanvasItemCountChange: { canvasMode.canvasSelectedItemCount = $0 },
            onPromotedInsightIDsChange: { canvasMode.promotedCanvasInsightIDs = $0 },
            savedConceptIDs: Set(treeInsights.map(\.id)),
            onToggleSavedConcept: toggleSavedInsight,
            onBookmarkConcepts: { concepts in
                for concept in concepts
                where !treeInsights.contains(where: { $0.id == concept.id }) {
                    restoreTopicTreeInsight(concept)
                }
            },
            inquireConnectionRequest: canvasMode.canvasInquireConnectionRequest,
            onInquireConnectionConcepts: { concepts in
                guard let first = concepts.first else { return }
                forkTopicInsight(first)
            },
            midpointEnterRequest: canvasMode.canvasMidpointEnterRequest,
            midpointCenterRequest: canvasMode.canvasMidpointCenterRequest,
            midpointPlaceRequest: canvasMode.canvasMidpointPlaceRequest,
            onMidpointModeChange: { canvasMode.isCanvasMidpointMode = $0 },
            onMidpointGeneratingChange: { canvasMode.isCanvasInsightGenerating = $0 },
            showQuestionBar: false,
            modelTasks: modelTasks,
            modelTaskOriginPage: .studyTopics,
            model: model,
            embeddingProvider: embeddingProvider,
            insightTreeService: insightTreeService,
            reconcilesPersistedSavedInsights: true
        )
        .transition(.move(edge: .trailing).combined(with: .opacity))
        .zIndex(5)
    }

    @ViewBuilder
    private var insightControlDock: some View {
        InquiryControlDock(
            isCanvasMode: true,
            showFilePicker: $insightShowFilePicker,
            showPhotoPicker: $insightShowPhotoPicker,
            showCamera: $insightShowCamera,
            selectedPersonality: $insightSelectedPersonality,
            isPersonalityMenuOpen: $insightIsPersonalityMenuOpen,
            isAtBottom: true,
            hasCanvasHover: canvasMode.hasCanvasHover,
            hasCanvasInsightHover: canvasMode.hasHoveredCanvasInsight,
            hasSelectedCanvasItems: canvasMode.canvasSelectedItemCount > 0,
            selectedCanvasItemCount: canvasMode.canvasSelectedItemCount,
            onScrollToBottom: {},
            onViewEntireCanvas: {},
            onOpenInsights: {},
            onSelectCanvasItem: { canvasMode.canvasSelectionRequest += 1 },
            onCreateCanvasConcept: { canvasMode.canvasCreateConceptRequest += 1 },
            onStudyCanvasInsight: { canvasMode.canvasStudyRequest += 1 },
            onInquireConnection: { canvasMode.canvasInquireConnectionRequest += 1 },
            onQuoteCanvasItem: {
                guard canvasMode.canvasQuoteTarget != nil else { return }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    isInsightAskMode = true
                }
            },
            usesCanvasAskFlow: true,
            isCanvasAskMode: isInsightAskMode,
            onAskInNewConversation: {
                guard let insight = canvasMode.canvasQuoteTarget else { return }
                isInsightAskMode = false
                onQuoteInsightIntoNewConversation(insight)
            },
            onAskInExistingConversation: {
                guard let insight = canvasMode.canvasQuoteTarget else { return }
                quotePickerInsight = insight
            },
            onCancelCanvasAsk: {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    isInsightAskMode = false
                }
            },
            onMidpointConcepts: { canvasMode.canvasMidpointEnterRequest += 1 },
            isMidpointMode: canvasMode.isCanvasMidpointMode,
            isStudyMode: canvasMode.isCanvasStudyMode,
            isStudyToolsActive: canvasMode.isCanvasStudyToolsActive,
            onToggleStudyTools: { canvasMode.canvasStudyToolsToggleRequest += 1 },
            studyBranchCount: canvasMode.canvasStudyBranchCount,
            onStudyBranchCountChange: { canvasMode.canvasStudyBranchCount = $0 },
            isCanvasInsightLoading: canvasMode.isCanvasInsightGenerating,
            modelTasks: modelTasks,
            modelTasksPopupState: modelTasksPopupState,
            onMidpointCenter: { canvasMode.canvasMidpointCenterRequest += 1 },
            onMidpointPlace: { canvasMode.canvasMidpointPlaceRequest += 1 },
            onClearCanvasSelection: { canvasMode.canvasClearSelectionRequest += 1 },
            onContextWillOpen: {
                if canvasMode.isTopicCanvasVisible { canvasMode.canvasDismissHoverRequest += 1 }
            },
            contextCard: insightContextCardState
        )
    }
}

// MARK: - Existing Conversation Picker

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

private struct AddButtonEntranceModifier: ViewModifier {
    let scale: CGFloat
    let opacity: Double
    let blurRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .blur(radius: blurRadius)
    }
}

private extension AnyTransition {
    /// Scales down from 1.1 → 1, fades 0 → 1 opacity, and un-blurs 4pt → 0pt.
    /// Symmetric, so removal automatically plays the same recipe in reverse.
    static var addButtonEntrance: AnyTransition {
        .modifier(
            active: AddButtonEntranceModifier(scale: 1.1, opacity: 0, blurRadius: 4),
            identity: AddButtonEntranceModifier(scale: 1, opacity: 1, blurRadius: 0)
        )
    }

    /// Scales up 5%, blurs by 8pt, and fades to 0 opacity. Symmetric, so the button
    /// reverses the same recipe on the way back in.
    static var canvasToggleFade: AnyTransition {
        .modifier(
            active: AddButtonEntranceModifier(scale: 1.05, opacity: 0, blurRadius: 8),
            identity: AddButtonEntranceModifier(scale: 1, opacity: 1, blurRadius: 0)
        )
    }
}

private struct ExistingConversationPickerSheet: View {
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

// MARK: - Search Field

struct StudyTopicsSearchField: View {
    @Binding var searchText: String
    var prompt: Text = Text("Search")
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AquinasTheme.Colors.lightGreen)
                .frame(width: 16, height: 16)

            TextField("", text: $searchText, prompt: prompt)
                .font(AquinasTheme.Typography.body)
                .foregroundColor(AquinasTheme.Colors.paragraphText)
                .tint(AquinasTheme.Colors.secondaryMuted)
                .submitLabel(.search)
                .focused($isFocused)
                .onSubmit { isFocused = false }
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

// MARK: - Filters

private struct StudyTopicSection: Identifiable {
    let id: String
    let title: String
    let topics: [StudyTopic]
}

private enum StudyTopicFilter: String, CaseIterable, Identifiable, Equatable {
    case recent, date

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: return "Recent"
        case .date: return "Date"
        }
    }

    func matches(_ topic: StudyTopic) -> Bool {
        switch self {
        case .recent, .date:
            return true
        }
    }
}

// MARK: - Empty State

private struct StudyTopicsEmptyState: View {
    let hasAnyTopics: Bool

    var body: some View {
        if hasAnyTopics {
            AquinasEmptyState(
                systemImage: "magnifyingglass",
                title: "No Matches Found",
                message: "Try a different search term."
            )
        } else {
            AquinasEmptyState(
                systemImage: "book.closed",
                title: "Gather your studies here",
                message: "Create a study topic to organize conversations, insights, and files around a single subject."
            )
        }
    }
}

// MARK: - Topic Card (list view)

private struct StudyTopicCard: View {
    let topic: StudyTopic
    let subItems: [InquiryConversation]
    var subItemTitle: (InquiryConversation) -> String
    var onSelect: () -> Void
    var onRename: () -> Void = {}
    var onDelete: () -> Void = {}
    var onSelectSubItem: (InquiryConversation) -> Void = { _ in }

    @State private var isExpanded = false
    @State private var isShowingLongPressFeedback = false

    private let longPressDuration: TimeInterval = 0.25

    private var visibleSubItems: [InquiryConversation] {
        isExpanded ? subItems : Array(subItems.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header: title + options button
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.stack")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AquinasTheme.Colors.lightGreen)

                        Text(displayTitle)
                            .font(.custom("Figtree-Bold", size: 18))
                            .foregroundColor(AquinasTheme.Colors.lightGreen)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .scaleEffect(isShowingLongPressFeedback ? 1.02 : 1, anchor: .leading)

                    Spacer(minLength: 8)

                    Menu {
                        Button("Rename", systemImage: "pencil.line") { onRename() }
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive) { onDelete() }
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
                    .accessibilityLabel("Topic options")
                }

                if !displayDescription.isEmpty {
                    Text(displayDescription)
                        .font(.custom("Figtree-Regular", size: 14))
                        .foregroundColor(AquinasTheme.Colors.paragraphText)
                        .lineSpacing(4)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Sub-items: branch / question titles
            if !subItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleSubItems, id: \.id) { conversation in
                        Button(action: { onSelectSubItem(conversation) }) {
                            Text(subItemTitle(conversation))
                                .font(.custom("Figtree-Bold", size: 14))
                                .foregroundColor(AquinasTheme.Colors.headingText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .buttonStyle(.plain)
                    }

                    if subItems.count > 3 {
                        Button(action: {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                isExpanded.toggle()
                            }
                        }) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(AquinasTheme.Colors.lightGreen)
                                .frame(width: 34, height: 18)
                                .background(AquinasTheme.Colors.canvas.opacity(0.72))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AquinasTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .trim(from: 0, to: isShowingLongPressFeedback ? 1 : 0)
                .stroke(
                    AquinasTheme.Colors.border,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
                .opacity(isShowingLongPressFeedback ? 1 : 0)
                .padding(1)
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture(perform: onSelect)
        .onLongPressGesture(
            minimumDuration: longPressDuration,
            maximumDistance: 18,
            pressing: { isPressing in
                withAnimation(.linear(duration: isPressing ? longPressDuration : 0.12)) {
                    isShowingLongPressFeedback = isPressing
                }
            },
            perform: {}
        )
    }

    private var displayTitle: String {
        let trimmed = topic.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Study Topic" : trimmed
    }

    private var displayDescription: String {
        topic.description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}


// MARK: - Files Section

/// Displays uploaded files for a study topic — shown above the conversations list.
private struct StudyTopicFilesSection: View {
    let files: [UploadedFile]
    var onRemove: (UploadedFile) -> Void

    /// Matches the UploadedFileThumbnail outer frame (76px image + 5px padding each side).
    private let thumbnailWidth: CGFloat = 86
    /// Width of the edge fade overlays. Leading padding is doubled so the first
    /// item sits fully past the gradient before scrolling begins.
    private let fadeWidth: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Files")
                .font(.custom("Figtree-Bold", size: 14))
                .foregroundColor(AquinasTheme.Colors.paragraphText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(files) { file in
                        VStack(spacing: 8) {
                            UploadedFileThumbnail(file: file, onRemove: {
                                onRemove(file)
                            })

                            Text(file.name)
                                .font(.custom("Figtree-Regular", size: 11))
                                .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.6))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: thumbnailWidth)
                        }
                    }
                }
                .padding(.vertical, 18)
                // Leading inset keeps the first item clear of the fade.
                .padding(.leading, fadeWidth * 2 - 12)
            }
            // Disable the scroll view's own clip rect so rotated thumbnails and
            // drop shadows render freely outside the container's frame.
            .scrollClipDisabled()
            // Edge fades: opaque canvas colour → transparent, drawn on top of the
            // scroll content. Using overlay (not mask) avoids re-clipping overflow.
            .overlay(alignment: .leading) {
                LinearGradient(
                    stops: [
                        .init(color: AquinasTheme.Colors.canvas, location: 0),
                        .init(color: AquinasTheme.Colors.canvas.opacity(0), location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: fadeWidth)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .trailing) {
                LinearGradient(
                    stops: [
                        .init(color: AquinasTheme.Colors.canvas.opacity(0), location: 0),
                        .init(color: AquinasTheme.Colors.canvas, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: fadeWidth)
                .allowsHitTesting(false)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

private struct StudyTopicTitleTextView: View {
    let placeholder: String
    @Binding var text: String
    @Binding var isFocused: Bool
    var lineSpacing: CGFloat

    @State private var measuredHeight: CGFloat = 64

    var body: some View {
        ZStack(alignment: .topLeading) {
            AutoSizingStudyTopicTitleTextView(
                text: $text,
                isFocused: $isFocused,
                measuredHeight: $measuredHeight,
                lineSpacing: lineSpacing
            )
            .frame(height: measuredHeight)
            .frame(maxWidth: .infinity, alignment: .leading)

            if text.isEmpty {
                Text(placeholder)
                    .font(.baskervilleHeadingXLarge)
                    .lineSpacing(lineSpacing)
                    .foregroundColor(AquinasTheme.Colors.primaryReadable.opacity(0.5))
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: measuredHeight, alignment: .topLeading)
    }
}

private struct AutoSizingStudyTopicTitleTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var measuredHeight: CGFloat
    var lineSpacing: CGFloat

    func makeUIView(context: Context) -> UITextView {
        let textView = StudyTopicSizingTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isOpaque = false
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.widthTracksTextView = true
        textView.returnKeyType = .done
        textView.tintColor = UIColor(AquinasTheme.Colors.secondaryMuted)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.onBoundsChange = { view in
            context.coordinator.parent.recalculateHeight(for: view)
        }
        applyTextStyle(to: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        if textView.text != text {
            textView.attributedText = attributedTitle(text)
        }
        textView.typingAttributes = typingAttributes()
        textView.textColor = .aquinasPrimaryReadable

        if isFocused, !textView.isFirstResponder {
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        } else if !isFocused, textView.isFirstResponder {
            textView.resignFirstResponder()
        }

        recalculateHeight(for: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView textView: UITextView, context: Context) -> CGSize? {
        guard let proposedWidth = proposal.width, proposedWidth > 8 else { return nil }
        let height = measuredHeight(for: textView, width: proposedWidth)
        updateMeasuredHeight(height)
        return CGSize(width: proposedWidth, height: height)
    }

    private func applyTextStyle(to textView: UITextView) {
        textView.attributedText = attributedTitle(text)
        textView.typingAttributes = typingAttributes()
    }

    private func attributedTitle(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: typingAttributes())
    }

    private func typingAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.lineBreakMode = .byWordWrapping

        return [
            .font: UIFont(name: "LibreBaskerville-Regular", size: 40) ?? UIFont.systemFont(ofSize: 40),
            .foregroundColor: UIColor.aquinasPrimaryReadable,
            .paragraphStyle: paragraph
        ]
    }

    private func recalculateHeight(for textView: UITextView) {
        guard textView.bounds.width > 8 else { return }
        let height = measuredHeight(for: textView, width: textView.bounds.width)
        updateMeasuredHeight(height)
    }

    private func measuredHeight(for textView: UITextView, width: CGFloat) -> CGFloat {
        textView.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        let targetSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        return ceil(textView.sizeThatFits(targetSize).height)
    }

    private func updateMeasuredHeight(_ height: CGFloat) {
        guard abs(measuredHeight - height) > 0.5 else { return }
        DispatchQueue.main.async {
            measuredHeight = height
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: AutoSizingStudyTopicTitleTextView

        init(parent: AutoSizingStudyTopicTitleTextView) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text.replacingOccurrences(of: "\n", with: "")
            parent.recalculateHeight(for: textView)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            if replacement.contains("\n") {
                textView.resignFirstResponder()
                parent.isFocused = false
                return false
            }
            return true
        }
    }
}

private final class StudyTopicSizingTextView: UITextView {
    var onBoundsChange: ((UITextView) -> Void)?
    private var lastWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        guard abs(bounds.width - lastWidth) > 0.5 else { return }
        lastWidth = bounds.width
        onBoundsChange?(self)
    }
}

// MARK: - Shared helper

/// Strips markdown links and collapses whitespace for clean text previews.
private func cleanPreviewText(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^\\)]+\\)", with: "$1", options: .regularExpression)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
