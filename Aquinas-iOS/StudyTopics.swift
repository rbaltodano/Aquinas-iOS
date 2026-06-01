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

    init(
        id: UUID = UUID(),
        title: String = "",
        description: String = "",
        files: [UploadedFile] = []
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.files = files
    }
}

enum StudyTopicStore {
    private static let key = "aquinas.study-topics.v1"

    static func load() -> [StudyTopic] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let topics = try? JSONDecoder().decode([StudyTopic].self, from: data) else {
            return []
        }
        return topics
    }

    static func save(_ topics: [StudyTopic]) {
        guard let data = try? JSONEncoder().encode(topics) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Study Topics List

struct StudyTopicsView: View {
    let conversations: [InquiryConversation]
    let activeConversationID: UUID?
    @Binding var savedInsights: [ConceptDefinition]
    var onOpenMenu: () -> Void
    var onSelectConversation: (InquiryConversation) -> Void
    var onNewChat: () -> Void
    /// Called when the user taps "New Conversation" inside a topic's detail view.
    var onNewChatInTopic: (UUID) -> Void = { _ in }
    var onAttachConversationToTopic: (InquiryConversation, UUID) -> Void
    var onRenameConversation: (InquiryConversation, String) -> Void
    /// When set, the view automatically opens this topic's detail on appear.
    var requestedTopicID: UUID? = nil

    @State private var searchText = ""
    @State private var topics: [StudyTopic] = StudyTopicStore.load()
    @State private var selectedTopicID: UUID? = nil
    @State private var topicBeingRenamed: StudyTopic? = nil
    @State private var topicRenameDraft: String = ""
    /// ID of the topic card whose "…" menu is currently open.
    @State private var cardMenuTopicID: UUID? = nil
    /// Set to a newly-created topic's ID so the detail view can auto-focus its title field.
    @State private var autoFocusTopicID: UUID? = nil
    // File/photo pickers live here (not on the conditionally-shown detail view)
    // so SwiftUI can reliably present them.
    @State private var showTopicPhotoPicker = false
    @State private var showTopicFilePicker = false
    @State private var topicPhotoItems: [PhotosPickerItem] = []

    private var selectedTopic: StudyTopic? {
        guard let selectedTopicID else { return nil }
        return topics.first { $0.id == selectedTopicID }
    }

    private var visibleTopics: [StudyTopic] {
        topics.filter { topicMatchesSearch($0) }
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
                    autoFocusTitle: topic.id == autoFocusTopicID,
                    onUpdateTopic: updateTopic,
                    onSelectConversation: onSelectConversation,
                    onNewChat: {
                        onNewChatInTopic(topic.id)
                    },
                    onAttachConversation: { conversation in
                        onAttachConversationToTopic(conversation, topic.id)
                    },
                    onRenameConversation: onRenameConversation,
                    onDeleteTopic: {
                        deleteTopic(topic)
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

            // Card-level options menu — rendered above everything in the list layer.
            if let menuTopicID = cardMenuTopicID,
               let menuTopic = topics.first(where: { $0.id == menuTopicID }) {
                // Full-screen backdrop — tap anywhere to dismiss.
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { closeCardMenu() }
                    .zIndex(8)

                ConversationOptionsMenu(
                    onRename: {
                        closeCardMenu()
                        topicRenameDraft = menuTopic.title
                        topicBeingRenamed = menuTopic
                    },
                    onPin: { closeCardMenu() },
                    onDelete: {
                        closeCardMenu()
                        deleteTopic(menuTopic)
                    },
                    showAddToStudyTopic: false
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 80)
                .padding(.trailing, 24)
                .transition(.scale(scale: 0.92, anchor: .topTrailing).combined(with: .opacity))
                .zIndex(9)
            }

            // Single morphing nav button that floats above both layers.
            VStack {
                HStack {
                    AquinasNavButton(
                        isDetailVisible: selectedTopicID != nil,
                        onMenuTap: onOpenMenu,
                        onBackTap: {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                selectedTopicID = nil
                            }
                        }
                    )
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(true)
            .zIndex(20)
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: selectedTopicID)
        .onAppear {
            guard let id = requestedTopicID,
                  topics.contains(where: { $0.id == id }) else { return }
            // Brief delay so the page-in transition finishes before the detail slides in.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                    selectedTopicID = id
                }
            }
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
                       UIImage(data: data) != nil {
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
                    let imageData = data.flatMap { UIImage(data: $0) == nil ? nil : $0 }
                    added.append(UploadedFile(
                        name: url.lastPathComponent,
                        imageData: imageData,
                        rotationDegrees: Double.random(in: -5...5)
                    ))
                }
                var updated = topic
                updated.files.append(contentsOf: added)
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

    private func closeCardMenu() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.76)) {
            cardMenuTopicID = nil
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

                    Text("Study Topics")
                        .font(.custom("LibreBaskerville-Regular", size: 28))
                        .foregroundColor(AquinasTheme.Colors.primaryReadable)
                        .padding(.top, 28)
                        .frame(maxWidth: .infinity, alignment: .center)

                    StudyTopicsSearchField(searchText: $searchText)
                        .padding(.top, 24)

                    LazyVStack(spacing: 16) {
                        ForEach(visibleTopics) { topic in
                            StudyTopicCard(
                                topic: topic,
                                subItems: topicSubItems(for: topic),
                                onSelect: {
                                    withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                        selectedTopicID = topic.id
                                    }
                                },
                                onMenuOpen: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.76)) {
                                        cardMenuTopicID = topic.id
                                    }
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
                    .padding(.top, 48)
                    .padding(.bottom, 120)
                    .animation(.spring(response: 0.34, dampingFraction: 0.86), value: normalizedSearchText)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // FAB
            Button(action: createStudyTopic) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .sfSymbolDrawOn()
                    Text("New Study Topic")
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
    }

    private func createStudyTopic() {
        let topic = StudyTopic()
        topics.insert(topic, at: 0)
        StudyTopicStore.save(topics)
        autoFocusTopicID = topic.id
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            selectedTopicID = topic.id
        }
    }

    private func updateTopic(_ topic: StudyTopic) {
        guard let index = topics.firstIndex(where: { $0.id == topic.id }) else { return }
        topics[index] = topic
        StudyTopicStore.save(topics)
    }

    private func deleteTopic(_ topic: StudyTopic) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            topics.removeAll { $0.id == topic.id }
        }
        StudyTopicStore.save(topics)
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

    private func topicSubItems(for topic: StudyTopic) -> [String] {
        conversations
            .filter { $0.studyTopicID == topic.id }
            .map { conversationTitle($0) }
            .filter { !$0.isEmpty }
    }

    private func topicMatchesSearch(_ topic: StudyTopic) -> Bool {
        guard !normalizedSearchText.isEmpty else { return true }
        let text = ([displayTitle(for: topic), topic.description] + topicSubItems(for: topic))
            .joined(separator: " ")
            .lowercased()
        return text.contains(normalizedSearchText)
    }

    private func displayTitle(for topic: StudyTopic) -> String {
        let trimmed = topic.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Study Topic" : trimmed
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
    var onUpdateTopic: (StudyTopic) -> Void
    var onSelectConversation: (InquiryConversation) -> Void
    var onNewChat: () -> Void
    var onAttachConversation: (InquiryConversation) -> Void
    var onRenameConversation: (InquiryConversation, String) -> Void
    var onDeleteTopic: () -> Void
    var onBack: () -> Void

    @State private var activeInsight: ConceptDefinition? = nil
    @State private var pickerActiveInsight: ConceptDefinition? = nil
    @State private var conversationBeingRenamed: InquiryConversation? = nil
    @State private var renameDraft = ""
    @State private var isTopicOptionsOpen = false
    @State private var isExistingConversationPickerOpen = false
    /// ID of the conversation card whose "…" menu is currently open (hoisted here
    /// so the menu renders above all other cards in the ZStack).
    @State private var conversationCardMenuID: UUID? = nil
    @State private var titleDraft: String
    @State private var descriptionDraft: String
    @State private var localFiles: [UploadedFile]
    @FocusState private var isTitleFocused: Bool

    private let optionsMenuZIndex: Double = 10_000

    init(
        topic: StudyTopic,
        conversations: [InquiryConversation],
        activeConversationID: UUID?,
        savedInsights: Binding<[ConceptDefinition]>,
        autoFocusTitle: Bool = false,
        onUpdateTopic: @escaping (StudyTopic) -> Void,
        onSelectConversation: @escaping (InquiryConversation) -> Void,
        onNewChat: @escaping () -> Void,
        onAttachConversation: @escaping (InquiryConversation) -> Void,
        onRenameConversation: @escaping (InquiryConversation, String) -> Void,
        onDeleteTopic: @escaping () -> Void,
        onBack: @escaping () -> Void,
        onRequestPhotoPicker: @escaping () -> Void = {},
        onRequestFilePicker: @escaping () -> Void = {}
    ) {
        self.topic = topic
        self.conversations = conversations
        self.activeConversationID = activeConversationID
        self._savedInsights = savedInsights
        self.autoFocusTitle = autoFocusTitle
        self.onUpdateTopic = onUpdateTopic
        self.onSelectConversation = onSelectConversation
        self.onNewChat = onNewChat
        self.onAttachConversation = onAttachConversation
        self.onRenameConversation = onRenameConversation
        self.onDeleteTopic = onDeleteTopic
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

            let topicConversations = conversations.filter { $0.studyTopicID == topic.id }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Spacer behind the floating hamburger button.
                    Color.clear.frame(height: 72)

                    VStack(alignment: .center, spacing: 48) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 12) {
                                placeholderTextField(
                                    placeholder: "New Study Topic",
                                    text: $titleDraft,
                                    font: .custom("LibreBaskerville-Regular", size: 28),
                                    color: AquinasTheme.Colors.primaryReadable,
                                    emptyOpacity: 0.5,
                                    lineLimit: 1...2,
                                    focusBinding: $isTitleFocused
                                )
                                .lineSpacing(14)
                                .onChange(of: titleDraft) { _, _ in persistDrafts() }

                                Spacer(minLength: 8)

                                Button(action: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.76)) {
                                        isTopicOptionsOpen.toggle()
                                    }
                                }) {
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

                            placeholderTextField(
                                placeholder: "Briefly describe the topic of this study",
                                text: $descriptionDraft,
                                font: .custom("Figtree-Regular", size: 14),
                                color: AquinasTheme.Colors.paragraphText,
                                emptyOpacity: 0.5,
                                lineLimit: 1...4
                            )
                            .lineSpacing(7)
                            .onChange(of: descriptionDraft) { _, _ in persistDrafts() }
                        }

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
                                        onMenuOpen: {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.76)) {
                                                conversationCardMenuID = conversation.id
                                            }
                                        }
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }

                        Button(action: {
                            isExistingConversationPickerOpen = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .bold))
                                    .sfSymbolDrawOn()
                                Text("Add Existing Conversation")
                                    .font(.custom("Figtree-Regular", size: 14))
                            }
                            .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .padding(24)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(
                                        AquinasTheme.Colors.darkText.opacity(0.15),
                                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 24)

                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollClipDisabled()

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: onNewChat) {
                        HStack(spacing: 8) {
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
                    .shadow(color: AquinasTheme.Colors.dropShadow.opacity(0.16), radius: 16, x: 0, y: 10)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .zIndex(6)

            // Topic options overlay (rename / pin / delete the topic itself).
            if isTopicOptionsOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { closeTopicOptions() }
                    .zIndex(optionsMenuZIndex - 1)

                ConversationOptionsMenu(
                    onRename: {
                        // The title is editable inline — just close the menu;
                        // the user can tap the title field directly to rename.
                        closeTopicOptions()
                    },
                    onPin: { closeTopicOptions() },
                    onDelete: {
                        closeTopicOptions()
                        onDeleteTopic()
                    },
                    showAddToStudyTopic: false,
                    showUploadOptions: true,
                    onUploadImage: {
                        closeTopicOptions()
                        onRequestPhotoPicker()
                    },
                    onUploadFile: {
                        closeTopicOptions()
                        onRequestFilePicker()
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 120)
                .padding(.trailing, 24)
                .zIndex(optionsMenuZIndex)
                .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
            }

            // Conversation card options menu — hoisted here so it renders above all
            // sibling cards in the ZStack, not clipped by the LazyVStack.
            if let menuID = conversationCardMenuID,
               let menuConversation = conversations.first(where: { $0.id == menuID }) {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { closeConversationCardMenu() }
                    .zIndex(optionsMenuZIndex - 1)

                ConversationOptionsMenu(
                    onRename: {
                        closeConversationCardMenu()
                        renameDraft = menuConversation.title
                        conversationBeingRenamed = menuConversation
                    },
                    onPin: { closeConversationCardMenu() },
                    onDelete: { closeConversationCardMenu() },
                    showAddToStudyTopic: false
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 120)
                .padding(.trailing, 24)
                .zIndex(optionsMenuZIndex)
                .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.76), value: isTopicOptionsOpen)
        .animation(.spring(response: 0.35, dampingFraction: 0.76), value: conversationCardMenuID)
        .task(id: autoFocusTitle) {
            guard autoFocusTitle else { return }
            // Wait for the slide-in transition to finish before stealing first responder.
            try? await Task.sleep(for: .milliseconds(550))
            isTitleFocused = true
        }
        // Swipe right to go back.
        .simultaneousGesture(
            DragGesture(minimumDistance: 18)
                .onEnded { value in
                    guard value.translation.width > 60,
                          abs(value.translation.width) > abs(value.translation.height) else { return }
                    onBack()
                }
        )
        .sheet(item: $activeInsight) { insight in
            ConceptSheetContent(concept: insight, collectedDefinitions: $savedInsights)
                .presentationDetents([.fraction(0.45)])
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
                }
            )
            .presentationDetents([.height(420), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(AquinasTheme.Colors.canvas)
        }
        .sheet(item: $pickerActiveInsight) { insight in
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

    private func placeholderTextField(
        placeholder: String,
        text: Binding<String>,
        font: Font,
        color: Color,
        emptyOpacity: Double,
        lineLimit: ClosedRange<Int>,
        focusBinding: FocusState<Bool>.Binding? = nil
    ) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(font)
                    .foregroundColor(color.opacity(emptyOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .allowsHitTesting(false)
            }

            if let focusBinding {
                TextField("", text: text, axis: .vertical)
                    .font(font)
                    .foregroundColor(color)
                    .tint(AquinasTheme.Colors.secondaryMuted)
                    .lineLimit(lineLimit)
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
                    .lineLimit(lineLimit)
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
    }

    private func closeTopicOptions() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.76)) {
            isTopicOptionsOpen = false
        }
    }

    private func closeConversationCardMenu() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.76)) {
            conversationCardMenuID = nil
        }
    }

    private func persistDrafts() {
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
}

