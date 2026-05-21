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
                .background(AquinasTheme.Colors.surface)
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
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "flowchart")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isActive ? AquinasTheme.Colors.surface : AquinasTheme.Colors.lightGreen)
                .sfSymbolDrawOn()
                .frame(width: 48, height: 48)
                .background(isActive ? AquinasTheme.Colors.lightGreen : AquinasTheme.Colors.surface)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(AquinasTheme.Colors.controlBorder, lineWidth: isActive ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "Return to branch view" : "Open canvas view")
    }
}

/// Slide-out navigation panel mirrored from Figma's "03 - User Screen Flow" side-panel frames.
struct AquinasSideMenu: View {
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
    var onDeleteConversation: (InquiryConversation) -> Void
    var newInsightsCount: Int = 0
    var onOpenConversations: () -> Void
    var onOpenInsights: () -> Void
    var onOpenSettings: () -> Void
    var onClose: () -> Void
    @State private var showsTitle = false
    @State private var showsOpenConversationsTitle = false
    @State private var conversationBeingRenamed: InquiryConversation? = nil
    @State private var renameDraft = ""

    var body: some View {
        GeometryReader { geometry in
            let topPadding = max(24, geometry.safeAreaInsets.top + 16)

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 24) {
                    Text(createEditorialTitle(
                        fullText: currentTitle,
                        keyword: "The Didache?",
                        fontSize: 28,
                        baseColor: AquinasTheme.Colors.primaryReadable,
                        keywordColor: AquinasTheme.Colors.lightGreen
                    ))
                        .lineSpacing(8)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(showsTitle ? 1 : 0)
                        .offset(x: showsTitle ? 0 : -24)

                    VStack(alignment: .leading, spacing: 24) {
                        SearchRow(isPresented: isPresented, delay: 0.15)

                        VStack(alignment: .leading, spacing: 0) {
                            SideMenuRow(icon: "house", title: "Home", isPresented: isPresented, delay: 0.20, action: {})
                            SideMenuRow(
                                icon: "bubble.left.and.bubble.right",
                                title: "Conversations",
                                isActive: activePage == .openConversations,
                                isPresented: isPresented,
                                delay: 0.25,
                                action: onOpenConversations
                            )
                            SideMenuRow(
                                icon: "brain.head.profile",
                                title: "Insights",
                                badge: newInsightsCount,
                                isActive: activePage == .insights,
                                isPresented: isPresented,
                                delay: 0.30,
                                action: onOpenInsights
                            )
                            SideMenuRow(icon: "doc", title: "Files", isPresented: isPresented, delay: 0.35, action: {})
                        }
                    }
                }

                FooterDivider(isPresented: isPresented, delay: 0)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Recents")
                        .font(.custom("Figtree-Bold", size: 18))
                        .lineSpacing(9)
                        .foregroundColor(AquinasTheme.Colors.primaryReadable)
                        .opacity(showsOpenConversationsTitle ? 1 : 0)
                        .offset(x: showsOpenConversationsTitle ? 0 : -24)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(conversations.enumerated()), id: \.element.id) { index, conversation in
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
                                onDelete: {
                                    onDeleteConversation(conversation)
                                }
                            )
                        }
                    }
                }
            }

            Spacer(minLength: 24)

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
                        Text("New Chat")
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
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .padding(.top, topPadding)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(AquinasTheme.Colors.sideMenuSurface)
        .clipShape(.rect(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 24, topTrailingRadius: 24))
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 24, topTrailingRadius: 24)
                .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
        )
        .ignoresSafeArea()
        .onAppear(perform: runTitleEntrance)
        .onChange(of: isPresented) { oldValue, newValue in
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

    private func runTitleEntrance() {
        showsTitle = false
        showsOpenConversationsTitle = false
        guard isPresented else { return }

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

private struct SearchRow: View {
    let isPresented: Bool
    let delay: TimeInterval
    @State private var showsIcon = false
    @State private var showsText = false
    @State private var showsBackground = false
    @State private var borderDrawProgress: CGFloat = 0

    var body: some View {
        HStack(spacing: 24) {
            Group {
                if showsIcon {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AquinasTheme.Colors.lightGreen)
                        .sfSymbolDrawOn()
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .hidden()
                }
            }

            Text("Search")
                .font(.custom("LibreBaskerville-Regular", size: 14))
                .lineSpacing(9)
                .foregroundColor(AquinasTheme.Colors.placeholderText)
                .opacity(showsText ? 1 : 0)
                .offset(x: showsText ? 0 : -10)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AquinasTheme.Colors.canvas.opacity(showsBackground ? 1 : 0))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .inset(by: 0.5)
                .trim(from: 0, to: borderDrawProgress)
                .stroke(AquinasTheme.Colors.sideMenuSearchBorder, lineWidth: 1)
        )
        .onAppear(perform: runEntrance)
        .onChange(of: isPresented) { oldValue, newValue in
            runEntrance()
        }
    }

    private func runEntrance() {
        showsIcon = false
        showsText = false
        showsBackground = false
        borderDrawProgress = 0
        guard isPresented else { return }

        withAnimation(.easeOut(duration: 0.25)) {
            showsBackground = true
        }

        withAnimation(.easeOut(duration: 0.55)) {
            borderDrawProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeOut(duration: 0.35)) {
                showsIcon = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.025) {
            withAnimation(.easeOut(duration: 0.30)) {
                showsText = true
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 24) {
                Group {
                    if showsIcon {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AquinasTheme.Colors.lightGreen)
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
        showsIcon = false
        showsText = false
        guard isPresented else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeOut(duration: 0.35)) {
                showsIcon = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.025) {
            withAnimation(.easeOut(duration: 0.30)) {
                showsText = true
            }
        }
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
    var onDelete: () -> Void
    @State private var isVisible = false
    @State private var isOptionsMenuOpen = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                Text(conversation.title)
                    .font(.custom("LibreBaskerville-Regular", size: 14))
                    .lineSpacing(7)
                    .foregroundColor(AquinasTheme.Colors.paragraphText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if isActive {
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.76)) {
                        isOptionsMenuOpen.toggle()
                    }
                }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AquinasTheme.Colors.paragraphText)
                        .frame(width: 18, height: 18)
                        .sfSymbolDrawOn(delay: delay + 0.08)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Conversation options")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isActive ? AquinasTheme.Colors.systemSelection : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(isVisible ? 1 : 0)
        .offset(x: isVisible ? 0 : -10)
        .overlay(alignment: .topTrailing) {
            if isOptionsMenuOpen {
                ZStack(alignment: .topTrailing) {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: 325, height: 700)
                        .offset(x: 24, y: -260)
                        .onTapGesture {
                            closeOptionsMenu()
                        }
                        .zIndex(0)

                    ConversationOptionsMenu(
                        onRename: {
                            closeOptionsMenu()
                            onRename()
                        },
                        onPin: {
                            closeOptionsMenu()
                            onPin()
                        },
                        onDelete: {
                            closeOptionsMenu()
                            onDelete()
                        }
                    )
                    .offset(x: 0, y: 52)
                    .zIndex(1)
                }
                .zIndex(8)
            }
        }
        .onAppear(perform: runEntrance)
        .onChange(of: isPresented) { oldValue, newValue in
            isOptionsMenuOpen = false
            runEntrance()
        }
        .zIndex(isOptionsMenuOpen ? 100 : 0)
    }

    private func runEntrance() {
        isVisible = false
        guard isPresented else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeOut(duration: 0.30)) {
                isVisible = true
            }
        }
    }

    private func closeOptionsMenu() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.76)) {
            isOptionsMenuOpen = false
        }
    }
}

struct ConversationOptionsMenu: View {
    var onRename: () -> Void
    var onPin: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            MenuOptionRow(icon: "pencil", title: "Rename", delay: 0, action: onRename)
            MenuOptionRow(icon: "pin", title: "Pin", delay: 0.05, action: onPin)
            MenuOptionRow(icon: "trash", title: "Delete", delay: 0.10, action: onDelete)
        }
        .menuPanelStyle(anchor: .topTrailing)
    }
}

private struct FooterDivider: View {
    let isPresented: Bool
    let delay: TimeInterval
    @State private var showsDivider = false

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
                .foregroundColor(AquinasTheme.Colors.accent)
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
        showsDivider = false
        guard isPresented else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeOut(duration: 0.35)) {
                showsDivider = true
            }
        }
    }
}
