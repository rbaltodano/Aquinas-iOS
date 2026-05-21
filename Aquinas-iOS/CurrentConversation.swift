//
//  CurrentConversation.swift
//  Aquinas-iOS
//
//  Clean-room canvas built on InsightTree's camera architecture.
//
//  Key design principles (mirroring InsightTreeCanvasView):
//    • Pure camera model — scale + offset + @GestureState dragOffset
//    • Thread cards are ALWAYS Metal textures (.drawingGroup) on the canvas layer
//    • Focused content is a separate ScrollView overlay; no mode-switch in the canvas
//    • Tap → camera springs to thread (InsightTree's focusInsight pattern)
//    • preFocusCamera → swipe/pinch restores exact pre-tap camera state
//    • Momentum pan (decay 0.18) matches the InsightTree smooth-feel expectation
//

import SwiftUI
import UIKit
import PhotosUI

// MARK: - Persistence

private enum CCStore {
    static let key = "aquinas.cc2.threads.v1"

    static func load() -> [CanvasThread]? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([CanvasThread].self, from: data)
    }

    static func save(_ threads: [CanvasThread]) {
        let clean = threads.map { t -> CanvasThread in var c = t; c.isGenerating = false; return c }
        if let data = try? JSONEncoder().encode(clean) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Camera Snapshot

private struct CCCameraSnapshot {
    let scale:  CGFloat
    let offset: CGSize
}

// MARK: - Shell

/// Drop-in replacement for ConversationCanvasView.
/// Manages persistence and side-menu state; delegates all canvas rendering to CCMapView.
struct CurrentConversationView: View {
    var onOpenMenu: () -> Void = {}
    @Binding var collectedDefinitions:       [ConceptDefinition]
    @Binding var sideMenuConversations:      [InquiryConversation]
    @Binding var sideMenuCurrentTitle:       String
    @Binding var sideMenuActiveConversationID: UUID?
    @Binding var requestedConversationID:    UUID?
    @Binding var newConversationRequest:     Int
    @Binding var deletedConversationID:      UUID?
    @Binding var requestedForkConcept:       ConceptDefinition?

    @State private var threads:    [CanvasThread] = []
    @State private var canvasSize: CGSize = UIScreen.main.bounds.size

    var body: some View {
        GeometryReader { geo in
            CCMapView(
                threads:              $threads,
                collectedDefinitions: $collectedDefinitions,
                onOpenMenu:           onOpenMenu
            )
            .ignoresSafeArea()
            .onAppear {
                canvasSize = geo.size
                if let saved = CCStore.load(), !saved.isEmpty { threads = saved }
                if threads.isEmpty { threads = [CanvasThread()] }
            }
            .onChange(of: geo.size)       { _, s in canvasSize = s }
            .onChange(of: threads)        { _, new in CCStore.save(new); publishShellState() }
            .onChange(of: requestedConversationID) { _, id in
                guard let id, let thread = threads.first(where: { $0.id == id }) else { return }
                requestedConversationID = nil
                _ = thread   // CCMapView handles focus internally via focusRequest
            }
            .onChange(of: newConversationRequest) { _, _ in
                let fresh = CanvasThread()
                withAnimation(.spring(response: 0.52, dampingFraction: 0.74)) {
                    threads.append(fresh)
                }
            }
            .onChange(of: deletedConversationID) { _, id in
                guard let id else { return }
                deletedConversationID = nil
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    threads.removeAll { $0.id == id || $0.parentID == id }
                }
                if threads.isEmpty { threads = [CanvasThread()] }
            }
            .onChange(of: requestedForkConcept) { _, concept in
                guard let concept else { return }
                requestedForkConcept = nil
                let fresh = CanvasThread(title: concept.word.capitalized)
                threads.append(fresh)
            }
        }
    }

    private func publishShellState() {
        let topLevel = threads.filter { $0.parentID == nil }
        sideMenuConversations = topLevel.map { thread in
            let blocks: [ChatBlock] = thread.messages.compactMap { msg in
                switch msg.role {
                case .user:      return .user(msg.text, msg.quotedConcept, msg.attachments)
                case .assistant: return .text(msg.text)
                }
            }
            var b = ChatBranch(startingConcept: nil, parentBranchID: nil)
            b.activeChatBlocks = blocks
            b.topQuestionText  = thread.messages.first(where: { $0.role == .user })?.text ?? ""
            b.topQuestionSubmitted = !thread.messages.isEmpty
            return InquiryConversation(id: thread.id, title: thread.title, branches: [b])
        }
        sideMenuCurrentTitle = threads.first?.title ?? "New Conversation"
    }
}

