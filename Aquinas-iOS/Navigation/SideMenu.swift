//
//  InquirySideMenu.swift
//  Aquinas-iOS
//

import SwiftUI

// MARK: - Side Menu

/// Always-available top-left trigger for the conversation side panel.
struct SideMenuTriggerButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AquinasTheme.Colors.darkGreen)
                .sfSymbolDrawOn()
                .frame(width: 48, height: 48)
                .background(AquinasTheme.Colors.canvasSecondary)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open side menu")
    }
}

/// Top-right control for quickly moving between focused Branch mode and the wider Canvas view.
struct CanvasModeToggleButton: View {
    let isActive: Bool
    var updateSignal: Int = 0
    var action: () -> Void
    @State private var pulseScale: CGFloat = 1.0
    @State private var updatedTextWidth: CGFloat = 0
    @State private var animatedButtonWidth: CGFloat = 48
    @State private var animatedLabelGap: CGFloat = 0
    @State private var animatedLabelWidth: CGFloat = 0
    @State private var isShowingUpdated = false
    @State private var hapticTrigger = 0
    @State private var dismissalTask: Task<Void, Never>?
    @State private var updatedPulseTask: Task<Void, Never>?

    private static let collapsedWidth: CGFloat = 48
    private static let activeWidth: CGFloat = 93
    private static let labelGap: CGFloat = 8
    private static let updatedTransitionDuration: TimeInterval = 0.28

    private var showsUpdatedLabel: Bool {
        !isActive && isShowingUpdated
    }

    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: 0) {
                ZStack {
                    if isActive {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AquinasTheme.Colors.darkGreen)
                            .transition(.blurFade)
                    } else {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AquinasTheme.Colors.lightGreen)
                            .sfSymbolDrawOn()
                            .transition(.blurFade)
                    }
                }
                .frame(width: 18, height: 18)

                if !isActive {
                    Color.clear
                        .frame(width: animatedLabelGap)

                    updatedText
                        .frame(width: animatedLabelWidth, alignment: .leading)
                        .opacity(showsUpdatedLabel && animatedLabelWidth > 0 ? 1 : 0)
                        .blur(radius: showsUpdatedLabel && animatedLabelWidth > 0 ? 0 : 8)
                        .clipped()
                }

                if isActive {
                    Text("Back")
                        .font(.custom("Figtree-Bold", size: 14))
                        .foregroundColor(AquinasTheme.Colors.paragraphText)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .transition(.blurFade)
                }
            }
            .padding(.horizontal, isActive ? 19 : 15)
            .frame(width: animatedButtonWidth, height: 48)
            .background(AquinasTheme.Colors.canvasSecondary)
            .clipShape(Capsule())
            .clipped()
            .overlay(
                Capsule()
                    .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
            )
            .animation(.spring(response: 0.42, dampingFraction: 0.84), value: isActive)
        }
        .background(updatedTextMeasurement)
        .buttonStyle(.plain)
        .scaleEffect(pulseScale)
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
        .accessibilityLabel(isActive ? "Return to branch view" : "Open canvas view")
        .onAppear {
            updateButtonLayout(animated: false)
        }
        .onChange(of: isActive) { _, _ in
            updateButtonLayout(animated: true)
        }
        .onChange(of: updateSignal) { oldValue, newValue in
            guard newValue > oldValue, !isActive else { return }
            presentUpdatedFeedback()
        }
        .onDisappear {
            dismissalTask?.cancel()
            updatedPulseTask?.cancel()
        }
    }

    private var updatedText: some View {
        Text("Updated")
            .font(.figtreeChipLabel)
            .foregroundColor(AquinasTheme.Colors.headingText)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var updatedTextMeasurement: some View {
        updatedText
            .hidden()
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: CanvasModeUpdatedWidthKey.self, value: proxy.size.width)
                }
            )
            .onPreferenceChange(CanvasModeUpdatedWidthKey.self) { width in
                updatedTextWidth = width
                updateButtonLayout(animated: showsUpdatedLabel)
            }
    }

    private func targetButtonWidth(labelWidth: CGFloat) -> CGFloat {
        if isActive { return Self.activeWidth }
        if showsUpdatedLabel { return Self.collapsedWidth + Self.labelGap + labelWidth }
        return Self.collapsedWidth
    }

    private func updateButtonLayout(animated: Bool) {
        let nextLabelWidth = showsUpdatedLabel ? updatedTextWidth : 0
        let nextLabelGap = showsUpdatedLabel ? Self.labelGap : 0
        let nextButtonWidth = targetButtonWidth(labelWidth: nextLabelWidth)

        let updates = {
            animatedLabelWidth = nextLabelWidth
            animatedLabelGap = nextLabelGap
            animatedButtonWidth = nextButtonWidth
        }

        if animated {
            withAnimation(.easeInOut(duration: Self.updatedTransitionDuration), updates)
        } else {
            updates()
        }
    }

    private func presentUpdatedFeedback() {
        dismissalTask?.cancel()
        withAnimation(.easeInOut(duration: Self.updatedTransitionDuration)) {
            isShowingUpdated = true
            updateButtonLayout(animated: false)
        }
        hapticTrigger += 1
        triggerUpdatedTransitionPulse()
        dismissalTask = Task {
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            await MainActor.run {
                triggerUpdatedTransitionPulse()
                withAnimation(.easeInOut(duration: Self.updatedTransitionDuration)) {
                    isShowingUpdated = false
                    updateButtonLayout(animated: false)
                }
            }
        }
    }

    private func handleTap() {
        triggerPulse()
        action()
    }

    private func triggerUpdatedTransitionPulse() {
        updatedPulseTask?.cancel()
        let halfDuration = Self.updatedTransitionDuration / 2
        updatedPulseTask = Task {
            withAnimation(.easeInOut(duration: halfDuration)) {
                pulseScale = 1.05
            }
            do {
                try await Task.sleep(for: .seconds(halfDuration))
            } catch {
                return
            }
            withAnimation(.easeInOut(duration: halfDuration)) {
                pulseScale = 1
            }
        }
    }

    private func triggerPulse() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.52)) {
            pulseScale = 1.05
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.68)) {
                pulseScale = 1.0
            }
        }
    }
}