// MARK: - Existing Conversation Picker

private struct ExistingConversationPickerSheet: View {
    /// Conversations from sideMenuConversations — may be stale or empty if
    /// CurrentConversationView hasn't published its state yet this session.
    let conversations: [InquiryConversation]
    let activeConversationID: UUID?
    @Binding var savedInsights: [ConceptDefinition]
    var onSelectConversation: (InquiryConversation) -> Void
    var onOpenInsight: (ConceptDefinition) -> Void
    var onRenameConversation: (InquiryConversation, String) -> Void

    @State private var searchText = ""
    @State private var conversationBeingRenamed: InquiryConversation? = nil
    @State private var renameDraft = ""
    /// Loaded from CurrentConversationsStore on appear as a reliable fallback.
    @State private var storeConversations: [InquiryConversation] = []

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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Add Existing Conversation")
                    .font(.custom("LibreBaskerville-Regular", size: 24))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 28)

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
                                    onSelectConversation(conversation)
                                },
                                onOpenInsight: onOpenInsight,
                                onRename: { conversation in
                                    renameDraft = conversation.title
                                    conversationBeingRenamed = conversation
                                }
                            )
                        }
                    }
                    .padding(.top, 32)
                }

                Color.clear.frame(height: 32)
            }
            .padding(.horizontal, 24)
        }
        .background(AquinasTheme.Colors.canvas)
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
    @FocusState private var isFocused: Bool

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

// MARK: - Topic Card (list view)

private struct StudyTopicCard: View {
    let topic: StudyTopic
    let subItems: [String]
    var onSelect: () -> Void
    var onMenuOpen: () -> Void = {}

    @State private var isExpanded = false

    private var visibleSubItems: [String] {
        isExpanded ? subItems : Array(subItems.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header: title + options button
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    Text(displayTitle)
                        .font(.custom("LibreBaskerville-Regular", size: 18))
                        .foregroundColor(AquinasTheme.Colors.primaryReadable)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    Button(action: onMenuOpen) {
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
                        .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
                        .lineSpacing(4)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Sub-items: branch / question titles
            if !subItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleSubItems, id: \.self) { item in
                        Text(item)
                            .font(.custom("Figtree-Bold", size: 12))
                            .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    if subItems.count > 3 {
                        Button(action: {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                isExpanded.toggle()
                            }
                        }) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
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
        .background(AquinasTheme.Colors.componentBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onSelect)
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

// MARK: - Shared helper

/// Strips markdown links and collapses whitespace for clean text previews.
private func cleanPreviewText(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^\\)]+\\)", with: "$1", options: .regularExpression)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