// MARK: - Camera Canvas

private struct CCMapView: View {

    @Binding var threads:              [CanvasThread]
    @Binding var collectedDefinitions: [ConceptDefinition]
    var onOpenMenu: () -> Void

    // ── Camera (InsightTree architecture) ────────────────────────────────────
    @State  private var scale:            CGFloat = 1.0
    @State  private var offset:           CGSize  = .zero
    @GestureState private var dragOffset: CGSize  = .zero
    @State  private var pinchStartScale:  CGFloat?
    @State  private var pinchStartOffset: CGSize?
    @State  private var preFocusCamera:   CCCameraSnapshot?
    @State  private var lastDragEnd:      Date    = .distantPast
    @State  private var isDragging:       Bool    = false
    @State  private var canvasSize:       CGSize  = .zero

    // ── Focus ─────────────────────────────────────────────────────────────────
    @State private var focusedID: UUID?

    // ── Input / attachment ────────────────────────────────────────────────────
    @State private var sendTrigger:          Bool  = false
    @State private var uploadedFiles:        [UploadedFile]       = []
    @State private var attachedConcept:      ConceptDefinition?   = nil
    @State private var showFilePicker:       Bool  = false
    @State private var showPhotoPicker:      Bool  = false
    @State private var selectedPhotoItems:   [PhotosPickerItem]   = []
    @State private var showCamera:           Bool  = false
    @State private var isThinkingEnabled:    Bool  = false
    @State private var selectedPersonality:  String = "Friendly"
    @State private var isPersonalityMenuOpen: Bool = false
    @State private var isInsightLibraryOpen: Bool  = false

    // ── Constants ─────────────────────────────────────────────────────────────
    private let laneSpacing:    CGFloat = 88
    private let focusThreshold: CGFloat = 0.85

    // ── Derived ───────────────────────────────────────────────────────────────
    private var activeScale:  CGFloat { ccClamp(scale, 0.20, 1.0) }
    private var activeOffset: CGSize  {
        CGSize(width:  offset.width  + dragOffset.width,
               height: offset.height + dragOffset.height)
    }
    private var isFocused:    Bool { activeScale >= focusThreshold && focusedID != nil }
    private var canAcceptTap: Bool { !isDragging && Date().timeIntervalSince(lastDragEnd) > 0.16 }

    // ── Camera projection — top-left origin, Y↓ ──────────────────────────────
    private func worldToScreen(_ pt: CGPoint) -> CGPoint {
        CGPoint(x: pt.x * activeScale + activeOffset.width,
                y: pt.y * activeScale + activeOffset.height)
    }

