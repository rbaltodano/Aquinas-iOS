//
//  ConversationCanvas.swift
//  Aquinas-iOS
//
//  Free-pan world-space conversation canvas.
//  Architecture mirrors InsightTreeCanvasView exactly:
//    • worldToScreen / screenToWorld camera projection
//    • @GestureState dragOffset for lag-free panning
//    • Tap a thread card → camera springs to it at scale 1.0
//    • At scale ≥ focusThreshold the live scrollable thread fills the screen
//    • Pinch to zoom, pan freely; canvas gestures are suppressed when focused
//

import SwiftUI
import UIKit
import PhotosUI

// MARK: - Insight Link Sheet State

/// Mirrors the TriggerWord pattern from ActiveInquiry: drives `.sheet(item:)` when an aq:// link is tapped.
private struct CanvasInsightWord: Identifiable {
    let id = UUID()
    let text: String    // the raw concept word extracted from the aq:// host
}

// MARK: - Conversation Bubble (pill → card, unified)

/// Single view covering both the "thinking" loading state and the final response card.
///
/// Lifecycle:
///   isLoading = true  → pill (spinning cross + thinkingText). Appears immediately on Submit.
///   isLoading → false → onChange fires, spring expands pill into the full card in-place.
///   msg.hasStreamed    → starts fully expanded with no animation (e.g. returning to a thread).
///
/// `thinkingText` is @State so the model's reasoning stream can update it later without
/// changing the view's public signature.
private struct ConversationBubble: View {
    let thread: CanvasThread
    let msg: CanvasMessage?       // nil while loading, set when response arrives
    let isLoading: Bool
    @Binding var threads: [CanvasThread]

    @State private var isExpanded: Bool
    @State private var actionsVisible: Bool
    @State private var thinkingText: String = "Thinking..."

    init(thread: CanvasThread, msg: CanvasMessage?, isLoading: Bool, threads: Binding<[CanvasThread]>) {
        self.thread = thread
        self.msg = msg
        self.isLoading = isLoading
        self._threads = threads
        self._isExpanded = State(initialValue: msg?.hasStreamed ?? false)
        self._actionsVisible = State(initialValue: msg?.hasStreamed ?? false)
    }

    var body: some View {
        // Single unified VStack — the "Thinking / Show Thinking" row is the SAME
        // view instance throughout. isExpanded drives layout changes so SwiftUI
        // animates position (centred pill → left-aligned card) on the spring rather
        // than crossfading two separate views.
        VStack(alignment: .leading, spacing: 8) {

            // ── Thinking / Show Thinking row ─────────────────────────────────
            HStack(spacing: 4) {
                // The text is the same structural instance in both states.
                // Content flips instantly; position animates via the spring.
                Text(isExpanded ? "Show Thinking" : thinkingText)
                    .font(.figtreeHeading2)   // Figtree Bold 14pt
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)

                // Right chevron — only visible when expanded.
                if isExpanded {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AquinasTheme.Colors.primaryReadable)
                }
            }
            .opacity(0.5)
            // No frame modifier here — pill wraps its content and the parent VStack
            // (which defaults to .center alignment) centres it in the column.

            // ── Response content (card state only) ───────────────────────────
            if isExpanded, let msg = msg {
                Text(thread.title)
                    .font(.custom("Figtree-Bold", size: 18))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)

                CanvasStreamingBody(
                    text: msg.text,
                    shouldStream: !msg.hasStreamed,
                    onFinish: {
                        guard let ti = threads.firstIndex(where: { $0.id == thread.id }),
                              let mi = threads[ti].messages.firstIndex(where: { $0.id == msg.id })
                        else { return }
                        threads[ti].messages[mi].hasStreamed = true
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                            actionsVisible = true
                        }
                    }
                )

                if actionsVisible {
                    HStack(spacing: 20) {
                        // Copy button — copies the full response text to the clipboard.
                        Button(action: { UIPasteboard.general.string = msg.text }) {
                            Image(systemName: "square.on.square")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AquinasTheme.Colors.responseButton)
                                .sfSymbolDrawOn()
                        }
                        .buttonStyle(.plain)

                        // Fork button — branches the current thread into a new child thread,
                        // recording which pair index was forked so the canvas can Y-align it.
                        Button(action: {
                            let assistantIdx = thread.messages.firstIndex(where: { $0.id == msg.id }) ?? 1
                            let pairIdx = assistantIdx / 2
                            let forked = CanvasThread(
                                title: thread.title + " — Branch",
                                parentID: thread.id,
                                parentMessageIndex: pairIdx
                            )
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                threads.append(forked)
                            }
                        }) {
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
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AquinasTheme.Colors.border.opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.55, dampingFraction: 0.72), value: isExpanded)
        .onAppear {
            if msg != nil && !isExpanded {
                Task {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                        isExpanded = true
                    }
                }
            }
        }
        .onChange(of: isLoading) { _, newVal in
            if !newVal {
                Task {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                        isExpanded = true
                    }
                }
            }
        }
    }
}

// MARK: - Canvas Streaming Body

/// Word-by-word streaming text renderer sized for the canvas response card (12pt Figtree).
/// Reuses the same FlowLayout + GlideFadeModifier + .glideFadeUp transition as
/// StreamingMessageView, with identical batch (4 words / 55 ms) parameters.
private struct CanvasStreamingBody: View {
    let text: String
    let shouldStream: Bool
    var onFinish: (() -> Void)? = nil

    private let responseWords: [String]
    private let streamBatchSize = 4
    private let streamBatchDelay: UInt64 = 55_000_000   // 55 ms

    @State private var displayedWords: [String] = []
    @Environment(\.openURL) private var openURL

