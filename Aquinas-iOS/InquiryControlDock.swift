//
//  InquiryControlDock.swift
//  Aquinas-iOS
//

import SwiftUI

extension Notification.Name {
    static let aquinasMiniScrollButtonVisibilityChanged = Notification.Name("aquinasMiniScrollButtonVisibilityChanged")
}

// MARK: - Bottom Control Dock

/// A single persistent control surface whose contents adapt to Branch and Canvas mode.
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
    var isKeyboardOpen: Bool = false
    var showsSendButton: Bool = false
    var hasCanvasHover: Bool = false
    var hasCanvasInsightHover: Bool = false
    var hasSelectedCanvasItems: Bool = false
    var selectedCanvasItemCount: Int = 0
    var onScrollToBottom: () -> Void
    var onViewEntireCanvas: () -> Void
    var onOpenInsights: () -> Void
    var onSend: () -> Void = {}
    var onSelectCanvasItem: () -> Void = {}
    var onCreateCanvasConcept: () -> Void = {}
    var onInquireConnection: () -> Void = {}
    var onQuoteCanvasItem: () -> Void = {}
    var onMidpointConcepts: () -> Void = {}
    var isMidpointMode: Bool = false
    var onMidpointCenter: () -> Void = {}
    var onMidpointPlace: () -> Void = {}
    var onClearCanvasSelection: () -> Void = {}

    @State private var isAttachmentMenuOpen = false
    @State private var thinkingIconDrawID = UUID()
    @State private var canvasActionDrawID = UUID()
    @State private var isScrollButtonVisible = false
    @State private var controlScale: CGFloat = 1

    private var controlCount: Int {
        if isCanvasMode && isMidpointMode {
            return 2 + 1 // Center + Place + context
        }
        let attachmentCount = isCanvasMode ? 0 : 1
        let thinkingCount = isCanvasMode ? 0 : 1
        let canvasActionCount: Int
        if !isCanvasMode {
            canvasActionCount = 0
        } else if hasSelectedCanvasItems {
            if selectedCanvasItemCount == 2 {
                canvasActionCount = 3 // Select + Quote + Midpoint
            } else if selectedCanvasItemCount > 2 {
                canvasActionCount = 2 // Select + Midpoint
            } else {
                canvasActionCount = 1 // Select only
            }
        } else if hasCanvasInsightHover {
            canvasActionCount = 3 // Select + Quote + Make Node
        } else if hasCanvasHover {
            canvasActionCount = 2 // Select + Quote
        } else {
            canvasActionCount = 0
        }
        return attachmentCount + thinkingCount + canvasActionCount + 1 + (showsSendButton ? 1 : 0)
    }

    var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .center, spacing: 24) {
                if !isCanvasMode {
                    attachmentButton
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }

                if !isCanvasMode {
                    thinkingButton
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }

                if isCanvasMode && isMidpointMode {
                    canvasActionButton(title: "Center", icon: "lines.measurement.horizontal", action: onMidpointCenter)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                    canvasActionButton(title: "Place", icon: "arrow.down", action: onMidpointPlace)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                } else if isCanvasMode && (hasCanvasHover || hasSelectedCanvasItems) {
                    selectCanvasActionButton

                    if hasSelectedCanvasItems && selectedCanvasItemCount == 2 {
                        canvasActionButton(title: "Quote", icon: "arrow.turn.down.right", action: onInquireConnection)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                        canvasActionButton(title: "Midpoint", icon: "graph.2d", action: onMidpointConcepts)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    } else if hasSelectedCanvasItems && selectedCanvasItemCount > 2 {
                        canvasActionButton(title: "Midpoint", icon: "graph.2d", action: onMidpointConcepts)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    } else if hasCanvasInsightHover && !hasSelectedCanvasItems {
                        canvasActionButton(title: "Quote", icon: "arrow.turn.down.right", action: onQuoteCanvasItem)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                        canvasActionButton(title: "Make Node", icon: "move.3d", action: onCreateCanvasConcept)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    } else if hasCanvasHover && !hasSelectedCanvasItems {
                        canvasActionButton(title: "Quote", icon: "arrow.turn.down.right", action: onQuoteCanvasItem)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }

                contextButton

                if showsSendButton {
                    sendButton
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .fixedSize(horizontal: true, vertical: true)
            .background(AquinasTheme.Colors.canvasSecondary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1))
            .scaleEffect(controlScale)
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: controlCount)

            if !isCanvasMode {
                scrollToBottomButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, isKeyboardOpen ? 8 : 24)
        .background(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: AquinasTheme.Colors.canvas.opacity(0.95), location: 0),
                    .init(color: AquinasTheme.Colors.canvas.opacity(0), location: 1)
                ],
                startPoint: UnitPoint(x: 0.5, y: 0.52),
                endPoint: UnitPoint(x: 0.5, y: 0)
            )
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
        .onAppear {
            isScrollButtonVisible = !isAtBottom
        }
        .onReceive(NotificationCenter.default.publisher(for: .aquinasMiniScrollButtonVisibilityChanged)) { notification in
            guard let isVisible = notification.userInfo?["isVisible"] as? Bool else { return }
            isScrollButtonVisible = isVisible
        }
        .onChange(of: controlCount) { _, _ in
            controlScale = 1.05
            withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
                controlScale = 1
            }
        }
        .onChange(of: hasCanvasHover) { _, selected in
            if selected { canvasActionDrawID = UUID() }
        }
    }

    private var attachmentButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                isAttachmentMenuOpen.toggle()
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AquinasTheme.Colors.lightGreen)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
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
    }

    private var thinkingButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isThinkingEnabled.toggle()
                if isThinkingEnabled { thinkingIconDrawID = UUID() }
            }
        } label: {
            let inactiveThinkingColor = AquinasTheme.Colors.paragraphText.opacity(0.75)
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 14, weight: .semibold))
                    .id(thinkingIconDrawID)
                    .sfSymbolDrawOn()
                Text("Thinking")
                    .font(.custom("Figtree-Bold", size: 14))
            }
            .frame(height: 16, alignment: .center)
            .foregroundColor(isThinkingEnabled ? AquinasTheme.Colors.accentGreen : inactiveThinkingColor)
        }
        .buttonStyle(.plain)
    }

    private var contextButton: some View {
        Button {
            if hasSelectedCanvasItems {
                onClearCanvasSelection()
            }
        } label: {
            let contextColor = AquinasTheme.Colors.paragraphText.opacity(0.75)
            HStack(spacing: 8) {
                if hasSelectedCanvasItems {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                } else {
                    ContextUsageIcon(progress: 0.36, color: contextColor)
                }
                if !hasCanvasHover && !hasSelectedCanvasItems {
                    Text("Context")
                        .font(.custom("Figtree-Bold", size: 14))
                        .transition(.offset(x: -12).combined(with: .opacity))
                }
            }
            .frame(height: 16, alignment: .center)
            .foregroundColor(contextColor)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hasCanvasHover)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hasSelectedCanvasItems)
        }
        .buttonStyle(.plain)
    }

    private func canvasActionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .id("\(title)-\(canvasActionDrawID)")
                    .sfSymbolDrawOn()
                Text(title)
                    .font(.custom("Figtree-Bold", size: 14))
            }
            .frame(height: 16, alignment: .center)
            .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
        }
        .buttonStyle(.plain)
    }

    private var selectCanvasActionButton: some View {
        Button(action: onSelectCanvasItem) {
            HStack(spacing: 8) {
                selectionCountIcon
                Text(selectedCanvasItemCount >= 1 ? "Add" : "Select")
                    .font(.custom("Figtree-Bold", size: 14))
            }
            .frame(height: 16, alignment: .center)
            .foregroundColor(selectedCanvasItemCount >= 1 ? AquinasTheme.Colors.accentGreen : AquinasTheme.Colors.paragraphText.opacity(0.75))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var selectionCountIcon: some View {
        if selectedCanvasItemCount > 0 {
            ZStack {
                Circle()
                    .fill(AquinasTheme.Colors.accentGreen)
                Text("\(min(selectedCanvasItemCount, 99))")
                    .font(.custom("Figtree-Bold", size: selectedCanvasItemCount > 9 ? 7 : 8))
                    .foregroundColor(AquinasTheme.Colors.canvasSecondary)
            }
            .frame(width: 14, height: 14)
            .transition(.scale(scale: 0.5).combined(with: .opacity))
        } else {
            Image(systemName: "circle.dashed")
                .font(.system(size: 14, weight: .semibold))
                .id("select-\(canvasActionDrawID)")
                .sfSymbolDrawOn()
        }
    }

    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AquinasTheme.Colors.lightGreen)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
    }

    private var scrollToBottomButton: some View {
        Button(action: onScrollToBottom) {
            Image(systemName: "arrow.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(Color(hex: 0xFFFAF0))
                .frame(width: 24, height: 24)
                .background(AquinasTheme.Colors.lightBrown)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .offset(y: isScrollButtonVisible ? -36 : -28)
        .opacity(isScrollButtonVisible ? 1 : 0)
        .allowsHitTesting(isScrollButtonVisible)
        .animation(.easeInOut(duration: 0.16), value: isScrollButtonVisible)
    }
}

private struct ContextUsageIcon: View {
    let progress: CGFloat
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.35), lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 14, height: 14)
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
            MenuOptionRow(icon: "camera", title: "Camera", delay: 0) { closeMenu(); showCamera = true }
            MenuOptionRow(icon: "photo", title: "Photo", delay: 0.05) { closeMenu(); showPhotoPicker = true }
            MenuOptionRow(icon: "doc", title: "File", delay: 0.10) { closeMenu(); showFilePicker = true }
            MenuOptionRow(icon: "text.bubble", title: "Insights", delay: 0.15) { closeMenu(); onOpenInsights() }
        }
        .menuPanelStyle(anchor: .bottomLeading)
    }

    private func closeMenu() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { isAttachmentMenuOpen = false }
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
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 16, height: 16)
                    .foregroundColor(AquinasTheme.Colors.lightGreen)
                    .opacity(showsIcon ? 1 : 0)
                    .sfSymbolDrawOn(delay: delay)
                Text(title)
                    .font(.custom("LibreBaskerville-Bold", size: 12))
                    .foregroundColor(AquinasTheme.Colors.lightGreen)
                    .opacity(showsText ? 1 : 0)
                    .offset(x: showsText ? 0 : -10)
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3).delay(delay)) {
                showsIcon = true
                showsText = true
            }
        }
    }
}

private struct MenuPanelStyle: ViewModifier {
    let anchor: UnitPoint

    func body(content: Content) -> some View {
        content
            .fixedSize()
            .padding(.horizontal, 36)
            .padding(.vertical, 24)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(AquinasTheme.Colors.canvasSecondary))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1))
            .transition(.scale(scale: 0.92, anchor: anchor).combined(with: .opacity))
    }
}

private extension View {
    func menuPanelStyle(anchor: UnitPoint) -> some View {
        modifier(MenuPanelStyle(anchor: anchor))
    }
}