    private func worldOrigin(for thread: CanvasThread, laneWidth: CGFloat) -> CGPoint {
        let idx = threads.firstIndex(where: { $0.id == thread.id }) ?? 0
        return CGPoint(x: CGFloat(idx) * (laneWidth + laneSpacing),
                       y: thread.estimatedWorldY)
    }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            ZStack(alignment: .topLeading) {
                // ── Background ──────────────────────────────────────────────
                AquinasTheme.Colors.canvas.ignoresSafeArea()

                // ── Connector lines (parent → child, settled offset only) ───
                connectorCanvas(in: size)

                // ── Thread cards — ALWAYS drawingGroup Metal textures ───────
                ForEach(Array(threads.enumerated()), id: \.element.id) { index, thread in
                    let origin = worldOrigin(for: thread, laneWidth: size.width)
                    let screen = worldToScreen(origin)

                    CCThreadCard(thread: thread)
                        .frame(width: size.width)
                        .background(AquinasTheme.Colors.canvas)
                        .drawingGroup()
                        .allowsHitTesting(false)
                        .scaleEffect(activeScale, anchor: .topLeading)
                        .offset(x: screen.x, y: screen.y)
                        .zIndex(Double(index + 1))
                }

                // ── Focused thread overlay ───────────────────────────────────
                // Fades in once the camera reaches focus threshold.
                // Pure ScrollView — no mode-switch in the canvas layer.
                if isFocused, let id = focusedID,
                   let thread = threads.first(where: { $0.id == id }) {
                    CCFocusedOverlay(
                        thread:         thread,
                        threads:        $threads,
                        uploadedFiles:  $uploadedFiles,
                        attachedConcept: $attachedConcept,
                        sendTrigger:    $sendTrigger,
                        size:           size,
                        onUnfocus:      { unfocusThread(in: size) },
                        onForkThread:   { forked in
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                threads.append(forked)
                            }
                            // Auto-focus the new fork
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                focusThread(forked, in: size)
                            }
                        }
                    )
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity)
                    .zIndex(100)
                }

                // ── Top chrome: menu (left) + mode toggle (right) ────────────
                VStack {
                    HStack {
                        ccChromButton(icon: "line.3.horizontal.decrease", action: onOpenMenu)
                        Spacer()
                        ccChromButton(icon: isFocused ? "flowchart" : "viewfinder") {
                            toggleMode(in: size)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    Spacer()
                }
                .zIndex(200)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(panGesture)
            .simultaneousGesture(zoomGesture(in: size))
            .gesture(tapGesture(in: size))
            .onChange(of: sendTrigger) { _, _ in
                guard let id = focusedID, let t = threads.first(where: { $0.id == id }) else { return }
                submitMessage(to: t)
            }
            .onAppear {
                canvasSize = size
                // Start focused on the first thread
                if let first = threads.first {
                    focusedID = first.id
                    let idx = 0
                    offset = CGSize(width: -CGFloat(idx) * (size.width + laneSpacing),
                                   height: -first.estimatedWorldY)
                    scale = 1.0
                }
            }
            .onChange(of: size) { _, s in canvasSize = s }
            .onChange(of: threads) { old, new in
                // Auto-focus a newly appended thread (fork)
                if new.count > old.count, let newest = new.last, newest.messages.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        focusThread(newest, in: size)
                    }
                }
            }
        }
        // ── BranchControlBar ─────────────────────────────────────────────────
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BranchControlBar(
                showFilePicker:       $showFilePicker,
                showPhotoPicker:      $showPhotoPicker,
                showCamera:           $showCamera,
                isThinkingEnabled:    $isThinkingEnabled,
                selectedPersonality:  $selectedPersonality,
                isPersonalityMenuOpen: $isPersonalityMenuOpen,
                isAtBottom:           true,
                onScrollToBottom:     {},
                onOpenInsights: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        isInsightLibraryOpen = true
                    }
                },
                onSend: { sendTrigger.toggle() }
            )
            .padding(.bottom, 16)
            .opacity(isFocused ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
        }
        // ── Attachment pickers ────────────────────────────────────────────────
        .fileImporter(isPresented: $showFilePicker,
                      allowedContentTypes: [.image, .pdf, .audio, .plainText],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                for url in urls {
                    let ok = url.startAccessingSecurityScopedResource()
                    defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url) {
                        uploadedFiles.append(UploadedFile(
                            name: url.lastPathComponent,
                            imageData: UIImage(data: data) != nil ? data : nil,
                            rotationDegrees: Double.random(in: -5...5)))
                    }
                }
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItems,
                      maxSelectionCount: 8, matching: .images)
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       UIImage(data: data) != nil {
                        await MainActor.run {
                            uploadedFiles.append(UploadedFile(name: "Photo", imageData: data,
                                                              rotationDegrees: Double.random(in: -5...5)))
                        }
                    }
                }
                await MainActor.run { selectedPhotoItems.removeAll() }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView { image in
                if let data = image.jpegData(compressionQuality: 0.86) {
                    uploadedFiles.append(UploadedFile(name: "Camera Photo", imageData: data,
                                                      rotationDegrees: Double.random(in: -5...5)))
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Focus (InsightTree's focusInsight / restorePreFocusCamera pattern)

    private func focusThread(_ thread: CanvasThread, in size: CGSize) {
        if preFocusCamera == nil {
            preFocusCamera = CCCameraSnapshot(scale: scale, offset: offset)
        }
        let idx  = threads.firstIndex(where: { $0.id == thread.id }) ?? 0
        let wx   = CGFloat(idx) * (size.width + laneSpacing)
        let wy   = thread.estimatedWorldY
        withAnimation(.spring(response: 0.52, dampingFraction: 0.74)) {
            focusedID = thread.id
            scale     = 1.0
            offset    = CGSize(width: -wx, height: -wy)
        }
    }

    private func unfocusThread(in size: CGSize) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        if let snap = preFocusCamera {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.80)) {
                focusedID = nil
                scale     = snap.scale
                offset    = snap.offset
            }
            preFocusCamera = nil
        } else {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.80)) {
                focusedID = nil
                scale     = overviewScale(in: size)
                offset    = overviewOffset(in: size)
            }
        }
    }

    private func toggleMode(in size: CGSize) {
        if focusedID != nil {
            unfocusThread(in: size)
        } else {
            guard let thread = threads.first else { return }
            focusThread(thread, in: size)
        }
    }

    private func overviewScale(in size: CGSize) -> CGFloat {
        guard threads.count > 1, size.width > 0 else { return 0.88 }
        let worldW = CGFloat(threads.count) * size.width + CGFloat(threads.count - 1) * laneSpacing
        return min(0.88, max(0.24, (size.width - 32) / worldW))
    }

    private func overviewOffset(in size: CGSize) -> CGSize {
        let s = overviewScale(in: size)
        let worldCx = size.width / 2   // center of lane 0
        return CGSize(width: size.width / 2 - worldCx * s, height: 0)
    }

    // MARK: Gestures

    /// Pan — identical to InsightTree, + momentum on release.
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($dragOffset) { value, state, _ in
                guard !isFocused else { return }
                state = value.translation
            }
            .onChanged { value in
                guard hypot(value.translation.width, value.translation.height) > 8 else { return }
                isDragging = true
            }
            .onEnded { value in
                guard !isFocused else { return }
                offset.width  += value.translation.width
                offset.height += value.translation.height
                lastDragEnd = Date()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { isDragging = false }
                let decay: CGFloat = 0.18
                withAnimation(.spring(response: 0.68, dampingFraction: 0.86)) {
                    offset.width  += value.velocity.width  * decay
                    offset.height += value.velocity.height * decay
                }
            }
    }

    /// Zoom — identical to InsightTree; pinch-to-exit-focus on big pinch-out.
    private func zoomGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                if pinchStartScale == nil {
                    pinchStartScale  = scale
                    pinchStartOffset = offset
                }
                applyZoom(value.magnification, anchor: value.startAnchor, in: size)
            }
            .onEnded { value in
                applyZoom(value.magnification, anchor: value.startAnchor, in: size)
                if isFocused && scale < focusThreshold - 0.05 {
                    unfocusThread(in: size)
                }
                pinchStartScale  = nil
                pinchStartOffset = nil
            }
    }

    private func applyZoom(_ mag: CGFloat, anchor: UnitPoint, in size: CGSize) {
        let initS = pinchStartScale  ?? scale
        let initO = pinchStartOffset ?? offset
        let minS: CGFloat = threads.count > 1
            ? max(0.20, (size.width - 32) / (CGFloat(threads.count) * (size.width + laneSpacing)))
            : 0.30
        let next = ccClamp(initS * pow(mag, 0.72), minS, 1.0)
        let pt   = CGPoint(x: anchor.x * size.width, y: anchor.y * size.height)
        let wx   = (pt.x - initO.width)  / initS
        let wy   = (pt.y - initO.height) / initS
        scale    = next
        offset   = CGSize(width: pt.x - wx * next, height: pt.y - wy * next)
    }

    /// Tap to focus a thread (overview only).
    private func tapGesture(in size: CGSize) -> some Gesture {
        SpatialTapGesture()
            .onEnded { tap in
                guard canAcceptTap && !isFocused else { return }
                let wx = (tap.location.x - activeOffset.width) / activeScale
                for thread in threads {
                    let o = worldOrigin(for: thread, laneWidth: size.width)
                    if wx >= o.x && wx < o.x + size.width {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        focusThread(thread, in: size)
                        return
                    }
                }
            }
    }

    // MARK: Connector lines

    private func connectorCanvas(in size: CGSize) -> some View {
        Canvas { ctx, _ in
            guard !isFocused else { return }
            for child in threads {
                guard let parentID = child.parentID,
                      let parent   = threads.first(where: { $0.id == parentID })
                else { continue }
                func settled(_ p: CGPoint) -> CGPoint {
                    CGPoint(x: p.x * scale + offset.width,
                            y: p.y * scale + offset.height)
                }
                let cs = settled(worldOrigin(for: child,  laneWidth: size.width))
                let ps = settled(worldOrigin(for: parent, laneWidth: size.width))
                var path = Path()
                path.move(to:    CGPoint(x: ps.x + size.width * scale, y: cs.y))
                path.addLine(to: CGPoint(x: cs.x, y: cs.y))
                ctx.stroke(path, with: .color(AquinasTheme.Colors.border),
                           style: StrokeStyle(lineWidth: max(1.5, scale * 1.5), lineCap: .round))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(x: dragOffset.width, y: dragOffset.height)
        .allowsHitTesting(false)
    }

    // MARK: Message submission (stub — replace with real model call)

    private func submitMessage(to thread: CanvasThread) {
        let text = ""   // actual text lives inside CCFocusedOverlay
        _ = text        // submission is triggered by sendTrigger; overlay handles its own input
    }

    // MARK: Chrome button

    @ViewBuilder
    private func ccChromButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AquinasTheme.Colors.darkGreen)
                .frame(width: 48, height: 48)
                .background(AquinasTheme.Colors.canvasSecondary)
                .clipShape(Circle())
                .overlay(Circle().stroke(AquinasTheme.Colors.border.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Utility

    private func ccClamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(hi, max(lo, v))
    }
}

// MARK: - Thread Card (canvas layer — always drawingGroup)

/// Static rendering of a thread for the canvas layer.
/// No interactive elements — those live in CCFocusedOverlay.
/// This view is always rasterised; streaming animations are invisible here (correct).
private struct CCThreadCard: View {
    let thread: CanvasThread

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 100)
            headerView.padding(.bottom, 16)
            ForEach(messagePairs, id: \.0.id) { pair in
                connectorLine
                questionView(pair.0)
                connectorLine
                responseCard(pair.1)
            }
            Spacer().frame(height: 1200)
        }
    }

    private var messagePairs: [(CanvasMessage, CanvasMessage?)] { ccPairs(thread.messages) }

    private var connectorLine: some View {
        Rectangle()
            .fill(AquinasTheme.Colors.border)
            .frame(width: 1, height: 25)
            .padding(.vertical, 24)
    }

    private var headerView: some View {
        VStack(spacing: 8) {
            Image("cross-1")
                .renderingMode(.template).resizable().scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundColor(AquinasTheme.Colors.accent)
            (Text("What Is ")
                .foregroundColor(AquinasTheme.Colors.primaryReadable)
             + Text(thread.title + "?")
                .italic()
                .foregroundColor(AquinasTheme.Colors.lightGreen))
                .font(.custom("LibreBaskerville-Regular", size: 28))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 144)
    }

    private func questionView(_ msg: CanvasMessage) -> some View {
        VStack(spacing: 16) {
            UploadedFileStrip(files: msg.attachments)
            if let c = msg.quotedConcept {
                BranchContextChip(title: c.word.capitalized, icon: "text.bubble.fill",
                                  isFilled: true, showRemove: false)
            }
            Text(msg.text)
                .font(.baskervilleBody)
                .foregroundColor(AquinasTheme.Colors.primaryReadable)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    private func responseCard(_ msg: CanvasMessage?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(msg == nil ? "Thinking…" : "Show Thinking")
                    .font(.figtreeHeading2)
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                if msg != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AquinasTheme.Colors.primaryReadable)
                }
            }
            .opacity(0.5)

            if let m = msg {
                Text(thread.title)
                    .font(.custom("Figtree-Bold", size: 18))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                Text(m.text)
                    .font(.figtreeParagraphLarge)
                    .foregroundColor(AquinasTheme.Colors.bodyText)
                    .lineSpacing(4)
            }
        }
        .padding(.horizontal, msg != nil ? 24 : 16)
        .padding(.vertical,   msg != nil ? 24 : 10)
        .frame(maxWidth: msg != nil ? .infinity : nil, alignment: .leading)
        .background(AquinasTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(AquinasTheme.Colors.border.opacity(0.5), lineWidth: 1))
        .padding(.horizontal, 16)
    }
}