    init(text: String, shouldStream: Bool = true, onFinish: (() -> Void)? = nil) {
        self.text = text
        self.shouldStream = shouldStream
        self.onFinish = onFinish
        let words = Self.tokenize(text)
        self.responseWords = words
        _displayedWords = State(initialValue: shouldStream ? [] : words)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Hidden ghost reserves the final height up front.
            wordFlow(words: responseWords).hidden()
            wordFlow(words: displayedWords)
        }
        .animation(.easeOut(duration: 0.18), value: displayedWords.count)
        .task {
            if shouldStream { await streamText() }
        }
    }

    @ViewBuilder
    private func wordFlow(words: [String]) -> some View {
        FlowLayout {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                if let link = insightLink(from: word) {
                    Button(action: { openURL(link.url) }) {
                        HStack(spacing: 0) {
                            Text(link.title).underline()
                            Text(link.trailingPunctuation)
                        }
                        .font(.figtreeHeading2)
                        .foregroundColor(AquinasTheme.Colors.secondaryMuted)
                        .padding(.horizontal, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transition(.glideFadeUp)
                } else {
                    Text(word)
                        .font(.figtreeParagraphLarge)
                        .foregroundColor(AquinasTheme.Colors.bodyText)
                        .transition(.glideFadeUp)
                }
            }
        }
    }

    /// Parses a `[title](url)` token with optional trailing punctuation.
    private func insightLink(from word: String) -> (title: String, url: URL, trailingPunctuation: String)? {
        let pattern = #"^\[([^\]]+)\]\(([^)]+)\)([.,!?;:]*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: word, range: NSRange(word.startIndex..., in: word)),
              match.numberOfRanges == 4,
              let titleRange = Range(match.range(at: 1), in: word),
              let urlRange   = Range(match.range(at: 2), in: word),
              let punctRange = Range(match.range(at: 3), in: word),
              let url = URL(string: String(word[urlRange])) else { return nil }
        return (
            title: String(word[titleRange]),
            url: url,
            trailingPunctuation: String(word[punctRange])
        )
    }

    /// Tokenizes text keeping `[title](url)[punct]` blocks intact so the link
    /// parser receives the full token rather than broken fragments.
    private static func tokenize(_ text: String) -> [String] {
        let pattern = "\\[[^\\]]+\\]\\([^\\)]+\\)[.,!?;]*|\\S+"
        let regex = try! NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.map { String(text[Range($0.range, in: text)!]) }
    }

    private func streamText() async {
        try? await Task.sleep(nanoseconds: 400_000_000)
        let words = responseWords
        for batchStart in stride(from: 0, to: words.count, by: streamBatchSize) {
            let batchEnd = min(batchStart + streamBatchSize, words.count)
            displayedWords.append(contentsOf: words[batchStart..<batchEnd])
            try? await Task.sleep(nanoseconds: streamBatchDelay)
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            onFinish?()
        }
    }
}

// MARK: - Models

struct CanvasThread: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var messages: [CanvasMessage]
    var parentID: UUID?
    /// 0-based index of the message *pair* (user+assistant) in the parent thread that was forked.
    var parentMessageIndex: Int = 0
    var isGenerating: Bool = false

    init(id: UUID = UUID(), title: String = "New Conversation",
         messages: [CanvasMessage] = [], parentID: UUID? = nil,
         parentMessageIndex: Int = 0) {
        self.id = id; self.title = title
        self.messages = messages; self.parentID = parentID
        self.parentMessageIndex = parentMessageIndex
    }

    /// Approximate world-space Y for this thread's origin.
    /// Child threads are offset so their header aligns with the parent
    /// response bubble they forked from.
    var estimatedWorldY: CGFloat {
        guard parentID != nil else { return 0 }
        // These constants mirror the actual layout heights in threadContent / threadHeaderView.
        let topPad:    CGFloat = 100   // Spacer at top of threadContent
        let headerH:   CGFloat = 252   // threadHeaderView (144 internal top + cross 24 + spacing 8 + title ~60 + .padding(.bottom,16))
        let connector: CGFloat = 73    // 25px line + 24+24 vertical padding
        let question:  CGFloat = 60    // typical questionView height
        let bubble:    CGFloat = 280   // typical expanded ConversationBubble height
        let pairStep   = connector + question + connector + bubble  // ≈ 486
        // Y of the Nth pair's response bubble top edge in parent world space
        return topPad + headerH
             + CGFloat(parentMessageIndex) * pairStep
             + connector + question + connector
    }
}

struct CanvasMessage: Identifiable, Equatable, Codable {
    let id: UUID
    let role: CanvasRole
    var text: String
    var quotedConcept: ConceptDefinition?
    var attachments: [UploadedFile]
    var hasStreamed: Bool = false

    init(
        id: UUID = UUID(),
        role: CanvasRole,
        text: String,
        quotedConcept: ConceptDefinition? = nil,
        attachments: [UploadedFile] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.quotedConcept = quotedConcept
        self.attachments = attachments
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, text, quotedConcept, attachments, hasStreamed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(CanvasRole.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        quotedConcept = try container.decodeIfPresent(ConceptDefinition.self, forKey: .quotedConcept)
        attachments = try container.decodeIfPresent([UploadedFile].self, forKey: .attachments) ?? []
        hasStreamed = try container.decodeIfPresent(Bool.self, forKey: .hasStreamed) ?? false
    }
}

enum CanvasRole: Codable { case user, assistant }

// MARK: - Canvas Persistence

private enum CanvasPersistenceStore {
    static let key = "aquinas.canvas.threads.v1"

    static func load() -> [CanvasThread]? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([CanvasThread].self, from: data)
    }