private struct CanvasModeUpdatedWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Slide-out navigation panel mirrored from Figma's "03 - User Screen Flow" side-panel frames.
struct AquinasSideMenu: View {
    @Environment(\.colorScheme) private var colorScheme

    let currentTitle: String
    let conversations: [InquiryConversation]
    let activeConversationID: UUID?
    let activePage: AppPage
    let selectedPersonality: String
    let isPresented: Bool
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

                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(sideMenuStudyTopics.enumerated()), id: \.element.id) { index, topic in
                                StudyTopicMenuRow(
                                    topic: topic,
                                    conversations: conversations.filter { $0.studyTopicID == topic.id },
                                    isPresented: isPresented,
                                    delay: 0.20 + (Double(index) * 0.05),
                                    onSelect: { onSelectStudyTopic(topic) },
                                    onSelectConversation: { onSelectConversation($0) },
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

                    VStack(alignment: .leading, spacing: 8) {
                        let sortedConversations = conversations.sorted { $0.isPinned && !$1.isPinned }
                        ForEach(Array(sortedConversations.enumerated()), id: \.element.id) { index, conversation in
                            ConversationMenuRow(
                                conversation: conversation,
                                isActive: activePage == .conversation && conversation.id == activeConversationID,
                                isPresented: isPresented,
                                delay: 0.20 + (Double(index) * 0.05),
                                onSelect: {
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
                            .font(.custom("Figtree-Regular", size: 14))
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
            if newValue { sideMenuStudyTopics = StudyTopicStore.load() }
            runTitleEntrance()
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

private struct SideMenuRow: View {
    let icon: String
    let title: String
    var badge: Int = 0
    var isActive: Bool = false
    let isPresented: Bool
    let delay: TimeInterval
    var action: () -> Void
    @State private var showsIcon = false
    @State private var showsText = false
    @State private var entranceRunID = UUID()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 24) {
                Group {
                    if showsIcon {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AquinasTheme.Colors.headingText)
                            .frame(width: 16, height: 16)
                            .sfSymbolDrawOn()
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 16, height: 16)
                            .hidden()
                    }
                }

                Text(title)
                    .font(.custom("LibreBaskerville-Regular", size: 14))
                    .lineSpacing(7)
                    .foregroundColor(AquinasTheme.Colors.paragraphText)
                    .opacity(showsText ? 1 : 0)
                    .offset(x: showsText ? 0 : -10)

                if badge > 0 {
                    Text("\(badge)")
                        .font(.custom("Figtree-Bold", size: 12))
                        .foregroundColor(AquinasTheme.Colors.sideMenuSurface)
                        .frame(width: 22, height: 22)
                        .background(AquinasTheme.Colors.lightGreen)
                        .clipShape(Circle())
                        .opacity(showsText ? 1 : 0)
                        .transition(.scale(scale: 0.75).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? AquinasTheme.Colors.systemSelection : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onAppear(perform: runEntrance)
        .onChange(of: isPresented) { oldValue, newValue in
            runEntrance()
        }
    }

    private func runEntrance() {
        let runID = UUID()
        entranceRunID = runID

        // The panel owns the dismissal animation. Keeping each row visible
        // prevents its content from fading away before that animation ends.
        guard isPresented else { return }

        showsIcon = false
        showsText = false

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard entranceRunID == runID, isPresented else { return }
            withAnimation(.easeOut(duration: 0.35)) {
                showsIcon = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.025) {
            guard entranceRunID == runID, isPresented else { return }
            withAnimation(.easeOut(duration: 0.30)) {
                showsText = true
            }
        }
    }
}

private struct PinBlurModifier: ViewModifier, Animatable {
    var amount: Double // 1 = fully hidden, 0 = fully revealed
    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }
    func body(content: Content) -> some View {
        content
            .blur(radius: amount * 7)
            .opacity(1 - amount)
            .scaleEffect(1 - amount * 0.38, anchor: .leading)
    }
}

private struct ConversationMenuRow: View {
    let conversation: InquiryConversation
    let isActive: Bool
    let isPresented: Bool
    let delay: TimeInterval
    var onSelect: () -> Void
    var onRename: () -> Void
    var onPin: () -> Void
    var onUnpin: () -> Void = {}
    var onAddToStudyTopic: () -> Void
    var onRemoveFromStudyTopic: () -> Void
    var onDelete: () -> Void
    @State private var isVisible = false
    @State private var showUnpinConfirmation = false
    @State private var isPinRevealed = false
    @State private var entranceRunID = UUID()

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                if isPinRevealed {
                    Button {
                        showUnpinConfirmation = true
                    } label: {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AquinasTheme.Colors.accent)
                    }
                    .buttonStyle(.plain)
                    .transition(.modifier(
                        active: PinBlurModifier(amount: 1),
                        identity: PinBlurModifier(amount: 0)
                    ))
                }
                Text(conversation.title)
                    .font(.custom("LibreBaskerville-Regular", size: 14))
                    .lineSpacing(7)
                    .foregroundColor(AquinasTheme.Colors.paragraphText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.spring(response: 0.40, dampingFraction: 0.78), value: isPinRevealed)

            if isActive {
                Menu {
                    Button("Rename", systemImage: "pencil.line") { onRename() }
                    if conversation.isPinned {
                        Button("Unpin", systemImage: "pin.slash") { onUnpin() }
                    } else {
                        Button("Pin", systemImage: "pin") { onPin() }
                    }
                    if conversation.studyTopicID != nil {
                        Button("Remove from Study Topic", systemImage: "square.stack") { onRemoveFromStudyTopic() }
                    } else {
                        Button("Add to Study Topic", systemImage: "square.stack") { onAddToStudyTopic() }
                    }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AquinasTheme.Colors.paragraphText)
                        .sfSymbolDrawOn(delay: delay + 0.08)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .padding(11)
                .contentShape(Rectangle())
                .padding(-11)
                .accessibilityLabel("Conversation options")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isActive ? AquinasTheme.Colors.systemSelection : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("Rename", systemImage: "pencil.line") { onRename() }
            if conversation.isPinned {
                Button("Unpin", systemImage: "pin.slash") { onUnpin() }
            } else {
                Button("Pin", systemImage: "pin") { onPin() }
            }
            if conversation.studyTopicID != nil {
                Button("Remove from Study Topic", systemImage: "square.stack") { onRemoveFromStudyTopic() }
            } else {
                Button("Add to Study Topic", systemImage: "square.stack") { onAddToStudyTopic() }
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { onDelete() }
        }
        .alert("Unpin Conversation?", isPresented: $showUnpinConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Unpin") { onUnpin() }
        } message: {
            Text("Remove \"\(conversation.title)\" from pinned conversations?")
        }
        .opacity(isVisible ? 1 : 0)
        .offset(x: isVisible ? 0 : -10)
        .onAppear {
            isPinRevealed = conversation.isPinned
            runEntrance()
        }
        .onChange(of: conversation.isPinned) { _, newValue in
            withAnimation(.spring(response: 0.40, dampingFraction: 0.78)) {
                isPinRevealed = newValue
            }
        }
        .onChange(of: isPresented) { _, _ in
            runEntrance()
        }
    }

    private func runEntrance() {
        let runID = UUID()
        entranceRunID = runID

        // Keep the row rendered while the parent panel is closing.
        guard isPresented else { return }

        isVisible = false

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard entranceRunID == runID, isPresented else { return }
            withAnimation(.easeOut(duration: 0.30)) {
                isVisible = true
            }
        }
    }
}

private struct StudyTopicMenuRow: View {
    let topic: StudyTopic
    let conversations: [InquiryConversation]
    let isPresented: Bool
    let delay: TimeInterval
    var onSelect: () -> Void
    var onSelectConversation: (InquiryConversation) -> Void = { _ in }
    var onRename: () -> Void = {}
    var onDelete: () -> Void = {}
    @State private var isVisible = false
    @State private var isExpanded = false
    @State private var isShowingLongPressFeedback = false
    @State private var entranceRunID = UUID()

    private let longPressDuration: TimeInterval = 0.25

    private var displayTitle: String {
        let trimmed = topic.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Study Topic" : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Topic header row ─────────────────────────────────────────────
            HStack(spacing: 12) {
                Image(systemName: "square.stack")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AquinasTheme.Colors.lightGreen)
                    .frame(width: 16, height: 16)
                    .sfSymbolDrawOn()

                Text(displayTitle)
                    .font(.custom("LibreBaskerville-Regular", size: 14))
                    .lineSpacing(7)
                    .foregroundColor(AquinasTheme.Colors.paragraphText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .scaleEffect(isShowingLongPressFeedback ? 1.05 : 1, anchor: .leading)


                Menu {
                    Button("Rename", systemImage: "pencil.line") { onRename() }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AquinasTheme.Colors.paragraphText)
                        .sfSymbolDrawOn(delay: delay + 0.08)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .padding(11)
                .contentShape(Rectangle())
                .padding(-11)
                .accessibilityLabel("Topic options")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture {
                // First tap expands; tapping again navigates.
                if isExpanded || conversations.isEmpty {
                    onSelect()
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        isExpanded = true
                    }
                }
            }
            .onLongPressGesture(
                minimumDuration: longPressDuration,
                maximumDistance: 18,
                pressing: { isPressing in updateLongPressFeedback(isPressing) },
                perform: {}
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .trim(from: 0, to: isShowingLongPressFeedback ? 1 : 0)
                    .stroke(
                        AquinasTheme.Colors.border,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )
                    .opacity(isShowingLongPressFeedback ? 1 : 0)
                    .padding(1)
                    .allowsHitTesting(false)
            }

            // ── Expanded conversation list ────────────────────────────────────
            if isExpanded && !conversations.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(conversations.enumerated()), id: \.element.id) { index, conversation in
                        TopicConversationRow(
                            conversation: conversation,
                            index: index,
                            onTap: { onSelectConversation(conversation) }
                        )
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .offset(x: isVisible ? 0 : -10)
        .onAppear(perform: runEntrance)
        .onChange(of: isPresented) { _, newValue in
            isShowingLongPressFeedback = false
            runEntrance()
        }
    }

    private func updateLongPressFeedback(_ isPressing: Bool) {
        withAnimation(.linear(duration: isPressing ? longPressDuration : 0.12)) {
            isShowingLongPressFeedback = isPressing
        }
    }

    private func runEntrance() {
        let runID = UUID()
        entranceRunID = runID
        // Keep the row rendered while the parent panel is closing.
        guard isPresented else { return }
        isVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard entranceRunID == runID, isPresented else { return }
            withAnimation(.easeOut(duration: 0.30)) { isVisible = true }
        }
    }
}

private struct TopicConversationRow: View {
    let conversation: InquiryConversation
    let index: Int
    var onTap: () -> Void

    @State private var appeared = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "text.word.spacing")
                    .font(.system(size: 11))
                    .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.4))
                    .frame(width: 14, height: 14)
                    .sfSymbolDrawOn(delay: Double(index) * 0.15 + 0.05)
                Text(conversation.title.isEmpty ? "Untitled" : conversation.title)
                    .font(.custom("LibreBaskerville-Regular", size: 13))
                    .foregroundColor(AquinasTheme.Colors.paragraphText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 52)
            .padding(.trailing, 24)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -8)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)
                .delay(Double(index) * 0.15)) {
                appeared = true
            }
        }
        .onDisappear { appeared = false }
    }
}