// MARK: - Focused Overlay (full-screen ScrollView)

/// Interactive thread view shown over the canvas once the camera zooms in.
/// Handles its own input, scrolling, and fork actions.
/// The canvas layer (CCThreadCard) remains unchanged underneath — no mode switch.
private struct CCFocusedOverlay: View {
    let thread:   CanvasThread
    @Binding var threads:         [CanvasThread]
    @Binding var uploadedFiles:   [UploadedFile]
    @Binding var attachedConcept: ConceptDefinition?
    @Binding var sendTrigger:     Bool
    let size:        CGSize
    let onUnfocus:   () -> Void
    let onForkThread: (CanvasThread) -> Void

    @State  private var inputText:    String = ""
    @FocusState private var focused:  Bool

    private var lastStreamed: Bool {
        thread.messages.last(where: { $0.role == .assistant })?.hasStreamed ?? true
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 100)
                    headerView.padding(.bottom, 16)

                    if thread.messages.isEmpty {
                        connectorLine
                        inlineInput.id("input-\(thread.id)")
                    } else {
                        ForEach(messagePairs, id: \.0.id) { (user, assistant) in
                            connectorLine
                            questionRow(user).id("q-\(user.id)")
                            connectorLine
                            CCBubble(
                                thread:  thread,
                                msg:     assistant,
                                isLoading: assistant == nil,
                                threads: $threads,
                                onFork:  { idx in
                                    let forked = CanvasThread(
                                        title: thread.title + " — Branch",
                                        parentID: thread.id,
                                        parentMessageIndex: idx
                                    )
                                    onForkThread(forked)
                                }
                            )
                            .id("b-\(user.id)")
                        }
                        if !thread.isGenerating && lastStreamed {
                            connectorLine
                                .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .top)))
                            inlineInput.id("input-\(thread.id)")
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    Spacer().frame(height: size.height * 0.75)
                        .id("bottom-\(thread.id)")
                }
                .animation(.spring(response: 0.52, dampingFraction: 0.72), value: thread.isGenerating)
                .animation(.spring(response: 0.55, dampingFraction: 0.78), value: lastStreamed)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: thread.messages.count) { _, _ in
                guard let last = thread.messages.last, last.role == .user else { return }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    proxy.scrollTo("q-\(last.id)", anchor: .center)
                }
            }
            .onChange(of: focused) { _, f in
                guard f else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                    proxy.scrollTo("input-\(thread.id)", anchor: .bottom)
                }
            }
            .onChange(of: uploadedFiles.count) { _, _ in
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                    proxy.scrollTo("input-\(thread.id)", anchor: .center)
                }
            }
            .onChange(of: sendTrigger) { _, _ in submitMessage() }
        }
        .background(AquinasTheme.Colors.canvas)
        // Horizontal swipe exits focus; vertical drag belongs to the ScrollView.
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let isHoriz = abs(value.translation.width) > abs(value.translation.height) * 1.5
                    guard isHoriz && abs(value.translation.width) > 56 else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    focused = false
                    onUnfocus()
                }
        )
    }

    // MARK: Sub-views

    private var headerView: some View {
        VStack(spacing: 8) {
            Image("cross-1")
                .renderingMode(.template).resizable().scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundColor(AquinasTheme.Colors.accent)
            (Text("What Is ")
                .foregroundColor(AquinasTheme.Colors.primaryReadable)
             + Text(thread.title + "?")
                .italic()
                .foregroundColor(AquinasTheme.Colors.lightGreen))
                .font(.custom("LibreBaskerville-Regular", size: 28))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 144)
    }

    private var connectorLine: some View {
        Rectangle()
            .fill(AquinasTheme.Colors.border)
            .frame(width: 1, height: 25)
            .padding(.vertical, 24)
    }

    private func questionRow(_ msg: CanvasMessage) -> some View {
        VStack(spacing: 16) {
            UploadedFileStrip(files: msg.attachments)
            if let c = msg.quotedConcept {
                BranchContextChip(title: c.word.capitalized, icon: "text.bubble.fill",
                                  isFilled: true, showRemove: false)
            }
            Text(msg.text)
                .font(.baskervilleBody)
                .foregroundColor(AquinasTheme.Colors.primaryReadable)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    private var inlineInput: some View {
        VStack(spacing: 16) {
            UploadedFileStrip(files: uploadedFiles) { f in
                uploadedFiles.removeAll { $0.id == f.id }
            }
            if let c = attachedConcept {
                BranchContextChip(
                    title: c.word.capitalized, icon: "text.bubble",
                    isFilled: false, showRemove: true,
                    onRemove: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            attachedConcept = nil
                        }
                    }
                )
            }
            TextField("Ask Theo a question", text: $inputText, axis: .vertical)
                .font(.baskervilleBody)
                .foregroundColor(AquinasTheme.Colors.primaryReadable)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .focused($focused)
                .onSubmit { submitMessage() }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: uploadedFiles)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: attachedConcept?.id)
    }

    private var messagePairs: [(CanvasMessage, CanvasMessage?)] { ccPairs(thread.messages) }

    // MARK: Submit

    private func submitMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let idx = threads.firstIndex(where: { $0.id == thread.id }) else { return }
        let uploads = uploadedFiles
        let concept = attachedConcept
        inputText = ""; focused = false; uploadedFiles.removeAll(); attachedConcept = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if threads[idx].messages.isEmpty || threads[idx].title == "New Conversation" {
            let words = text
                .replacingOccurrences(of: "?", with: "")
                .split(separator: " ").prefix(5)
                .map { String($0).capitalized }
            if !words.isEmpty { threads[idx].title = words.joined(separator: " ") }
        }
        threads[idx].messages.append(
            CanvasMessage(role: .user, text: text, quotedConcept: concept, attachments: uploads))
        threads[idx].isGenerating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            guard let i = threads.firstIndex(where: { $0.id == thread.id }) else { return }
            threads[i].isGenerating = false
            threads[i].messages.append(CanvasMessage(
                role: .assistant,
                text: "Thomas Aquinas is one of the most influential figures in western thought. Often referred to as the Doctor Angelicus, he is the primary architect of [Thomism](aq://thomism). THE DIDACHE: THE TEACHING OF THE TWELVE APOSTLES — The [Didache](aq://didache) (pronounced DID-ah-kay) is essentially the first-century 'user manual' for the early Christian church. Derived from the Greek word for 'teaching,' this document was written between 50 AD and 100 AD, providing a rare look at how the earliest Christian communities organized their lives. I. THE TWO WAYS: The document opens with a moral framework called '[The Two Ways](aq://the-two-ways),' contrasting the Way of Life with the Way of Death. II. RITUAL AND LITURGY: The Didache provides the earliest 'how-to' instructions for Christian rituals including [Baptism](aq://baptism), [Fasting](aq://fasting), and the [Eucharist](aq://eucharist). III. CHURCH STRUCTURE: It outlines the qualifications for bishops and deacons and provides a guide on how to distinguish genuine [traveling prophets](aq://traveling-prophets) from those seeking personal gain. HISTORICAL IMPACT: Lost for centuries and rediscovered in 1873, the Didache serves as a vital bridge between the New Testament era and the formalized Church of later centuries."
            ))
        }
    }
}

