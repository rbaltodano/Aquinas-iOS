//
//  InquirySideMenu.swift
//  Aquinas-iOS
//

import SwiftUI

/// Slide-out navigation panel mirrored from Figma's "03 - User Screen Flow" side-panel frames.
struct AquinasSideMenu: View, Equatable {
    @Environment(\.colorScheme) private var colorScheme

    let currentTitle: String
    let conversations: [InquiryConversation]
    let activeConversationID: UUID?
    let activePage: AppPage
    let modelTasks: ModelTaskQueue
    let selectedPersonality: String
    let isPresented: Bool
    /// An inexpensive identity for the conversation collection. It lets the
    /// shell update the panel's position while preserving this whole view tree.
    let renderVersion: Int
    var onNewChat: () -> Void
    var onSelectConversation: (InquiryConversation) -> Void
    var onRenameConversation: (InquiryConversation, String) -> Void
    var onPinConversation: (InquiryConversation) -> Void
    var onUnpinConversation: (InquiryConversation) -> Void
    var onAddConversationToStudyTopic: (InquiryConversation, UUID) -> Void
    var onRemoveConversationFromStudyTopic: (InquiryConversation) -> Void
    var onDeleteConversation: (InquiryConversation) -> Void
    var newInsightsCount: Int = 0
    var onOpenHome: () -> Void
    var onOpenLibrary: () -> Void
    var onOpenConversations: () -> Void
    var onOpenInsights: () -> Void
    var onOpenStudyTopics: () -> Void
    var onSelectStudyTopic: (StudyTopic) -> Void = { _ in }
    var onOpenSettings: () -> Void
    var onClose: () -> Void
    @State private var showsTitle = false
    @State private var showsOpenConversationsTitle = false
    @State private var conversationBeingRenamed: InquiryConversation? = nil
    @State private var conversationBeingAddedToStudyTopic: InquiryConversation? = nil
    @State private var renameDraft = ""
    @State private var sideMenuStudyTopics: [StudyTopic] = []
    @State private var topicBeingRenamed: StudyTopic? = nil
    @State private var topicRenameDraft = ""

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.currentTitle == rhs.currentTitle
            && lhs.activeConversationID == rhs.activeConversationID
            && lhs.activePage == rhs.activePage
            && lhs.selectedPersonality == rhs.selectedPersonality
            && lhs.isPresented == rhs.isPresented
            && lhs.newInsightsCount == rhs.newInsightsCount
            && lhs.renderVersion == rhs.renderVersion
    }

    var body: some View {
        GeometryReader { geometry in
            let topPadding = max(24, geometry.safeAreaInsets.top + 16)

        ZStack(alignment: .bottom) {
            // ── Scrollable content ──────────────────────────────────────────
            ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CURRENT TOPIC")
                            .font(.custom("Figtree-Bold", size: 12))
                            .foregroundColor(AquinasTheme.Colors.lightGreen)

                        Text(currentTitle)
                            .font(.custom("LibreBaskerville-Regular", size: 28))
                            .lineSpacing(8)
                            .foregroundColor(AquinasTheme.Colors.headingText)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(showsTitle ? 1 : 0)
                        .offset(x: showsTitle ? 0 : -24)

                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 0) {
                            SideMenuRow(
                                icon: "house",
                                title: "Home",
                                isActive: activePage == .home,
                                isPresented: isPresented,
                                delay: 0.20,
                                action: onOpenHome
                            )
                            SideMenuRow(
                                icon: "books.vertical",
                                title: "Library",
                                isActive: activePage == .library,
                                isPresented: isPresented,
                                delay: 0.225,
                                action: onOpenLibrary
                            )
                            SideMenuRow(
                                icon: "brain.head.profile",
                                title: "Insights",
                                badge: newInsightsCount,
                                isActive: activePage == .insights,
                                isPresented: isPresented,
                                delay: 0.25,
                                action: onOpenInsights
                            )
                            SideMenuRow(
                                icon: "text.word.spacing",
                                title: "Conversations",
                                isActive: activePage == .openConversations,
                                isPresented: isPresented,
                                delay: 0.30,
                                action: onOpenConversations
                            )
                            SideMenuRow(
                                icon: "square.stack",
                                title: "Study Topics",
                                isActive: activePage == .studyTopics,
                                isPresented: isPresented,
                                delay: 0.35,
                                action: onOpenStudyTopics
                            )
                        }
                    }
                }

                FooterDivider(isPresented: isPresented, delay: 0)

                if !sideMenuStudyTopics.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Study Topics")
                            .font(.custom("Figtree-Bold", size: 18))
                            .lineSpacing(9)
                            .foregroundColor(AquinasTheme.Colors.primaryReadable)
                            .opacity(showsOpenConversationsTitle ? 1 : 0)
                            .offset(x: showsOpenConversationsTitle ? 0 : -24)

                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(sideMenuStudyTopics.enumerated()), id: \.element.id) { index, topic in
                                StudyTopicMenuRow(
                                    topic: topic,
                                    conversations: conversations.filter { $0.studyTopicID == topic.id },
                                    conversationActivity: conversationActivity,
                                    isPresented: isPresented,
                                    delay: 0.20 + (Double(index) * 0.05),
                                    onSelect: { onSelectStudyTopic(topic) },
                                    onSelectConversation: { conversation in
                                        markConversationViewed(conversation)
                                        onSelectConversation(conversation)
                                    },
                                    onRename: {
                                        topicRenameDraft = topic.title
                                        topicBeingRenamed = topic
                                    },
                                    onDelete: {
                                        deleteTopic(topic)
                                    },
                                )

                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("Recents")
                        .font(.custom("Figtree-Bold", size: 18))
                        .lineSpacing(9)
                        .foregroundColor(AquinasTheme.Colors.primaryReadable)
                        .opacity(showsOpenConversationsTitle ? 1 : 0)
                        .offset(x: showsOpenConversationsTitle ? 0 : -24)

                    LazyVStack(alignment: .leading, spacing: 8) {
                        let sortedConversations = conversations.sorted { $0.isPinned && !$1.isPinned }
                        ForEach(Array(sortedConversations.enumerated()), id: \.element.id) { index, conversation in
                            ConversationMenuRow(
                                conversation: conversation,
                                modelActivity: conversationActivity(for: conversation),
                                isActive: activePage == .conversation && conversation.id == activeConversationID,
                                isPresented: isPresented,
                                delay: 0.20 + (Double(index) * 0.05),
                                onSelect: {
                                    markConversationViewed(conversation)
                                    onSelectConversation(conversation)
                                },
                                onRename: {
                                    renameDraft = conversation.title
                                    conversationBeingRenamed = conversation
                                },
                                onPin: {
                                    onPinConversation(conversation)
                                },
                                onUnpin: {
                                    onUnpinConversation(conversation)
                                },
                                onAddToStudyTopic: {
                                    conversationBeingAddedToStudyTopic = conversation
                                },
                                onRemoveFromStudyTopic: {
                                    onRemoveConversationFromStudyTopic(conversation)
                                },
                                onDelete: {
                                    onDeleteConversation(conversation)
                                },
                            )

                        }
                    }
                }
            }

            } // end scrollable content
            .padding(.horizontal, 24)
            .padding(.top, topPadding)
            .padding(.bottom, 88) // reserve space so the last row clears the pinned bar
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // ── Bottom fade gradient ─────────────────────────────────────────
            LinearGradient(
                stops: [
                    .init(color: AquinasTheme.Colors.canvasSecondary.opacity(0), location: 0),
                    .init(color: AquinasTheme.Colors.canvasSecondary, location: 1),
                ],
                startPoint: UnitPoint(x: 0.5, y: 0),
                endPoint: UnitPoint(x: 0.5, y: 0.84)
            )
            .frame(height: geometry.size.height * 0.38)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
            .zIndex(1)

            // ── Pinned bottom bar ────────────────────────────────────────────
            HStack(alignment: .center) {
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .semibold))
                        .sfSymbolDrawOn()
                }
                .accessibilityLabel("Settings")
                .foregroundColor(AquinasTheme.Colors.primaryReadable)

                Spacer()

                Button(action: onNewChat) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .sfSymbolDrawOn()
                        Text("New Conversation")
                            .font(.custom("Figtree-Bold", size: 14))
                    }
                    .foregroundColor(AquinasTheme.Colors.canvas)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(AquinasTheme.Colors.secondaryMuted)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    stops: [
                        Gradient.Stop(
                            color: colorScheme == .dark
                                ? Color(red: 0.08, green: 0.07, blue: 0.06)
                                : Color(red: 0.98, green: 0.96, blue: 0.91),
                            location: 0.00
                        ),
                        Gradient.Stop(
                            color: colorScheme == .dark
                                ? Color(red: 0.08, green: 0.07, blue: 0.06).opacity(0)
                                : Color(red: 0.98, green: 0.96, blue: 0.91).opacity(0),
                            location: 1.00
                        ),
                    ],
                    startPoint: UnitPoint(x: 0.5, y: 1),
                    endPoint: UnitPoint(x: 0.5, y: 0)
                )
            )
            .zIndex(2)
        } // end ZStack
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // Visual-only shape — does NOT clip children, so popup menus can
            // extend beyond the panel boundary without being cut off.
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 24, topTrailingRadius: 24)
                .fill(AquinasTheme.Colors.sideMenuSurface)
                .overlay {
                    UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 24, topTrailingRadius: 24)
                        .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
                }
        }
        .ignoresSafeArea()
        .onAppear {
            sideMenuStudyTopics = StudyTopicStore.load()
            runTitleEntrance()
        }
        .onChange(of: isPresented) { _, newValue in
            if newValue { SideMenuEntrance.openedAt = Date() }
            runTitleEntrance()
        }
        // Give the slide transition its first frame before refreshing persisted
        // topics. This keeps an occasional larger UserDefaults decode off the
        // tap and gesture critical path while preserving fresh topic contents.
        .task(id: isPresented) {
            guard isPresented else { return }
            await Task.yield()
            sideMenuStudyTopics = StudyTopicStore.load()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 18)
                .onEnded { value in
                    guard value.translation.width < -60,
                          abs(value.translation.width) > abs(value.translation.height) else {
                        return
                    }
                    onClose()
                }
        )
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
        .alert("Rename Study Topic", isPresented: topicRenamePromptBinding) {
            TextField("Topic name", text: $topicRenameDraft)
            Button("Cancel", role: .cancel) {
                topicBeingRenamed = nil
                topicRenameDraft = ""
            }
            Button("Save") {
                guard let topic = topicBeingRenamed else { return }
                let title = topicRenameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    renameTopic(topic, to: title)
                }
                topicBeingRenamed = nil
                topicRenameDraft = ""
            }
        }
        .sheet(item: $conversationBeingAddedToStudyTopic) { conversation in
            SideMenuStudyTopicPickerSheet(
                conversation: conversation,
                onSelectTopic: { topic in
                    onAddConversationToStudyTopic(conversation, topic.id)
                },
                onRemoveTopic: {
                    onRemoveConversationFromStudyTopic(conversation)
                }
            )
            .presentationDetents([.height(420), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(AquinasTheme.Colors.canvas)
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

    private func conversationActivity(
        for conversation: InquiryConversation
    ) -> ConversationModelActivity {
        let branchIDs = Set(conversation.branches.map(\.id))
        let pendingTasks = [modelTasks.currentTask].compactMap { $0 } + modelTasks.upcomingTasks
        let isLoading = pendingTasks.contains { task in
            guard let branchID = task.kind.userQuestionBranchID else { return false }
            return branchIDs.contains(branchID)
        }

        if isLoading {
            return .loading
        }
        // Already open and being viewed — the answer's been seen, so no unread dot.
        let isCurrentlyViewed = activePage == .conversation && conversation.id == activeConversationID
        if !isCurrentlyViewed, !modelTasks.completedUserQuestionBranchIDs.isDisjoint(with: branchIDs) {
            return .completed
        }
        return .idle
    }

    private func markConversationViewed(_ conversation: InquiryConversation) {
        modelTasks.markUserQuestionsViewed(branchIDs: Set(conversation.branches.map(\.id)))
    }

    private var topicRenamePromptBinding: Binding<Bool> {
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

    private func renameTopic(_ topic: StudyTopic, to newTitle: String) {
        if let index = sideMenuStudyTopics.firstIndex(where: { $0.id == topic.id }) {
            sideMenuStudyTopics[index].title = newTitle
        }
        var stored = StudyTopicStore.load()
        if let index = stored.firstIndex(where: { $0.id == topic.id }) {
            stored[index].title = newTitle
            StudyTopicStore.save(stored)
        }
    }

    private func deleteTopic(_ topic: StudyTopic) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            sideMenuStudyTopics.removeAll { $0.id == topic.id }
        }
        var stored = StudyTopicStore.load()
        stored.removeAll { $0.id == topic.id }
        StudyTopicStore.save(stored)
    }

    private func runTitleEntrance() {
        // Keep the current contents intact while the containing panel slides
        // closed. They are reset only for the next presentation.
        guard isPresented else { return }

        showsTitle = false
        showsOpenConversationsTitle = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.32)) {
                showsTitle = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.32)) {
                showsOpenConversationsTitle = true
            }
        }
    }
}