struct SideMenuStudyTopicPickerSheet: View {
    let conversation: InquiryConversation
    var onSelectTopic: (StudyTopic) -> Void
    var onRemoveTopic: () -> Void = {}

    @State private var searchText = ""
    @State private var topics: [StudyTopic] = []
    @State private var selectedTopicID: UUID?
    @State private var isShowingNewTopicSheet = false

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredTopics: [StudyTopic] {
        topics.filter { topic in
            guard !normalizedSearchText.isEmpty else { return true }
            return [displayTitle(for: topic), topic.description]
                .joined(separator: " ")
                .lowercased()
                .contains(normalizedSearchText)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Add to Study Topic")
                    .font(.custom("LibreBaskerville-Regular", size: 24))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 56)

                Text(conversation.title)
                    .font(.custom("Figtree-Regular", size: 14))
                    .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)

                StudyTopicsSearchField(searchText: $searchText)
                    .padding(.top, 24)

                if topics.isEmpty {
                    // No topics exist at all — the dashed "Add New Study Topic" button below covers it.
                    Text("No study topics yet.")
                        .font(.custom("Figtree-Regular", size: 14))
                        .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                } else if filteredTopics.isEmpty {
                    Text("No matching study topics.")
                        .font(.custom("Figtree-Regular", size: 14))
                        .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(filteredTopics) { topic in
                            SideMenuStudyTopicPickerCard(
                                topic: topic,
                                isSelected: topic.id == selectedTopicID,
                                onSelect: { toggleSelection(of: topic) }
                            )
                        }
                    }
                    .padding(.top, 32)
                }

                Button(action: { isShowingNewTopicSheet = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .sfSymbolDrawOn()
                        Text("Add New Study Topic")
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
                .padding(.top, 24)

                Color.clear.frame(height: 32)
            }
            .padding(.horizontal, 24)
        }
        .background(AquinasTheme.Colors.canvas)
        .onAppear {
            topics = StudyTopicStore.load()
            selectedTopicID = conversation.studyTopicID
        }
        .sheet(isPresented: $isShowingNewTopicSheet) {
            NewStudyTopicSheet(onCreate: createAndSelectStudyTopic)
        }
    }

    private func toggleSelection(of topic: StudyTopic) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            if selectedTopicID == topic.id {
                selectedTopicID = nil
                onRemoveTopic()
            } else {
                selectedTopicID = topic.id
                onSelectTopic(topic)
            }
        }
    }

    private func createAndSelectStudyTopic(title: String, description: String) {
        let topic = StudyTopic(title: title, description: description)
        topics.insert(topic, at: 0)
        StudyTopicStore.save(topics)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            selectedTopicID = topic.id
        }
        onSelectTopic(topic)
    }

    private func displayTitle(for topic: StudyTopic) -> String {
        let trimmed = topic.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Study Topic" : trimmed
    }
}

private struct SideMenuStudyTopicPickerCard: View {
    let topic: StudyTopic
    var isSelected: Bool = false
    var onSelect: () -> Void

    private var displayTitle: String {
        let trimmed = topic.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Study Topic" : trimmed
    }

    private var displayDescription: String {
        topic.description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(displayTitle)
                .font(.custom("LibreBaskerville-Regular", size: 18))
                .foregroundColor(AquinasTheme.Colors.primaryReadable)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

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
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AquinasTheme.Colors.componentBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? AquinasTheme.Colors.lightGreen : AquinasTheme.Colors.controlBorder, lineWidth: isSelected ? 2 : 1)
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AquinasTheme.Colors.lightGreen)
                    .background(AquinasTheme.Colors.componentBackground, in: Circle())
                    .padding(12)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onSelect)
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
