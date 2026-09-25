//
//  SideMenuRows.swift
//  Aquinas-iOS
//

import SwiftUI

struct SideMenuRow: View {
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
        .onAppear(perform: appearedInList)
        .onChange(of: isPresented) { oldValue, newValue in
            runEntrance()
        }
    }

    private func appearedInList() {
        if isPresented, SideMenuEntrance.isScrollRecycle {
            entranceRunID = UUID()
            showsIcon = true
            showsText = true
        } else {
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

enum ConversationModelActivity: Equatable {
    case idle
    case loading
    case completed
}

private struct ConversationActivityIndicator: View {
    let activity: ConversationModelActivity

    var body: some View {
        ZStack {
            switch activity {
            case .idle:
                Color.clear
            case .loading:
                ContextUsageIcon(
                    progress: 0,
                    color: AquinasTheme.Colors.paragraphText.opacity(0.75),
                    isSpinning: true
                )
                .transition(.opacity)
            case .completed:
                Circle()
                    .fill(Color(red: 0.25, green: 0.55, blue: 1.0))
                    .frame(width: 9, height: 9)
                    .overlay(
                        Circle()
                            .stroke(AquinasTheme.Colors.sideMenuSurface, lineWidth: 1.5)
                    )
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 14, height: 14)
        .animation(.easeInOut(duration: 0.2), value: activity)
        .accessibilityHidden(activity == .idle)
        .accessibilityLabel(activity == .loading ? "Model working" : "New response")
    }
}

struct ConversationMenuRow: View {
    let conversation: InquiryConversation
    let modelActivity: ConversationModelActivity
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

            if modelActivity != .idle {
                ConversationActivityIndicator(activity: modelActivity)
            }

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
            if isPresented, SideMenuEntrance.isScrollRecycle {
                entranceRunID = UUID()
                isVisible = true
            } else {
                runEntrance()
            }
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

struct StudyTopicMenuRow: View {
    let topic: StudyTopic
    let conversations: [InquiryConversation]
    let conversationActivity: (InquiryConversation) -> ConversationModelActivity
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
                            modelActivity: conversationActivity(conversation),
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
        .onAppear {
            if isPresented, SideMenuEntrance.isScrollRecycle {
                entranceRunID = UUID()
                isVisible = true
            } else {
                runEntrance()
            }
        }
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
    let modelActivity: ConversationModelActivity
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
                if modelActivity != .idle {
                    ConversationActivityIndicator(activity: modelActivity)
                }
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