    static func save(_ threads: [CanvasThread]) {
        // Strip isGenerating before saving so we never persist a mid-generation stub.
        let clean = threads.map { t -> CanvasThread in
            var c = t; c.isGenerating = false; return c
        }
        if let data = try? JSONEncoder().encode(clean) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Top-Level Shell

struct ConversationCanvasView: View {
    var onOpenMenu: () -> Void = {}
    /// Shared with the Insights page — bookmarking from the canvas populates the same list.
    @Binding var collectedDefinitions: [ConceptDefinition]
    /// Published to ContentView so the Recents / Conversations page stays current.
    @Binding var sideMenuConversations: [InquiryConversation]
    @Binding var sideMenuCurrentTitle: String
    @Binding var sideMenuActiveConversationID: UUID?
    @Binding var requestedConversationID: UUID?
    /// Increment to create a new blank thread (from "New Chat" in the side menu).
    @Binding var newConversationRequest: Int
    /// Set to a thread ID to delete it (from the "..." menu in the side menu).
    @Binding var deletedConversationID: UUID?
    @Binding var requestedForkConcept: ConceptDefinition?

    @State private var threads: [CanvasThread] = [CanvasThread()]
    @State private var focusedID: UUID? = nil
    @State private var lastFocusedID: UUID? = nil
    @State private var camScale: CGFloat = 1.0
    @State private var camOffset: CGSize = .zero
    @State private var canvasSize: CGSize = UIScreen.main.bounds.size

    // MARK: Model controls
    @State private var isThinkingEnabled: Bool = false
    @State private var selectedPersonality: String = "Friendly"
    @State private var isPersonalityMenuOpen: Bool = false
    @State private var showFilePicker: Bool = false
    @State private var showPhotoPicker: Bool = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showCamera: Bool = false
    @State private var isInsightLibraryOpen: Bool = false
    @State private var insightLibraryPopupHeight: CGFloat = 520
    @State private var uploadedFiles: [UploadedFile] = []
    @State private var attachedConcept: ConceptDefinition? = nil

    // MARK: Insight link sheet — same pattern as ActiveInquiry
    @State private var activeSheetWord: CanvasInsightWord? = nil
    @State private var dynamicDefinition: ConceptDefinition? = nil
    @State private var insightSheetContentHeight: CGFloat = 178
    /// Flipped to true by the send button in the dock; CanvasMapView observes this and fires submitMessage.
    @State private var sendTrigger: Bool = false

    var body: some View {
        GeometryReader { geo in
        ZStack {
            // ── canvas ──────────────────────────────────────────────────────
            CanvasMapView(
                threads: $threads,
                uploadedFiles: $uploadedFiles,
                attachedConcept: $attachedConcept,
                scale: $camScale,
                offset: $camOffset,
                focusedID: focusedID,
                sendTrigger: $sendTrigger,
                onFocusThread: { thread, size in
                    let nextOffset = focusOffset(for: thread, in: size)
                    withAnimation(.spring(response: 0.52, dampingFraction: 0.74)) {
                        lastFocusedID = thread.id
                        focusedID = thread.id
                        camScale = 1.0
                        camOffset = nextOffset
                    }
                },
                onUnfocus: { size in
                    let prevID = focusedID
                    withAnimation(.spring(response: 0.46, dampingFraction: 0.80)) {
                        // Don't clear focusedID here — thread stays as ScrollView while the
                        // camera springs back to overview. isFocused (scale-based) goes false
                        // once scale drops below 0.85, re-enabling canvas pan mid-animation.
                        camScale = overviewScale(in: size)
                        camOffset = overviewOffset(focusedOn: prevID, in: size)
                    }
                    // Clear after spring settles. Scale is ~0.4–0.88 by then so the
                    // ScrollView → drawingGroup swap is visually imperceptible.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
                        if focusedID == prevID { focusedID = nil }
                    }
                }
            )
            .ignoresSafeArea()

            // ── top chrome: menu (left) + mode toggle (right) ───────────────
            VStack {
                HStack {
                    chromButton(icon: "line.3.horizontal.decrease", action: onOpenMenu)
                    Spacer()
                    chromButton(icon: focusedID != nil ? "flowchart" : "viewfinder") {
                        toggleMode()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                Spacer()
            }
            .zIndex(20)

        }
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: focusedID)
        .onAppear {
            canvasSize = geo.size
            // Restore persisted threads; fall back to a blank thread on first launch.
            if let saved = CanvasPersistenceStore.load(), !saved.isEmpty {
                threads = saved
            }
            if let first = threads.first {
                focusedID = first.id
                lastFocusedID = first.id
                camOffset = focusOffset(for: first, in: geo.size)
            }
            publishShellState()
            if let concept = requestedForkConcept {
                forkInsightIntoNewThread(concept)
                requestedForkConcept = nil
            }
        }
        .onChange(of: geo.size) { _, s in
            canvasSize = s
        }
        .onChange(of: threads) { oldVal, newVal in
            CanvasPersistenceStore.save(newVal)
            publishShellState()
            // Auto-focus a newly forked thread (appended by the Fork button).
            if newVal.count > oldVal.count, let newest = newVal.last, newest.messages.isEmpty {
                withAnimation(.spring(response: 0.52, dampingFraction: 0.74)) {
                    focusedID = newest.id
                    lastFocusedID = newest.id
                    camScale = 1.0
                    camOffset = focusOffset(for: newest, in: canvasSize)
                }
            }
        }
        .onChange(of: requestedConversationID) { _, reqID in
            guard let reqID,
                  let thread = threads.first(where: { $0.id == reqID }) else { return }
            requestedConversationID = nil
            withAnimation(.spring(response: 0.52, dampingFraction: 0.74)) {
                focusedID = thread.id
                lastFocusedID = thread.id
                camScale = 1.0
                camOffset = focusOffset(for: thread, in: canvasSize)
            }
        }
        .onChange(of: newConversationRequest) { _, _ in
            // "New Chat" tapped — add a blank top-level thread and focus it.
            let fresh = CanvasThread()
            withAnimation(.spring(response: 0.52, dampingFraction: 0.74)) {
                threads.append(fresh)
                attachedConcept = nil
                focusedID = fresh.id
                lastFocusedID = fresh.id
                camScale = 1.0
                camOffset = focusOffset(for: fresh, in: canvasSize)
            }
        }
        .onChange(of: requestedForkConcept) { _, concept in
            guard let concept else { return }
            forkInsightIntoNewThread(concept)
            requestedForkConcept = nil
        }
        .onChange(of: deletedConversationID) { _, delID in
            guard let delID else { return }
            deletedConversationID = nil
            // Remove the thread and any of its forks from the canvas.
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                threads.removeAll { $0.id == delID || $0.parentID == delID }
            }
            // If we deleted the focused thread, focus the first remaining one.
            if focusedID == delID || lastFocusedID == delID {
                if let first = threads.first {
                    focusedID = first.id
                    lastFocusedID = first.id
                    camOffset = focusOffset(for: first, in: canvasSize)
                } else {
                    // Canvas is empty — add a new blank thread.
                    let fresh = CanvasThread()
                    threads.append(fresh)
                    focusedID = fresh.id
                    lastFocusedID = fresh.id
                    camOffset = focusOffset(for: fresh, in: canvasSize)
                }
            }
        }
        } // GeometryReader
        // MARK: Model Controls dock (mirrors ActiveInquiry's BranchControlBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BranchControlBar(
                showFilePicker: $showFilePicker,
                showPhotoPicker: $showPhotoPicker,
                showCamera: $showCamera,
                isThinkingEnabled: $isThinkingEnabled,
                selectedPersonality: $selectedPersonality,
                isPersonalityMenuOpen: $isPersonalityMenuOpen,
                isAtBottom: true,
                onScrollToBottom: {},
                onOpenInsights: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        isInsightLibraryOpen = true
                    }
                },
                onSend: {
                    sendTrigger.toggle()
                }
            )
            .padding(.bottom, 16)
        }
        // MARK: Insight Link — same openURL + ConceptSheetContent pattern as ActiveInquiry
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "aq", let host = url.host else { return .systemAction }
            let word = host.removingPercentEncoding ?? host
            dynamicDefinition = nil
            insightSheetContentHeight = 178
            activeSheetWord = CanvasInsightWord(text: word)
            Task { await requestDynamicDefinition(for: word) }
            return .handled
        })
        .sheet(item: $activeSheetWord) { sheetData in
            VStack(spacing: 0) {
                if let concept = dynamicDefinition {
                    ConceptSheetContent(
                        concept: concept,
                        collectedDefinitions: $collectedDefinitions,
                        onInquireFurther: {
                            quoteInsightIntoCurrentThread(concept)
                        },
                        onNewConversation: {
                            forkInsightIntoNewThread(concept)
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .onPreferenceChange(InsightSheetContentHeightKey.self) { h in
                        insightSheetContentHeight = h
                    }
                } else {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(AquinasTheme.Colors.secondaryMuted)
                            .scaleEffect(1.2)
                        Text("Generating insight for \"\(sheetData.text.capitalized)\"...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AquinasTheme.Colors.secondaryMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AquinasTheme.Colors.canvas)
                }
            }
            .frame(maxWidth: .infinity)
            .background(AquinasTheme.Colors.canvas)
            .presentationDetents([.height(dynamicDefinition == nil ? 150 : insightSheetHeight)])
            .presentationDragIndicator(.visible)
            .presentationBackground(AquinasTheme.Colors.canvas)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: dynamicDefinition != nil)
        }
        // MARK: Insight Library sheet (opened via + → Insights)
        .sheet(isPresented: $isInsightLibraryOpen) {
            InsightLibraryPopup(
                currentConversationInsights: currentConversationInsights(),
                allInsights: collectedDefinitions,
                savedInsights: $collectedDefinitions,
                onQuote: { concept in
                    quoteInsightIntoCurrentThread(concept)
                    isInsightLibraryOpen = false
                },
                onFork:  { concept in
                    forkInsightIntoNewThread(concept)
                    isInsightLibraryOpen = false
                },
                onToggleSaved: { concept in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if collectedDefinitions.contains(where: { $0.word == concept.word }) {
                            collectedDefinitions.removeAll { $0.word == concept.word }
                        } else {
                            collectedDefinitions.append(concept)
                        }
                    }
                }
            )
            .onPreferenceChange(InsightLibraryPopupHeightKey.self) { h in
                insightLibraryPopupHeight = h
            }
            .presentationDetents([.height(min(max(insightLibraryPopupHeight, 220), canvasSize.height * 0.86))])
            .presentationDragIndicator(.visible)
            .presentationBackground(AquinasTheme.Colors.canvas)
        }
        // MARK: File picker
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.image, .pdf, .audio, .plainText],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls {
                    let hasAccess = url.startAccessingSecurityScopedResource()
                    defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                    let data = try? Data(contentsOf: url)
                    let imageData = data.flatMap { UIImage(data: $0) == nil ? nil : $0 }
                    uploadedFiles.append(UploadedFile(name: url.lastPathComponent, imageData: imageData, rotationDegrees: Double.random(in: -5...5)))
                }
            }
        }
        // MARK: Photo picker
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItems, maxSelectionCount: 8, matching: .images)
        .onChange(of: selectedPhotoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self), UIImage(data: data) != nil {
                        await MainActor.run {
                            uploadedFiles.append(UploadedFile(name: "Photo", imageData: data, rotationDegrees: Double.random(in: -5...5)))
                        }
                    }
                }
                await MainActor.run { selectedPhotoItems.removeAll() }
            }
        }
        // MARK: Camera
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView { image in
                if let data = image.jpegData(compressionQuality: 0.86) {
                    uploadedFiles.append(UploadedFile(name: "Camera Photo", imageData: data, rotationDegrees: Double.random(in: -5...5)))
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Shell State

    /// Maps canvas threads → InquiryConversation so the Recents / side-menu stays current.
    /// Only top-level threads (parentID == nil) appear in Recents — forked branches are excluded.
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
        // Track the focused top-level thread as the active conversation for the side menu.
        let activeTopLevelID = threads.first(where: {
            $0.id == (focusedID ?? lastFocusedID) && $0.parentID == nil
        })?.id
        sideMenuActiveConversationID = activeTopLevelID
        sideMenuCurrentTitle = threads.first(where: { $0.id == (focusedID ?? lastFocusedID) })?.title
            ?? threads.first?.title
            ?? "New Conversation"
    }

    // MARK: Insight Helpers

    private var insightSheetHeight: CGFloat {
        min(max(insightSheetContentHeight, 178) + 24, canvasSize.height * 0.82)
    }

    private func quoteInsightIntoCurrentThread(_ concept: ConceptDefinition) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            attachedConcept = concept
            if focusedID == nil {
                let target = lastFocusedID ?? threads.first?.id
                focusedID = target
                lastFocusedID = target
                if let targetThread = target.flatMap({ id in threads.first(where: { $0.id == id }) }) {
                    camScale = 1.0
                    camOffset = focusOffset(for: targetThread, in: canvasSize)
                }
            }
        }
    }

    private func forkInsightIntoNewThread(_ concept: ConceptDefinition) {
        let parentID = focusedID ?? lastFocusedID ?? threads.first?.id
        let fresh = CanvasThread(
            title: concept.word.capitalized,
            parentID: parentID
        )

        withAnimation(.spring(response: 0.52, dampingFraction: 0.74)) {
            threads.append(fresh)
            attachedConcept = concept
            focusedID = fresh.id
            lastFocusedID = fresh.id
            camScale = 1.0
            camOffset = focusOffset(for: fresh, in: canvasSize)
        }
    }

    private func currentConversationInsights() -> [ConceptDefinition] {
        let focusedThread = threads.first { $0.id == (focusedID ?? lastFocusedID) }
        let conversationText = focusedThread?.messages.reduce("") { partial, message in
            partial + " " + message.text + " " + (message.quotedConcept?.word ?? "") + " " + (message.quotedConcept?.meaning ?? "")
        } ?? ""
        let lowercasedConversationText = conversationText.lowercased()

        return collectedDefinitions.filter { insight in
            lowercasedConversationText.contains(insight.word.lowercased())
        }
        .uniquedByWord()
    }

    @MainActor
    private func requestDynamicDefinition(for word: String) async {
        // Stub — replace with real model call when backend is connected.
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        dynamicDefinition = ConceptDefinition(
            word: word.capitalized,
            partOfSpeech: "noun",
            pronunciation: "| \(word) |",
            meaning: "This concept appears in the response as a key theological or philosophical term. A full definition will be generated by the model in the connected version of the app.",
            example: "Tap 'Inquire Further' to explore \(word.capitalized) in a new conversation."
        )
    }

    // MARK: Helpers

    /// Figma-spec chrome button — 48×48 circle, canvasSecondary bg, subtle border.
    @ViewBuilder
    private func chromButton(icon: String, action: @escaping () -> Void) -> some View {
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

    /// Toggle between canvas overview (0.80 scale) and branch mode (1.0, focused thread).
    private func toggleMode() {
        if focusedID != nil {
            // Branch → Canvas
            let prevID = focusedID
            withAnimation(.spring(response: 0.46, dampingFraction: 0.80)) {
                // Same deferred-clear pattern as onUnfocus: keep the ScrollView alive
                // while the camera springs back so there's no snap at full scale.
                camScale = overviewScale(in: canvasSize)
                camOffset = overviewOffset(focusedOn: prevID, in: canvasSize)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
                if focusedID == prevID { focusedID = nil }
            }
        } else {
            // Canvas → Branch: return to last focused thread, or first thread
            let target = lastFocusedID
                .flatMap { id in threads.first(where: { $0.id == id }) }
                ?? threads.first
            guard let thread = target else { return }
            // Set focusedID first (outside animation) so the thread pre-loads its
            // ScrollView before the camera springs in — same as the tap path.
            lastFocusedID = thread.id
            focusedID = thread.id
            withAnimation(.spring(response: 0.52, dampingFraction: 0.74)) {
                camScale = 1.0
                camOffset = focusOffset(for: thread, in: canvasSize)
            }
        }
    }

    private func focusOffset(for thread: CanvasThread, in size: CGSize) -> CGSize {
        let idx = threads.firstIndex(where: { $0.id == thread.id }) ?? 0
        return CGSize(
            width:  -CGFloat(idx) * (size.width + 88),
            height: -thread.estimatedWorldY
        )
    }

    private func overviewScale(in size: CGSize) -> CGFloat {
        guard threads.count > 1, size.width > 0 else { return 0.88 }
        let worldW = CGFloat(threads.count) * size.width + CGFloat(threads.count - 1) * 88
        return min(0.88, max(0.24, (size.width - 32) / worldW))
    }

    /// Camera offset that centers the given thread (or thread 0) on screen at overview scale.
    private func overviewOffset(focusedOn id: UUID?, in size: CGSize) -> CGSize {
        let s = overviewScale(in: size)
        let idx = id.flatMap { i in threads.firstIndex(where: { $0.id == i }) } ?? 0
        let laneStep = size.width + 88.0
        // World-space horizontal centre of this thread's lane
        let worldCx = CGFloat(idx) * laneStep + size.width / 2
        // Pan so that world centre maps to screen centre
        return CGSize(width: size.width / 2 - worldCx * s, height: 0)
    }

}

