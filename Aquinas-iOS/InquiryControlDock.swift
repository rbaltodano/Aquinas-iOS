//
//  InquiryControlDock.swift
//  Aquinas-iOS
//

import SwiftUI

extension Notification.Name {
    static let aquinasMiniScrollButtonVisibilityChanged = Notification.Name("aquinasMiniScrollButtonVisibilityChanged")
}

// MARK: - Bottom Control Dock

/// Swaps between the Branch-mode controls and the Canvas-mode controls.
struct InquiryControlDock: View {
    let isCanvasMode: Bool
    @Binding var showFilePicker: Bool
    @Binding var showPhotoPicker: Bool
    @Binding var showCamera: Bool
    @Binding var isThinkingEnabled: Bool
    @Binding var selectedPersonality: String
    @Binding var isPersonalityMenuOpen: Bool
    @Binding var areResponsesCollapsed: Bool
    let isAtBottom: Bool
    var onScrollToBottom: () -> Void
    var onViewEntireCanvas: () -> Void
    var onOpenInsights: () -> Void
    var onSend: () -> Void = {}

    var body: some View {
        ZStack {
            BranchControlBar(
                showFilePicker: $showFilePicker,
                showPhotoPicker: $showPhotoPicker,
                showCamera: $showCamera,
                isThinkingEnabled: $isThinkingEnabled,
                selectedPersonality: $selectedPersonality,
                isPersonalityMenuOpen: $isPersonalityMenuOpen,
                isAtBottom: isAtBottom,
                onScrollToBottom: onScrollToBottom,
                onOpenInsights: onOpenInsights,
                onSend: onSend
            )
            .offset(y: isCanvasMode ? 96 : 0)
            .opacity(isCanvasMode ? 0 : 1)

            CanvasControlBar(
                areResponsesCollapsed: $areResponsesCollapsed,
                onViewEntireCanvas: onViewEntireCanvas
            )
            .offset(y: isCanvasMode ? 0 : 96)
            .opacity(isCanvasMode ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 76)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: isCanvasMode)
    }
}

struct BranchControlBar: View {
    @Binding var showFilePicker: Bool
    @Binding var showPhotoPicker: Bool
    @Binding var showCamera: Bool
    @Binding var isThinkingEnabled: Bool
    @Binding var selectedPersonality: String
    @Binding var isPersonalityMenuOpen: Bool
    let isAtBottom: Bool
    var onScrollToBottom: () -> Void
    var onOpenInsights: () -> Void
    var onSend: () -> Void = {}
    @State private var isAttachmentMenuOpen: Bool = false
    @State private var thinkingIconDrawID = UUID()
    @State private var personalityIconDrawID = UUID()
    @State private var isScrollButtonVisible: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 8) {
                // Attachment menu: photo library, document upload, camera.
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        isAttachmentMenuOpen.toggle()
                    }
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .regular))
                        .sfSymbolDrawOn()
                        .aquinasIconControl()
                }
                .overlay(alignment: .bottomLeading) {
                    if isAttachmentMenuOpen {
                        AttachmentMenu(
                            isAttachmentMenuOpen: $isAttachmentMenuOpen,
                            showPhotoPicker: $showPhotoPicker,
                            showFilePicker: $showFilePicker,
                            showCamera: $showCamera,
                            onOpenInsights: onOpenInsights
                        )
                        .offset(y: -56)
                    }
                }

                // Thinking toggle: visual only for now, ready to connect to model settings.
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        let isTurningOn = !isThinkingEnabled
                        isThinkingEnabled.toggle()
                        if isTurningOn {
                            thinkingIconDrawID = UUID()
                        }
                    }
                }) {
                    HStack(spacing: 10) {
                        if isThinkingEnabled {
                            Image(systemName: "globe")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(AquinasTheme.Colors.canvas)
                                .id(thinkingIconDrawID)
                                .sfSymbolDrawOn()
                        } else {
                            Image(systemName: "globe")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(AquinasTheme.Colors.secondaryMuted)
                        }
                        Text("Thinking")
                            .font(.custom("Figtree-Bold", size: 12))
                            .foregroundColor(isThinkingEnabled ? AquinasTheme.Colors.canvas : AquinasTheme.Colors.secondaryMuted)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(minHeight: AquinasTheme.Spacing.controlHeight)
                    .background(isThinkingEnabled ? AquinasTheme.Colors.secondaryMuted : AquinasTheme.Colors.surface)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(AquinasTheme.Colors.controlBorder, lineWidth: isThinkingEnabled ? 0 : 1)
                    )
                }

                // Personality selector: currently toggles between Friendly and Scholarly.
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        isPersonalityMenuOpen.toggle()
                    }
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: selectedPersonality == "Friendly" ? "brain.head.profile.fill" : "book.pages.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AquinasTheme.Colors.linkGreen)
                            .frame(width: 16, height: 16)
                            .id(personalityIconDrawID)
                            .sfSymbolDrawOn()
                        Text(selectedPersonality)
                            .font(.custom("Figtree-Bold", size: 12))
                            .foregroundColor(AquinasTheme.Colors.lightGreen)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AquinasTheme.Colors.linkGreen)
                            .sfSymbolDrawOn()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .aquinasCapsuleControl()
                }
                .overlay(alignment: .bottomLeading) {
                    if isPersonalityMenuOpen {
                        PersonalityMenu(
                            selectedPersonality: $selectedPersonality,
                            isPersonalityMenuOpen: $isPersonalityMenuOpen
                        )
                        .offset(y: -56)
                    }
                }

                // Send button — always trailing; submits the active question.
                Button(action: onSend) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .sfSymbolDrawOn()
                        .aquinasIconControl(isPrimary: true)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .center)
            .background {
                ControlBarGlow()
            }

            // Appears only when the current branch is scrolled away from the bottom.
                Button(action: onScrollToBottom) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(Color(hex: 0xFFFAF0))
                        .frame(width: 24, height: 24)
                        .background(AquinasTheme.Colors.lightBrown)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(AquinasTheme.Colors.lightBrown.opacity(0.05), lineWidth: 1)
                        )
                }
            .buttonStyle(.plain)
            .offset(y: isScrollButtonVisible ? -40 : -32)
            .opacity(isScrollButtonVisible ? 1 : 0)
            .allowsHitTesting(isScrollButtonVisible)
            .zIndex(2)
            .animation(.easeInOut(duration: 0.16), value: isScrollButtonVisible)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            if isAtBottom {
                isScrollButtonVisible = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .aquinasMiniScrollButtonVisibilityChanged
        )) { notification in
            guard let isVisible = notification.userInfo?["isVisible"] as? Bool else { return }
            isScrollButtonVisible = isVisible
        }
        .onChange(of: selectedPersonality) { oldValue, newValue in
            personalityIconDrawID = UUID()
        }
    }
}