// MARK: - Response Bubble (interactive, used in CCFocusedOverlay)

private struct CCBubble: View {
    let thread:    CanvasThread
    let msg:       CanvasMessage?
    let isLoading: Bool
    @Binding var threads: [CanvasThread]
    var onFork: (Int) -> Void = { _ in }

    @State private var isExpanded:    Bool
    @State private var actionsVisible: Bool
    @State private var thinkingText:  String = "Thinking…"

    init(thread: CanvasThread, msg: CanvasMessage?, isLoading: Bool,
         threads: Binding<[CanvasThread]>, onFork: @escaping (Int) -> Void = { _ in }) {
        self.thread    = thread
        self.msg       = msg
        self.isLoading = isLoading
        self._threads  = threads
        self.onFork    = onFork
        self._isExpanded    = State(initialValue: msg?.hasStreamed ?? false)
        self._actionsVisible = State(initialValue: msg?.hasStreamed ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(isExpanded ? "Show Thinking" : thinkingText)
                    .font(.figtreeHeading2)
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                if isExpanded {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AquinasTheme.Colors.primaryReadable)
                }
            }
            .opacity(0.5)

            if isExpanded, let m = msg {
                Text(thread.title)
                    .font(.custom("Figtree-Bold", size: 18))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)

                CCStreamingBody(
                    text: m.text,
                    shouldStream: !m.hasStreamed,
                    onFinish: {
                        guard let ti = threads.firstIndex(where: { $0.id == thread.id }),
                              let mi = threads[ti].messages.firstIndex(where: { $0.id == m.id })
                        else { return }
                        threads[ti].messages[mi].hasStreamed = true
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                            actionsVisible = true
                        }
                    }
                )

                if actionsVisible {
                    HStack(spacing: 20) {
                        Button { UIPasteboard.general.string = m.text } label: {
                            Image(systemName: "square.on.square")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AquinasTheme.Colors.responseButton)
                                .sfSymbolDrawOn()
                        }
                        .buttonStyle(.plain)

                        Button {
                            let assistantIdx = thread.messages.firstIndex(where: { $0.id == m.id }) ?? 1
                            onFork(assistantIdx / 2)
                        } label: {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AquinasTheme.Colors.responseButton)
                                .rotationEffect(.degrees(90))
                                .sfSymbolDrawOn(delay: 0.08)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.88)))
                }
            }
        }
        .padding(.horizontal, isExpanded ? 24 : 16)
        .padding(.vertical,   isExpanded ? 24 : 10)
        .frame(maxWidth: isExpanded ? .infinity : nil, alignment: .leading)
        .background(AquinasTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(AquinasTheme.Colors.border.opacity(0.5), lineWidth: 1))
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.55, dampingFraction: 0.72), value: isExpanded)
        .onAppear {
            if msg != nil && !isExpanded {
                Task {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { isExpanded = true }
                }
            }
        }
        .onChange(of: isLoading) { _, newVal in
            if !newVal {
                Task {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { isExpanded = true }
                }
            }
        }
    }
}