// MARK: - Canvas Map View

private struct CanvasMapView: View {

    @Binding var threads: [CanvasThread]
    @Binding var uploadedFiles: [UploadedFile]
    @Binding var attachedConcept: ConceptDefinition?
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    let focusedID: UUID?
    @Binding var sendTrigger: Bool
    let onFocusThread: (CanvasThread, CGSize) -> Void
    let onUnfocus: (CGSize) -> Void

    // Inline input state
    @State private var inputText: String = ""
    @FocusState private var inputFocused: Bool

    // Camera gesture state
    @State  private var pinchStartScale:  CGFloat?
    @State  private var pinchStartOffset: CGSize?
    @State  private var lastDragEnd:      Date = .distantPast
    @GestureState private var liveDrag:   CGSize = .zero

    // ── constants ─────────────────────────────────────────────────────────────
    private let laneSpacing: CGFloat = 88
    private let focusThreshold: CGFloat = 0.85

    // ── derived ───────────────────────────────────────────────────────────────
    private var isFocused: Bool { scale >= focusThreshold && focusedID != nil }

    private var activeOffset: CGSize {
        CGSize(width: offset.width + liveDrag.width,
               height: offset.height + liveDrag.height)
    }

    private var canAcceptTap: Bool {
        !isFocused && Date().timeIntervalSince(lastDragEnd) > 0.16
    }