struct AttachmentMenu: View {
    @Binding var isAttachmentMenuOpen: Bool
    @Binding var showPhotoPicker: Bool
    @Binding var showFilePicker: Bool
    @Binding var showCamera: Bool
    var onOpenInsights: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            MenuOptionRow(icon: "camera", title: "Camera", delay: 0) {
                closeMenu()
                showCamera = true
            }

            MenuOptionRow(icon: "photo", title: "Photo", delay: 0.05) {
                closeMenu()
                showPhotoPicker = true
            }

            MenuOptionRow(icon: "doc", title: "File", delay: 0.10) {
                closeMenu()
                showFilePicker = true
            }

            MenuOptionRow(icon: "text.bubble", title: "Insights", delay: 0.15) {
                closeMenu()
                onOpenInsights()
            }
        }
        .menuPanelStyle(anchor: .bottomLeading)
    }

    private func closeMenu() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            isAttachmentMenuOpen = false
        }
    }
}

struct PersonalityMenu: View {
    @Binding var selectedPersonality: String
    @Binding var isPersonalityMenuOpen: Bool

    var body: some View {
        // Replace these two rows when the real personality picker grows beyond two options.
        VStack(alignment: .leading, spacing: 24) {
            MenuOptionRow(icon: "book.pages", title: "Scholarly", delay: 0) {
                selectPersonality("Scholarly")
            }

            MenuOptionRow(icon: "brain.head.profile.fill", title: "Friendly", delay: 0.05) {
                selectPersonality("Friendly")
            }
        }
        .menuPanelStyle(anchor: .bottomLeading)
    }

    private func selectPersonality(_ personality: String) {
        selectedPersonality = personality
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            isPersonalityMenuOpen = false
        }
    }
}

struct MenuOptionRow: View {
    let icon: String
    let title: String
    let delay: TimeInterval
    var action: () -> Void
    @State private var showsIcon = false
    @State private var showsText = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Group {
                    if showsIcon {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AquinasTheme.Colors.lightGreen)
                            .frame(width: 16, height: 16)
                            .sfSymbolDrawOn()
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 16, height: 16)
                            .hidden()
                    }
                }

                Text(title)
                    .font(.custom("LibreBaskerville-Bold", size: 12))
                    .foregroundColor(AquinasTheme.Colors.lightGreen)
                    .lineLimit(1)
                    .opacity(showsText ? 1 : 0)
                    .offset(x: showsText ? 0 : -10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .onAppear(perform: runEntrance)
    }

    private func runEntrance() {
        showsIcon = false
        showsText = false

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

struct MenuPanelStyle: ViewModifier {
    let anchor: UnitPoint

    func body(content: Content) -> some View {
        content
            .fixedSize()
            .padding(.horizontal, 36)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AquinasTheme.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
            )
            .transition(.scale(scale: 0.92, anchor: anchor).combined(with: .opacity))
    }
}

extension View {
    func menuPanelStyle(anchor: UnitPoint) -> some View {
        modifier(MenuPanelStyle(anchor: anchor))
    }
}

struct CanvasControlBar: View {
    @Binding var areResponsesCollapsed: Bool
    var onViewEntireCanvas: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Max-fit overview toggle.
            Button(action: onViewEntireCanvas) {
                HStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2")
                        .sfSymbolDrawOn()
                    Text("View Entire Canvas")
                        .font(.figtreeHeading2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .aquinasCapsuleControl()
            }
            .frame(maxWidth: .infinity)

            // Global response visibility toggle.
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    areResponsesCollapsed.toggle()
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: areResponsesCollapsed ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                        .sfSymbolDrawOn()
                    Text(areResponsesCollapsed ? "Expand Responses" : "Collapse Responses")
                        .font(.figtreeHeading2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .aquinasCapsuleControl(isSelected: areResponsesCollapsed)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .center)
        .background {
            ControlBarGlow()
        }
    }
}

private struct ControlBarGlow: View {
    private let glowColor = AquinasTheme.Colors.controlGlow

    var body: some View {
        // Floating glow behind the dock. Increase blur/radius for a softer fade.
        Rectangle()
            .fill(glowColor)
            .frame(height: 170)
            .frame(maxWidth: .infinity)
            .blur(radius: 72)
            .offset(y: 46)
            .shadow(color: glowColor, radius: 72, x: 0, y: 48)
        .allowsHitTesting(false)
    }
}