/// Tracks when the panel last opened so rows the lazy stacks create while scrolling
/// skip the entrance animation and only rows present at open time animate in.
enum SideMenuEntrance {
    static var openedAt = Date.distantPast

    static var isScrollRecycle: Bool {
        Date().timeIntervalSince(openedAt) > 1.2
    }
}

private struct FooterDivider: View {
    let isPresented: Bool
    let delay: TimeInterval
    @State private var showsDivider = false
    @State private var entranceRunID = UUID()

    var body: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(AquinasTheme.Colors.controlBorder)
                .frame(height: 1)
                .scaleEffect(x: showsDivider ? 1 : 0.75, y: 1, anchor: .trailing)
                .opacity(showsDivider ? 1 : 0)

            Image("cross-1")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundColor(AquinasTheme.Colors.lightGreen)
                .rotationEffect(.degrees(showsDivider ? 0 : -45))
                .opacity(showsDivider ? 1 : 0)

            Rectangle()
                .fill(AquinasTheme.Colors.controlBorder)
                .frame(height: 1)
                .scaleEffect(x: showsDivider ? 1 : 0.75, y: 1, anchor: .leading)
                .opacity(showsDivider ? 1 : 0)
        }
        .onAppear(perform: runEntrance)
        .onChange(of: isPresented) { oldValue, newValue in
            runEntrance()
        }
    }

    private func runEntrance() {
        let runID = UUID()
        entranceRunID = runID

        // Keep the divider in place while the parent panel is closing.
        guard isPresented else { return }

        showsDivider = false

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard entranceRunID == runID, isPresented else { return }
            withAnimation(.easeOut(duration: 0.35)) {
                showsDivider = true
            }
        }
    }
}
