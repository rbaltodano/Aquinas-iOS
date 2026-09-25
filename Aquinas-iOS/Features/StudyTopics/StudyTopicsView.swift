//
//  StudyTopicsView.swift
//  Aquinas-iOS
//

import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