// MARK: - Streaming Body

/// Word-by-word streaming text renderer.
/// Uses simple Text (no FlowLayout) for clean overview rasterisation.
private struct CCStreamingBody: View {
    let text:         String
    let shouldStream: Bool
    var onFinish: (() -> Void)? = nil

    private let words: [String]
    @State private var displayedCount: Int

    init(text: String, shouldStream: Bool = true, onFinish: (() -> Void)? = nil) {
        self.text         = text
        self.shouldStream = shouldStream
        self.onFinish     = onFinish
        let w = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        self.words        = w
        _displayedCount   = State(initialValue: shouldStream ? 0 : w.count)
    }

    var body: some View {
        // Ghost copy reserves final layout height so the card doesn't resize while streaming.
        ZStack(alignment: .topLeading) {
            textView(words: words).hidden()
            textView(words: Array(words.prefix(displayedCount)))
        }
        .animation(.easeOut(duration: 0.18), value: displayedCount)
        .task { if shouldStream { await stream() } }
    }

    private func textView(words: [String]) -> some View {
        Text(words.joined(separator: " "))
            .font(.figtreeParagraphLarge)
            .foregroundColor(AquinasTheme.Colors.bodyText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineSpacing(4)
    }

    private func stream() async {
        try? await Task.sleep(nanoseconds: 400_000_000)
        while displayedCount < words.count {
            displayedCount = min(displayedCount + 4, words.count)
            try? await Task.sleep(nanoseconds: 55_000_000)
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { onFinish?() }
    }
}

// MARK: - Helpers

/// Pairs user + assistant messages into (user, assistant?) tuples.
private func ccPairs(_ messages: [CanvasMessage]) -> [(CanvasMessage, CanvasMessage?)] {
    var pairs: [(CanvasMessage, CanvasMessage?)] = []
    var i = 0
    while i < messages.count {
        let u = messages[i]
        if i + 1 < messages.count && messages[i + 1].role == .assistant {
            pairs.append((u, messages[i + 1])); i += 2
        } else {
            pairs.append((u, nil)); i += 1
        }
    }
    return pairs
}