    // ── camera projection (top-left coords, Y ↓) ──────────────────────────────
    private func worldToScreen(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * scale + activeOffset.width,
                y: point.y * scale + activeOffset.height)
    }

    private func screenToWorld(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: (point.x - activeOffset.width) / scale,
                y: (point.y - activeOffset.height) / scale)
    }

    // World origin for a thread: X = lane index × (width + spacing), Y = fork alignment offset.
    private func worldOrigin(for thread: CanvasThread, laneWidth: CGFloat) -> CGPoint {
        let idx = threads.firstIndex(where: { $0.id == thread.id }) ?? 0
        return CGPoint(
            x: CGFloat(idx) * (laneWidth + laneSpacing),
            y: thread.estimatedWorldY
        )
    }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            ZStack(alignment: .topLeading) {
                // Background
                AquinasTheme.Colors.canvas.ignoresSafeArea()

                // Connector lines between parent → child threads
                connectorCanvas(in: size)

                // Thread nodes
                ForEach(Array(threads.enumerated()), id: \.element.id) { index, thread in
                    threadView(thread, index: index, in: size)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(panGesture)
            .simultaneousGesture(zoomGesture(in: size))
            .simultaneousGesture(exitFocusGesture(in: size))
            // Canvas-level tap: maps tap location to world space so the correct
            // thread is focused regardless of layout-frame overlaps between lanes.
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard !isFocused && canAcceptTap else { return }
                        let worldPt = screenToWorld(value.location, in: size)
                        for thread in threads {
                            let origin = worldOrigin(for: thread, laneWidth: size.width)
                            if worldPt.x >= origin.x && worldPt.x < origin.x + size.width {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onFocusThread(thread, size)
                                return
                            }
                        }
                    }
            )
            .onChange(of: sendTrigger) { _, _ in
                guard let id = focusedID,
                      let thread = threads.first(where: { $0.id == id })
                else { return }
                submitMessage(to: thread)
            }
        }
    }

    // MARK: Thread rendering — single unified renderer
    // The camera (scale + offset) is the only thing that differs between
    // overview and focused mode. There is no separate card/preview path.

    @ViewBuilder
    private func threadView(_ thread: CanvasThread, index: Int, in size: CGSize) -> some View {
        let origin       = worldOrigin(for: thread, laneWidth: size.width)
        let screenOrigin = worldToScreen(origin, in: size)
        // Pre-load the ScrollView as soon as focusedID is set — camera is still at overview
        // scale at that moment, so drawingGroup and ScrollView look identical. The camera
        // then springs in on the live content (same as InsightTree's focusInsight path).
        let isFocusedThread = thread.id == focusedID

        Group {
            if isFocusedThread {
                // Focused: use a proper scroll viewport so the thread is scrollable.
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        threadContent(thread, isFocusedThread: true, size: size)
                    }
                    .frame(width: size.width, height: size.height)
                    .scrollDismissesKeyboard(.interactively)
                    .background(AquinasTheme.Colors.canvas)
                    .onChange(of: thread.messages.count) { _, _ in
                        guard thread.messages.last?.role == .user else { return }
                        let lastUserID = thread.messages.last?.id
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            if let id = lastUserID {
                                proxy.scrollTo("question-\(id)", anchor: .center)
                            }
                        }
                    }
                    .onChange(of: inputFocused) { _, focused in
                        guard focused else { return }
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                            proxy.scrollTo("thread-bottom-\(thread.id)", anchor: .bottom)
                        }
                    }
                    .onChange(of: uploadedFiles.count) { _, count in
                        guard count > 0 else { return }
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                            proxy.scrollTo("input-anchor-\(thread.id)", anchor: .center)
                        }
                    }
                    .onChange(of: attachedConcept?.id) { _, conceptID in
                        guard conceptID != nil else { return }
                        inputFocused = true
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                            proxy.scrollTo("input-anchor-\(thread.id)", anchor: .center)
                        }
                    }
                }
            } else {
                // Overview: plain layout, no ScrollView, content is never clipped.
                // .drawingGroup() rasterises the subtree to a Metal texture so touch events
                // can be processed at full 120Hz — the position update is a CALayer transform,
                // same as the momentum path, instead of a full SwiftUI diff on every event.
                threadContent(thread, isFocusedThread: false, size: size)
                    .frame(width: size.width)
                    .background(AquinasTheme.Colors.canvas)
                    .drawingGroup()
                    .allowsHitTesting(false)
            }
        }
        .scaleEffect(scale, anchor: .topLeading)
        .offset(x: screenOrigin.x, y: screenOrigin.y)
        .zIndex(isFocusedThread ? 100 : Double(index + 1))
    }

    @ViewBuilder
    private func threadContent(_ thread: CanvasThread, isFocusedThread: Bool, size: CGSize) -> some View {
        // The post-response connector + input only appear once the last assistant
        // message has finished word-by-word streaming (hasStreamed flips true).
        let lastAssistantStreamed = thread.messages.last(where: { $0.role == .assistant })?.hasStreamed ?? true

        VStack(spacing: 0) {
            Spacer().frame(height: 100)   // chrome clearance

            threadHeaderView(thread)
                .padding(.bottom, 16)

            if thread.messages.isEmpty {
                // In overview mode don't render the input — TextField breaks drawingGroup()
                // and there's nothing to show anyway. Focused mode gets the full input.
                if isFocusedThread {
                    connectorLine
                    inlineInput(for: thread, enabled: true)
                        .id("input-anchor-\(thread.id)")
                }
            } else {
                ForEach(messagePairs(from: thread.messages), id: \.0.id) { (userMsg, assistantMsg) in
                    connectorLine
                    questionView(userMsg)
                        .id("question-\(userMsg.id)")
                    connectorLine
                    ConversationBubble(
                        thread: thread,
                        msg: assistantMsg,
                        isLoading: assistantMsg == nil,
                        threads: $threads
                    )
                    .id("bubble-\(userMsg.id)")
                }
                // Connector line + input only in focused mode (TextField breaks drawingGroup).
                if isFocusedThread && !thread.isGenerating && lastAssistantStreamed {
                    connectorLine
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .top)))
                    inlineInput(for: thread, enabled: true)
                        .id("input-anchor-\(thread.id)")
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Spacer().frame(height: size.height * 0.75)
                .id("thread-bottom-\(thread.id)")
        }
        .animation(.spring(response: 0.52, dampingFraction: 0.72), value: thread.isGenerating)
        .animation(.spring(response: 0.55, dampingFraction: 0.78), value: lastAssistantStreamed)
    }

    // MARK: Figma-spec sub-views

    private var connectorLine: some View {
        Rectangle()
            .fill(AquinasTheme.Colors.border)
            .frame(width: 1, height: 25)
            .padding(.vertical, 24)
    }

    private func inlineInput(for thread: CanvasThread, enabled: Bool) -> some View {
        VStack(spacing: 16) {
            UploadedFileStrip(files: enabled ? uploadedFiles : []) { file in
                uploadedFiles.removeAll { $0.id == file.id }
            }

            if enabled, let concept = attachedConcept {
                BranchContextChip(
                    title: concept.word.capitalized,
                    icon: "text.bubble",
                    isFilled: false,
                    showRemove: true,
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
                .focused($inputFocused)
                .disabled(!enabled)
                .onSubmit { submitMessage(to: thread) }
        }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: uploadedFiles)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: attachedConcept?.id)
    }

    private func submitMessage(to thread: CanvasThread) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let idx = threads.firstIndex(where: { $0.id == thread.id }) else { return }
        let submittedUploads = uploadedFiles
        let quotedConcept = attachedConcept
        inputText = ""
        inputFocused = false
        uploadedFiles.removeAll()
        attachedConcept = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Auto-title the thread from the first question (mirrors ChatThreadColumn behaviour).
        if threads[idx].messages.isEmpty || threads[idx].title == "New Conversation" {
            let words = text
                .replacingOccurrences(of: "?", with: "")
                .split(separator: " ").prefix(5)
                .map { String($0).capitalized }
            if !words.isEmpty {
                threads[idx].title = words.joined(separator: " ")
            }
        }
        threads[idx].messages.append(
            CanvasMessage(
                role: .user,
                text: text,
                quotedConcept: quotedConcept,
                attachments: submittedUploads
            )
        )
        threads[idx].isGenerating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            guard let i = threads.firstIndex(where: { $0.id == thread.id }) else { return }
            threads[i].isGenerating = false
            threads[i].messages.append(
                CanvasMessage(role: .assistant,
                              text: "Thomas Aquinas is one of the most influential figures in western thought. Often referred to as the Doctor Angelicus, he is the primary architect of [Thomism](aq://thomism) THE DIDACHE: THE TEACHING OF THE TWELVE APOSTLES The [Didache](aq://didache) (pronounced DID-ah-kay) is essentially the first-century 'user manual' for the early Christian church. Derived from the Greek word for 'teaching,' this document was written between 50 AD and 100 AD, providing a rare look at how the earliest Christian communities organized their lives. I. THE TWO WAYS The document opens with a moral framework called '[The Two Ways](aq://the-two-ways),' contrasting the Way of Life with the Way of Death. It outlines a strict ethical code, covering everything from communal love to specific social prohibitions. II. RITUAL AND LITURGY The Didache provides the earliest 'how-to' instructions for Christian rituals: • [Baptism](aq://baptism): Prefers 'living' (running) water, but allows for pouring if necessary. • [Fasting](aq://fasting): Suggests specific days of the week (Wednesdays and Fridays). • THE [Eucharist](aq://eucharist): Contains some of the oldest recorded prayers for communion. III. CHURCH STRUCTURE It outlines the qualifications for bishops and deacons and provides a fascinating guide on how to distinguish between genuine [traveling prophets](aq://traveling-prophets) and those seeking personal gain. HISTORICAL IMPACT Lost for centuries and rediscovered in 1873, the Didache serves as a vital bridge between the New Testament era and the formalized Church of later centuries."))
        }
    }

    private func threadHeaderView(_ thread: CanvasThread) -> some View {
        VStack(spacing: 8) {
            Image("cross-1")
                .renderingMode(.template)
                .resizable().scaledToFit()
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

            if let concept = msg.quotedConcept {
                BranchContextChip(
                    title: concept.word.capitalized,
                    icon: "text.bubble.fill",
                    isFilled: true,
                    showRemove: false
                )
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

    private func messagePairs(from messages: [CanvasMessage]) -> [(CanvasMessage, CanvasMessage?)] {
        var pairs: [(CanvasMessage, CanvasMessage?)] = []
        var i = 0
        while i < messages.count {
            let user = messages[i]
            if i + 1 < messages.count && messages[i + 1].role == .assistant {
                pairs.append((user, messages[i + 1])); i += 2
            } else {
                pairs.append((user, nil)); i += 1
            }
        }
        return pairs
    }

    // MARK: Connector lines (canvas → parent relation)

    private func connectorCanvas(in size: CGSize) -> some View {
        Canvas { ctx, _ in
            guard !isFocused else { return }

            for child in threads {
                guard let parentID = child.parentID,
                      let parent = threads.first(where: { $0.id == parentID })
                else { continue }

                // Project using settled offset only — liveDrag is applied as a .offset()
                // transform on the whole view below, so connectors move in sync with the
                // drawingGroup thread textures instead of redrawing on every gesture event.
                func settledScreen(_ point: CGPoint) -> CGPoint {
                    CGPoint(x: point.x * scale + offset.width,
                            y: point.y * scale + offset.height)
                }

                let childOrigin  = settledScreen(worldOrigin(for: child,  laneWidth: size.width))
                let parentOrigin = settledScreen(worldOrigin(for: parent, laneWidth: size.width))

                let lineY = childOrigin.y
                var path = Path()
                path.move(to:    CGPoint(x: parentOrigin.x + size.width * scale, y: lineY))
                path.addLine(to: CGPoint(x: childOrigin.x, y: lineY))
                ctx.stroke(path, with: .color(AquinasTheme.Colors.border),
                           style: StrokeStyle(lineWidth: max(1.5, scale * 1.5), lineCap: .round))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(x: liveDrag.width, y: liveDrag.height)  // GPU transform — mirrors thread view movement
        .allowsHitTesting(false)
    }

    // MARK: Gestures

    /// Canvas pan — suppressed while focused so the inner ScrollView owns vertical drag.
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($liveDrag) { value, state, _ in
                guard !isFocused else { return }
                state = value.translation
            }
            .onEnded { value in
                guard !isFocused else { return }
                offset.width  += value.translation.width
                offset.height += value.translation.height
                if hypot(value.translation.width, value.translation.height) > 8 {
                    lastDragEnd = Date()
                }
                // Momentum: project the offset forward by a fraction of the release velocity
                // so the canvas coasts to a stop rather than cutting off abruptly.
                let decay: CGFloat = 0.18
                let momentum = CGSize(
                    width:  value.velocity.width  * decay,
                    height: value.velocity.height * decay
                )
                withAnimation(.spring(response: 0.68, dampingFraction: 0.86)) {
                    offset.width  += momentum.width
                    offset.height += momentum.height
                }
            }
    }

    /// Horizontal swipe anywhere exits focus mode and returns to the canvas.
    private func exitFocusGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard isFocused else { return }
                let isHoriz = abs(value.translation.width) > abs(value.translation.height) * 1.5
                guard isHoriz && abs(value.translation.width) > 56 else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                inputFocused = false
                onUnfocus(size)
            }
    }

    /// Pinch to zoom — always active so the user can pinch out from a focused branch.
    private func zoomGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                if pinchStartScale == nil {
                    pinchStartScale = scale; pinchStartOffset = offset
                }
                applyZoom(value.magnification, anchor: value.startAnchor, in: size)
            }
            .onEnded { value in
                applyZoom(value.magnification, anchor: value.startAnchor, in: size)

                // If the user pinched way out, treat it as intent to exit focus
                if isFocused && scale < focusThreshold - 0.05 {
                    inputFocused = false
                    onUnfocus(size)
                }

                pinchStartScale = nil; pinchStartOffset = nil
            }
    }

    private func applyZoom(_ mag: CGFloat, anchor: UnitPoint, in size: CGSize) {
        let initS = pinchStartScale  ?? scale
        let initO = pinchStartOffset ?? offset
        let next  = clampedScale(initS * pow(mag, 0.72), in: size)
        let pt    = CGPoint(x: anchor.x * size.width, y: anchor.y * size.height)

        // Keep the anchor point fixed on screen
        let wx = (pt.x - initO.width)  / initS
        let wy = (pt.y - initO.height) / initS

        scale  = next
        offset = CGSize(width: pt.x - wx * next, height: pt.y - wy * next)
    }

    private func clampedScale(_ s: CGFloat, in size: CGSize) -> CGFloat {
        let minS: CGFloat = threads.count > 1
            ? max(0.20, (size.width - 32) / (CGFloat(threads.count) * (size.width + laneSpacing)))
            : 0.30
        return min(1.0, max(minS, s))
    }

}
