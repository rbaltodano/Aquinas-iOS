//
//  StreamingMessageView.swift
//  Aquinas-iOS
//
//  Created by Ryan on 4/21/26.
//

import Foundation
import SwiftUI

// MARK: - Streaming Text Helpers

/// Lightweight entrance effect for streamed words.
struct GlideFadeModifier: ViewModifier {
    let isActive: Bool
    func body(content: Content) -> some View {
        content
            .blur(radius: isActive ? 3 : 0)
            .opacity(isActive ? 0 : 1)
            .offset(y: isActive ? 14 : 0)
            .scaleEffect(isActive ? 0.95 : 1)
    }
}

/// Compatibility name for older response-card code.
typealias BlurFadeModifier = GlideFadeModifier

/// Simple wrapping layout for streamed words and inline insight links.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4.5
    var alignment: TextAlignment = .center

    // MARK: - Cache
    //
    // SwiftUI calls sizeThatFits + placeSubviews on every layout pass, and both
    // previously recreated a full FlowResult — measuring every word from scratch
    // each time. For a 500-word response streaming 4 words every 55 ms that
    // amounted to ~188,000 CoreText sizeThatFits calls before the stream finished.
    //
    // The fix: use SwiftUI's built-in Layout cache to remember completed words by
    // subview index. The trailing token is deliberately remeasured because a
    // network chunk can still be extending it in place.
    //
    // Expected reduction: ~188,000 → ~1,000 total measurements for a 500-word stream.

    struct Cache {
        var sizes: [Int: CGSize] = [:]
        var subviewCount = 0
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(subviewCount: subviews.count)
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        // A network chunk can extend the current trailing token without adding
        // another subview ("res" -> "response"). Its index is unchanged, but its
        // measured width is not. Invalidate the previous trailing token whenever
        // SwiftUI updates the subviews so streamed glyphs never get placed inside
        // a stale, narrower measurement.
        let firstMutableIndex = max(
            0,
            min(cache.subviewCount, subviews.count) - 1
        )
        cache.sizes = cache.sizes.filter {
            $0.key < firstMutableIndex && $0.key < subviews.count
        }
        cache.subviewCount = subviews.count
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing, alignment: alignment, cache: &cache).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing, alignment: alignment, cache: &cache)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + result.points[index].x,
                            y: bounds.minY + result.points[index].y),
                proposal: .unspecified
            )
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var points: [CGPoint] = []

        init(
            in maxWidth: CGFloat,
            subviews: Subviews,
            spacing: CGFloat,
            alignment: TextAlignment,
            cache: inout Cache
        ) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            // Track each row's subview range and packed width so we can center
            // every row horizontally once the full row is known.
            var rowRanges: [(range: Range<Int>, width: CGFloat)] = []
            var rowStart = 0

            for (idx, subview) in subviews.enumerated() {
                let wordSize: CGSize
                let isTrailingToken = idx == subviews.count - 1
                if !isTrailingToken, let hit = cache.sizes[idx] {
                    wordSize = hit
                } else {
                    wordSize = subview.sizeThatFits(.unspecified)
                    if !isTrailingToken {
                        cache.sizes[idx] = wordSize
                    }
                }

                if currentX + wordSize.width > maxWidth && currentX > 0 {
                    // Close the row that just ended (drop the trailing spacing).
                    rowRanges.append((rowStart..<idx, max(0, currentX - spacing)))
                    rowStart = idx
                    currentX = 0
                    currentY += lineHeight + 8
                    lineHeight = 0
                }
                points.append(CGPoint(x: currentX, y: currentY))
                lineHeight = max(lineHeight, wordSize.height)
                currentX += wordSize.width + spacing
            }
            // Close the final row.
            rowRanges.append((rowStart..<subviews.count, max(0, currentX - spacing)))

            // Position each completed row using the user's response alignment.
            for (range, width) in rowRanges {
                let offset: CGFloat
                switch alignment {
                case .center:
                    offset = max(0, (maxWidth - width) / 2)
                default:
                    offset = 0
                }
                for i in range {
                    points[i].x += offset
                }
            }

            size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

// Shared transition shorthand.
extension AnyTransition {
    static var streamedTextFade: AnyTransition {
        .opacity.animation(.easeInOut(duration: 0.55))
    }

    static var glideFadeUp: AnyTransition {
        .modifier(active: GlideFadeModifier(isActive: true), identity: GlideFadeModifier(isActive: false))
        .animation(.easeOut(duration: 0.22))
    }

    static var blurSlideUp: AnyTransition {
        glideFadeUp
    }

    static var blurredTitleReplacement: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: GlideFadeModifier(isActive: true),
                identity: GlideFadeModifier(isActive: false)
            )
            .animation(.easeOut(duration: 0.5)),
            removal: .modifier(
                active: GlideFadeModifier(isActive: true),
                identity: GlideFadeModifier(isActive: false)
            )
            .animation(.easeInOut(duration: 0.5))
        )
    }
}

// MARK: - Cached Regex

/// Compiled once per process — never inside init or hot-path functions.
private enum CachedRegex {
    static let listLine    = try! NSRegularExpression(pattern: #"^\s*\d+[.)]\s+(.+)"#)
    static let insightLink = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#)
    static let tokenizer   = try! NSRegularExpression(pattern: #"\S*\[[^\]]+\]\([^)]+\)\S*|\*\*[^*]+\*\*[.,!?;:]*|\*[^*]+\*[.,!?;:]*|\S+"#)
}

/// A tappable Insight link plus any punctuation or Markdown emphasis wrapped around it.
/// The model can emit `*term*` or `(term)` before annotation inserts the aq:// link,
/// yielding tokens such as `(*[term](aq://term)*)`.
private struct ParsedInsightLink {
    let leadingPunctuation: String
    let title: String
    let url: URL
    let trailingPunctuation: String

    init?(token: String) {
        guard let match = CachedRegex.insightLink.firstMatch(
            in: token,
            range: NSRange(token.startIndex..., in: token)
        ),
        match.numberOfRanges == 3,
        let fullRange = Range(match.range(at: 0), in: token),
        let titleRange = Range(match.range(at: 1), in: token),
        let urlRange = Range(match.range(at: 2), in: token),
        let parsedURL = URL(string: String(token[urlRange])) else {
            return nil
        }

        leadingPunctuation = Self.removingEmphasis(
            from: String(token[..<fullRange.lowerBound])
        )
        title = String(token[titleRange])
        url = parsedURL
        trailingPunctuation = Self.removingEmphasis(
            from: String(token[fullRange.upperBound...])
        )
    }

    private static func removingEmphasis(from text: String) -> String {
        String(text.filter { $0 != "*" })
    }
}

// MARK: - Response Segment Model

/// A parsed block of text — either a normal paragraph or a numbered list.
private struct ResponseSegment: Identifiable {
    enum Kind {
        case paragraph
        case heading(level: Int)
        case orderedList([String])  // item texts, already stripped of "1." prefix
    }

    /// Stable for the lifetime of a response because generated blocks append in order.
    let id: Int
    let kind: Kind
    /// Flat word array for this segment (drives streaming progress).
    let words: [String]
    /// Where this segment starts in the global flat word array.
    let wordStart: Int
    /// For orderedList: word index (relative to segment start) where each item begins.
    let itemWordOffsets: [Int]

    var wordCount: Int { words.count }
}

// MARK: - Streaming Message View

/// Renders the model response body, animated word-by-word, with ordered-list bubble formatting
/// and bookmark/copy/fork actions.
struct StreamingMessageView: View {
    let fullText: String
    let shouldStream: Bool
    let isReceivingStream: Bool
    let usesNetworkStream: Bool
    let responseTextAlignment: ResponseTextAlignmentOption
    let responseFont: ConversationFontOption
    let conversationFontSize: ConversationFontSizeOption
    let loadingInsightKey: String?
    let queuedInsightKeys: Set<String>
    var onQuote: ((String) -> Void)? = nil
    var onBranch: (() -> Void)? = nil
    var onInsightTap: ((String, String) -> Void)? = nil
    var onFinish: (() -> Void)? = nil

    private let segments: [ResponseSegment]
    private let responseWords: [String]
    private let insightLinkSequenceByWordStart: [Int: Int]
    private let streamBatchSize = 4
    private let streamBatchDelay: UInt64 = 55_000_000

    // Process-level cache keyed by response text. parseSegments + tokenize is
    // O(words) and called every time a parent view re-renders (SwiftUI creates new
    // struct values for comparison). Caching makes repeated inits a O(1) lookup.
    private static var parseCache: [
        String: (
            segments: [ResponseSegment],
            words: [String],
            insightLinkSequenceByWordStart: [Int: Int]
        )
    ] = [:]

    @State private var displayedWords: [String] = []
    @State private var isFinished: Bool = false
    @State private var hasReportedFinish = false
    @State private var showsInsightUnderlines: Bool
    @Environment(\.openURL) private var openURL

    init(
        fullText: String,
        shouldStream: Bool = true,
        isReceivingStream: Bool = false,
        usesNetworkStream: Bool = false,
        responseTextAlignment: ResponseTextAlignmentOption = .center,
        responseFont: ConversationFontOption = .sans,
        conversationFontSize: ConversationFontSizeOption = .large,
        loadingInsightKey: String? = nil,
        queuedInsightKeys: Set<String> = [],
        onQuote: ((String) -> Void)? = nil,
        onBranch: (() -> Void)? = nil,
        onInsightTap: ((String, String) -> Void)? = nil,
        onFinish: (() -> Void)? = nil
    ) {
        self.fullText = fullText
        self.shouldStream = shouldStream
        self.isReceivingStream = isReceivingStream
        self.usesNetworkStream = usesNetworkStream
        self.responseTextAlignment = responseTextAlignment
        self.responseFont = responseFont
        self.conversationFontSize = conversationFontSize
        self.loadingInsightKey = loadingInsightKey
        self.queuedInsightKeys = queuedInsightKeys
        self.onQuote = onQuote
        self.onBranch = onBranch
        self.onInsightTap = onInsightTap
        self.onFinish = onFinish

        let cached: (
            segments: [ResponseSegment],
            words: [String],
            insightLinkSequenceByWordStart: [Int: Int]
        )
        if isReceivingStream {
            // A network stream changes `fullText` frequently. Parsing and caching every
            // intermediate prefix makes rendering quadratic and retains hundreds of
            // one-off cache entries. The persistent network renderer parses prefixes
            // without adding them to this completed-response cache.
            cached = (segments: [], words: [], insightLinkSequenceByWordStart: [:])
        } else if let hit = Self.parseCache[fullText] {
            cached = hit
        } else {
            let segs = Self.parseSegments(from: fullText)
            let words = segs.flatMap { $0.words }
            cached = (
                segments: segs,
                words: words,
                insightLinkSequenceByWordStart: Self.insightLinkSequenceByWordStart(in: segs)
            )
            Self.parseCache[fullText] = cached
        }
        self.segments = cached.segments
        self.responseWords = cached.words
        self.insightLinkSequenceByWordStart = cached.insightLinkSequenceByWordStart
        _displayedWords = State(
            initialValue: shouldStream && !usesNetworkStream ? [] : cached.words
        )
        _isFinished = State(
            initialValue: usesNetworkStream ? !isReceivingStream : !shouldStream
        )
        _showsInsightUnderlines = State(
            initialValue: !shouldStream || usesNetworkStream
        )
    }

    var body: some View {
        Group {
            if usesNetworkStream {
                networkResponse
            } else {
                completedResponse
            }
        }
        .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
        .task(id: usesNetworkStream ? "network-stream" : fullText) {
            if usesNetworkStream, !isReceivingStream {
                finishNetworkResponse()
            } else if shouldStream && !usesNetworkStream {
                await streamText()
            }
        }
        .onChange(of: isReceivingStream) { wasReceiving, isReceiving in
            guard wasReceiving, !isReceiving else { return }
            finishNetworkResponse()
        }
    }

    private var networkResponse: some View {
        VStack(alignment: responseTextAlignment.horizontalAlignment, spacing: 12) {
            LiveFormattedResponseView(
                text: fullText,
                responseTextAlignment: responseTextAlignment,
                responseFont: responseFont,
                conversationFontSize: conversationFontSize,
                loadingInsightKey: loadingInsightKey,
                queuedInsightKeys: queuedInsightKeys,
                onInsightTap: onInsightTap
            )

            if isFinished {
                responseButtons
            }
        }
    }

    private var completedResponse: some View {
        VStack(alignment: responseTextAlignment.horizontalAlignment, spacing: 12) {

            // Reserve the final response height up front so the card doesn't jump,
            // then reveal content on top of the ghost via streaming progress.
            ZStack(alignment: .top) {
                segmentsView(displayedCount: responseWords.count)
                    .hidden()

                segmentsView(
                    displayedCount: usesNetworkStream
                        ? responseWords.count
                        : displayedWords.count
                )
                    .textSelection(.enabled)   // let the user highlight / copy the response text
            }
            .animation(
                usesNetworkStream ? nil : .easeOut(duration: 0.55),
                value: usesNetworkStream ? responseWords.count : displayedWords.count
            )

            if isFinished {
                responseButtons
            }
        }
    }

    private var responseButtons: some View {
        ResponseButtons(
            canCopy: true,
            canFork: onBranch != nil,
            copyText: fullText,
            onSave: { print("Saved to bookmarks!") },
            onQuote: onQuote.map { q in { q(fullText) } },
            onFork: onBranch
        )
        .padding(.top, 8)
        .transition(
            .move(edge: .top)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.95))
        )
    }

    private func finishNetworkResponse() {
        displayedWords = responseWords
        isFinished = true
        guard !hasReportedFinish else { return }
        hasReportedFinish = true
        onFinish?()
    }

    // MARK: - Segment renderer

    @ViewBuilder
    private func segmentsView(displayedCount: Int) -> some View {
        VStack(alignment: responseTextAlignment.horizontalAlignment, spacing: 16) {
            ForEach(segments) { segment in
                segmentView(segment: segment, displayedCount: displayedCount)
            }
        }
    }

    @ViewBuilder
    private func segmentView(segment: ResponseSegment, displayedCount: Int) -> some View {
        let available = max(0, min(segment.wordCount, displayedCount - segment.wordStart))
        if available > 0 {
            switch segment.kind {
            case .paragraph:
                // Lay out the FULL paragraph so word positions are final from the
                // start; reveal up to `available` via opacity instead of inserting
                // words (which would re-center each row and slide text sideways).
                wordFlow(
                    words: segment.words,
                    visibleCount: available,
                    globalWordStart: segment.wordStart
                )

            case .heading(let level):
                headingFlow(words: segment.words, visibleCount: available, level: level)

            case .orderedList(let items):
                orderedListBubble(
                    items: items,
                    allWords: segment.words,
                    segmentWordStart: segment.wordStart,
                    itemOffsets: segment.itemWordOffsets,
                    available: available
                )
            }
        }
    }

    @ViewBuilder
    private func headingFlow(words: [String], visibleCount: Int, level: Int) -> some View {
        FlowLayout(spacing: 5, alignment: responseTextAlignment.textAlignment) {
            ForEach(Array(words.enumerated()), id: \.offset) { idx, word in
                styledText(for: word, baseFont: headingFont(for: level), allowsInlineMarkdown: false)
                    .foregroundColor(AquinasTheme.Colors.headingText)
                    .opacity(idx < visibleCount ? 1 : 0)
                    .offset(y: idx < visibleCount ? 0 : 10)
                    .blur(radius: idx < visibleCount ? 0 : 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .custom("LibreBaskerville-Regular", size: conversationFontSize.pointSize + 8)
        case 2:
            return .custom("LibreBaskerville-Regular", size: conversationFontSize.pointSize + 4)
        default:
            return .custom("Figtree-Bold", size: conversationFontSize.pointSize + 1)
        }
    }

    // MARK: - Ordered list bubble

    @ViewBuilder
    private func orderedListBubble(
        items: [String],
        allWords: [String],
        segmentWordStart: Int,
        itemOffsets: [Int],
        available: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, _ in
                let itemStart = itemOffsets[index]
                let itemEnd   = index + 1 < itemOffsets.count ? itemOffsets[index + 1] : allWords.count
                let itemWords = Array(allWords[itemStart..<itemEnd])

                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1).")
                        .font(responseFont.textFont(size: conversationFontSize))
                        .foregroundColor(AquinasTheme.Colors.bodyText)
                        .frame(minWidth: 22, alignment: .trailing)
                        .opacity(available > itemStart ? 1 : 0)

                    // Full item is laid out immediately; words reveal in place.
                    wordFlow(
                        words: itemWords,
                        visibleCount: max(0, available - itemStart),
                        globalWordStart: segmentWordStart + itemStart
                    )
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(AquinasTheme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AquinasTheme.Colors.quietBorder, lineWidth: 1)
        )
    }

    // MARK: - Word flow (unchanged)

    @ViewBuilder
    private func wordFlow(
        words: [String],
        visibleCount: Int,
        globalWordStart: Int
    ) -> some View {
        FlowLayout(alignment: responseTextAlignment.textAlignment) {
            ForEach(Array(words.enumerated()), id: \.offset) { idx, word in
                let globalWordIndex = globalWordStart + idx
                let underlineDelay = insightLinkSequenceByWordStart[globalWordIndex]
                    .map { Double($0) * 0.1 } ?? 0
                styledWord(
                    word,
                    isVisible: idx < visibleCount && showsInsightUnderlines,
                    underlineDelay: underlineDelay
                )
                // All words are laid out up front, so positions are final; reveal
                // each word with a slow fade + upward drift. The offset is purely
                // visual (doesn't affect layout), so positions never shift.
                .opacity(idx < visibleCount ? 1 : 0)
                .offset(y: idx < visibleCount ? 0 : 10)
                .blur(radius: idx < visibleCount ? 0 : 3)
            }
        }
    }

    @ViewBuilder
    private func styledWord(
        _ word: String,
        isVisible: Bool,
        underlineDelay: Double
    ) -> some View {
        if let link = Self.insightLink(from: word) {
            let isLoading = loadingInsightKey == insightLoadingKey(
                for: link.title,
                sourceResponseBlock: fullText
            )
            let isQueued = queuedInsightKeys.contains(
                insightLoadingKey(
                    for: link.title,
                    sourceResponseBlock: fullText
                )
            )
            Button(action: {
                if let onInsightTap {
                    onInsightTap(link.title, fullText)
                } else {
                    openURL(link.url)
                }
            }) {
                insightLinkLabel(
                    link: link,
                    isLoading: isLoading,
                    isQueued: isQueued,
                    isVisible: isVisible,
                    underlineDelay: underlineDelay
                )
            }
            .buttonStyle(.plain)
            .disabled(isLoading || isQueued)
        } else {
            styledText(
                for: word,
                baseFont: responseFont.textFont(size: conversationFontSize),
                allowsInlineMarkdown: true
            )
            .foregroundColor(AquinasTheme.Colors.bodyText)
        }
    }

    @ViewBuilder
    private func insightLinkLabel(
        link: ParsedInsightLink,
        isLoading: Bool,
        isQueued: Bool,
        isVisible: Bool,
        underlineDelay: Double
    ) -> some View {
        if isLoading {
            let label = HStack(spacing: 0) {
                Text(link.leadingPunctuation)
                Text(link.title).bold()
                Text(link.trailingPunctuation)
            }
            .font(responseFont.textFont(size: conversationFontSize))
            .padding(.horizontal, 2)
            .contentShape(Rectangle())

            label.modifier(
                ThinkingShimmer(
                    isActive: true,
                    color: AquinasTheme.Colors.lightGreen
                )
            )
        } else {
            HStack(spacing: 0) {
                Text(link.leadingPunctuation)
                    .font(responseFont.textFont(size: conversationFontSize))
                    .foregroundColor(AquinasTheme.Colors.secondaryMuted)
                AnimatedInsightUnderlineText(
                    text: link.title,
                    font: responseFont.textFont(size: conversationFontSize),
                    color: AquinasTheme.Colors.secondaryMuted,
                    isVisible: isVisible,
                    animationDelay: underlineDelay,
                    underlineOpacity: 1
                )
                .modifier(
                    QueuedWorkBreatheModifier(
                        isQueued: isQueued
                    )
                )
                Text(link.trailingPunctuation)
                    .font(responseFont.textFont(size: conversationFontSize))
                    .foregroundColor(AquinasTheme.Colors.secondaryMuted)
            }
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
    }

    private func insightLoadingKey(for text: String, sourceResponseBlock: String?) -> String {
        "\(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())\n\(sourceResponseBlock ?? "")"
    }

    private func styledText(
        for token: String,
        baseFont: Font,
        allowsInlineMarkdown: Bool
    ) -> Text {
        guard allowsInlineMarkdown,
              let markdown = inlineMarkdown(from: token) else {
            return Text(token).font(baseFont)
        }

        var text = Text(markdown.text).font(baseFont)
        if markdown.isBold { text = text.bold() }
        if markdown.isItalic { text = text.italic() }
        if !markdown.trailingPunctuation.isEmpty {
            text = text + Text(markdown.trailingPunctuation).font(baseFont)
        }
        return text
    }

    private func inlineMarkdown(from token: String) -> (text: String, trailingPunctuation: String, isBold: Bool, isItalic: Bool)? {
        let punctuation = token.reversed().prefix { ".,!?;:".contains($0) }
        let trailing = String(punctuation.reversed())
        let core = String(token.dropLast(trailing.count))
        if core.hasPrefix("**"), core.hasSuffix("**"), core.count > 4 {
            return (String(core.dropFirst(2).dropLast(2)), trailing, true, false)
        }
        if core.hasPrefix("*"), core.hasSuffix("*"), core.count > 2 {
            return (String(core.dropFirst().dropLast()), trailing, false, true)
        }
        return nil
    }

    // MARK: - Parsing

    /// Splits fullText into paragraph and ordered-list segments.
    /// Consecutive lines matching `^\d+[.)]\s+` form one orderedList segment.
    private static func parseSegments(from text: String) -> [ResponseSegment] {
        // Matches "1. ", "2) ", "10. " etc. and captures the item text.
        let listLineRegex = CachedRegex.listLine

        struct RawLine {
            let isListItem: Bool
            let headingLevel: Int?
            let content: String
        }

        var rawLines: [RawLine] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if let match = listLineRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let itemRange = Range(match.range(at: 1), in: trimmed) {
                rawLines.append(RawLine(isListItem: true, headingLevel: nil, content: String(trimmed[itemRange])))
            } else if let heading = markdownHeading(from: trimmed) {
                rawLines.append(RawLine(isListItem: false, headingLevel: heading.level, content: heading.text))
            } else {
                rawLines.append(RawLine(isListItem: false, headingLevel: nil, content: trimmed))
            }
        }

        var result: [ResponseSegment] = []
        var wordCursor = 0
        var i = 0

        while i < rawLines.count {
            if rawLines[i].isListItem {
                // Gather all consecutive list items into one segment.
                var items: [String] = []
                while i < rawLines.count && rawLines[i].isListItem {
                    items.append(rawLines[i].content)
                    i += 1
                }
                var allWords: [String] = []
                var itemOffsets: [Int] = []
                for item in items {
                    itemOffsets.append(allWords.count)
                    allWords.append(contentsOf: tokenize(item))
                }
                result.append(ResponseSegment(
                    id: result.count,
                    kind: .orderedList(items),
                    words: allWords,
                    wordStart: wordCursor,
                    itemWordOffsets: itemOffsets
                ))
                wordCursor += allWords.count
            } else if let headingLevel = rawLines[i].headingLevel {
                let words = tokenize(rawLines[i].content)
                result.append(ResponseSegment(
                    id: result.count,
                    kind: .heading(level: headingLevel),
                    words: words,
                    wordStart: wordCursor,
                    itemWordOffsets: []
                ))
                wordCursor += words.count
                i += 1
            } else {
                // Gather consecutive non-list lines into one paragraph segment.
                var paraWords: [String] = []
                while i < rawLines.count && !rawLines[i].isListItem && rawLines[i].headingLevel == nil {
                    paraWords.append(contentsOf: tokenize(rawLines[i].content))
                    i += 1
                }
                result.append(ResponseSegment(
                    id: result.count,
                    kind: .paragraph,
                    words: paraWords,
                    wordStart: wordCursor,
                    itemWordOffsets: []
                ))
                wordCursor += paraWords.count
            }
        }

        return result
    }

    private static func markdownHeading(from line: String) -> (level: Int, text: String)? {
        if line.hasPrefix("### ") {
            return (3, String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces))
        }
        if line.hasPrefix("## ") {
            return (2, String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces))
        }
        if line.hasPrefix("# ") {
            return (1, String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
        }
        if line.hasPrefix("**"), line.hasSuffix("**"), line.count > 4 {
            return (1, String(line.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces))
        }
        if line.hasPrefix("*"), line.hasSuffix("*"), line.count > 2 {
            return (2, String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// Tokenises a single line into words (and markdown links as single tokens).
    private static func tokenize(_ text: String) -> [String] {
        return CachedRegex.tokenizer.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .map { String(text[Range($0.range, in: text)!]) }
    }

    private static func insightLinkSequenceByWordStart(
        in segments: [ResponseSegment]
    ) -> [Int: Int] {
        var sequenceByWordStart: [Int: Int] = [:]
        var sequence = 0

        for segment in segments {
            for (offset, word) in segment.words.enumerated()
            where Self.insightLink(from: word) != nil {
                sequenceByWordStart[segment.wordStart + offset] = sequence
                sequence += 1
            }
        }

        return sequenceByWordStart
    }

    private static func insightLink(from word: String) -> ParsedInsightLink? {
        ParsedInsightLink(token: word)
    }

    // MARK: - Prototype Stream

    private func streamText() async {
        displayedWords = []
        isFinished = false
        showsInsightUnderlines = false
        guard !responseWords.isEmpty else { return }

        try? await Task.sleep(nanoseconds: 80_000_000)
        let words = responseWords

        for batchStart in stride(from: 0, to: words.count, by: streamBatchSize) {
            let batchEnd = min(batchStart + streamBatchSize, words.count)
            displayedWords.append(contentsOf: words[batchStart..<batchEnd])
            try? await Task.sleep(nanoseconds: streamBatchDelay)
        }

        // Underlines begin only after the final word has completed its reveal.
        try? await Task.sleep(nanoseconds: 550_000_000)
        guard !Task.isCancelled else { return }
        showsInsightUnderlines = true

        let underlineCount = insightLinkSequenceByWordStart.count
        if underlineCount > 0 {
            let underlineDuration = (Double(underlineCount - 1) * 0.1) + 0.42
            try? await Task.sleep(for: .seconds(underlineDuration))
            guard !Task.isCancelled else { return }
        }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0)) {
            isFinished = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            onFinish?()
        }
    }
}

private struct AnimatedInsightUnderlineText: View {
    let text: String
    let font: Font
    let color: Color
    let isVisible: Bool
    let animationDelay: Double
    let underlineOpacity: Double

    @State private var underlineProgress: CGFloat = 0

    var body: some View {
        Text(text)
            .bold()
            .font(font)
            .foregroundColor(color)
            .overlay(alignment: .bottomLeading) {
                Rectangle()
                    .fill(color)
                    .frame(height: 1)
                    .scaleEffect(x: underlineProgress, y: 1, anchor: .leading)
                    .offset(y: 1.5)
                    .opacity(underlineOpacity)
                    .animation(
                        .easeInOut(duration: 0.3),
                        value: underlineOpacity
                    )
            }
            .onAppear {
                if isVisible {
                    animateUnderlineIn()
                }
            }
            .onChange(of: isVisible) { _, visible in
                if visible {
                    animateUnderlineIn()
                } else {
                    underlineProgress = 0
                }
            }
    }

    private func animateUnderlineIn() {
        guard underlineProgress < 1 else { return }
        underlineProgress = 0
        withAnimation(.easeOut(duration: 0.42).delay(animationDelay)) {
            underlineProgress = 1
        }
    }
}

// MARK: - Persistent network-stream formatter

/// The same view hierarchy renders both the live prose and its annotated result.
/// Annotation changes token metadata in place; it never swaps the response body.
private struct LiveFormattedResponseView: View {
    let text: String
    let responseTextAlignment: ResponseTextAlignmentOption
    let responseFont: ConversationFontOption
    let conversationFontSize: ConversationFontSizeOption
    let loadingInsightKey: String?
    let queuedInsightKeys: Set<String>
    let onInsightTap: ((String, String) -> Void)?

    var body: some View {
        VStack(alignment: responseTextAlignment.horizontalAlignment, spacing: 16) {
            ForEach(LiveResponseBlock.parse(text)) { block in
                LiveResponseBlockView(
                    block: block,
                    sourceResponseBlock: text,
                    responseTextAlignment: responseTextAlignment,
                    responseFont: responseFont,
                    conversationFontSize: conversationFontSize,
                    loadingInsightKey: loadingInsightKey,
                    queuedInsightKeys: queuedInsightKeys,
                    onInsightTap: onInsightTap
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
        .textSelection(.enabled)
    }
}

private struct LiveResponseBlockView: View {
    let block: LiveResponseBlock
    let sourceResponseBlock: String
    let responseTextAlignment: ResponseTextAlignmentOption
    let responseFont: ConversationFontOption
    let conversationFontSize: ConversationFontSizeOption
    let loadingInsightKey: String?
    let queuedInsightKeys: Set<String>
    let onInsightTap: ((String, String) -> Void)?

    var body: some View {
        switch block.kind {
        case .paragraph(let text):
            LiveTokenFlow(
                source: text,
                sourceResponseBlock: sourceResponseBlock,
                font: responseFont.textFont(size: conversationFontSize),
                color: AquinasTheme.Colors.bodyText,
                allowsInlineMarkdown: true,
                spacing: 4.5,
                responseTextAlignment: responseTextAlignment,
                annotationSequenceStart: block.annotationSequenceStart,
                loadingInsightKey: loadingInsightKey,
                queuedInsightKeys: queuedInsightKeys,
                onInsightTap: onInsightTap
            )

        case .heading(let level, let text):
            LiveTokenFlow(
                source: text,
                sourceResponseBlock: sourceResponseBlock,
                font: headingFont(level: level),
                color: AquinasTheme.Colors.headingText,
                allowsInlineMarkdown: false,
                spacing: 5,
                responseTextAlignment: responseTextAlignment,
                annotationSequenceStart: block.annotationSequenceStart,
                loadingInsightKey: loadingInsightKey,
                queuedInsightKeys: queuedInsightKeys,
                onInsightTap: onInsightTap
            )

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 12) {
                ForEach(items.enumerated(), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1).")
                            .font(responseFont.textFont(size: conversationFontSize))
                            .foregroundColor(AquinasTheme.Colors.bodyText)
                            .frame(minWidth: 22, alignment: .trailing)

                        LiveTokenFlow(
                            source: item,
                            sourceResponseBlock: sourceResponseBlock,
                            font: responseFont.textFont(size: conversationFontSize),
                            color: AquinasTheme.Colors.bodyText,
                            allowsInlineMarkdown: true,
                            spacing: 4.5,
                            responseTextAlignment: responseTextAlignment,
                            annotationSequenceStart: annotationSequenceStart(forItemAt: index),
                            loadingInsightKey: loadingInsightKey,
                            queuedInsightKeys: queuedInsightKeys,
                            onInsightTap: onInsightTap
                        )
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(AquinasTheme.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AquinasTheme.Colors.quietBorder, lineWidth: 1)
            }
        }
    }

    private func annotationSequenceStart(forItemAt index: Int) -> Int {
        guard case .orderedList(let items) = block.kind else {
            return block.annotationSequenceStart
        }
        return block.annotationSequenceStart
            + items.prefix(index).reduce(0) {
                $0 + LiveResponseBlock.insightCount(in: $1)
            }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1:
            .custom(
                "LibreBaskerville-Regular",
                size: conversationFontSize.pointSize + 8
            )
        case 2:
            .custom(
                "LibreBaskerville-Regular",
                size: conversationFontSize.pointSize + 4
            )
        default:
            .custom(
                "Figtree-Bold",
                size: conversationFontSize.pointSize + 1
            )
        }
    }
}

private struct LiveTokenFlow: View {
    let source: String
    let sourceResponseBlock: String
    let font: Font
    let color: Color
    let allowsInlineMarkdown: Bool
    let spacing: CGFloat
    let responseTextAlignment: ResponseTextAlignmentOption
    let annotationSequenceStart: Int
    let loadingInsightKey: String?
    let queuedInsightKeys: Set<String>
    let onInsightTap: ((String, String) -> Void)?

    @State private var visibleTokenCount = 0
    @Environment(\.openURL) private var openURL

    private var tokens: [LiveResponseToken] {
        LiveResponseToken.parse(
            source,
            annotationSequenceStart: annotationSequenceStart
        )
    }

    var body: some View {
        FlowLayout(spacing: spacing, alignment: responseTextAlignment.textAlignment) {
            ForEach(tokens) { token in
                tokenView(token)
                    .opacity(token.id < visibleTokenCount ? 1 : 0)
                    .offset(y: token.id < visibleTokenCount ? 0 : 10)
                    .blur(radius: token.id < visibleTokenCount ? 0 : 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
        .onAppear {
            revealNewTokens(animated: true)
        }
        .onChange(of: tokens.count) { _, _ in
            revealNewTokens(animated: true)
        }
    }

    @ViewBuilder
    private func tokenView(_ token: LiveResponseToken) -> some View {
        if let annotation = token.annotation {
            let insightKey = insightLoadingKey(for: annotation.title)
            let isLoading = loadingInsightKey == insightKey
            let isQueued = queuedInsightKeys.contains(insightKey)
            Button {
                if let onInsightTap {
                    onInsightTap(annotation.title, sourceResponseBlock)
                } else {
                    openURL(annotation.url)
                }
            } label: {
                StableAnnotatedTokenLabel(
                    word: token.source,
                    leadingPunctuation: annotation.leadingPunctuation,
                    trailingPunctuation: annotation.trailingPunctuation,
                    font: font,
                    isLoading: isLoading,
                    isQueued: isQueued,
                    isVisible: token.id < visibleTokenCount,
                    animationDelay: Double(annotation.sequence) * 0.1
                )
            }
            .buttonStyle(.plain)
            .disabled(isLoading || isQueued)
        } else {
            Self.styledText(
                for: token.source,
                baseFont: font,
                allowsInlineMarkdown: allowsInlineMarkdown
            )
            .foregroundColor(color)
        }
    }

    private func revealNewTokens(animated: Bool) {
        guard visibleTokenCount < tokens.count else {
            visibleTokenCount = min(visibleTokenCount, tokens.count)
            return
        }

        if animated {
            withAnimation(.easeOut(duration: 0.55)) {
                visibleTokenCount = tokens.count
            }
        } else {
            visibleTokenCount = tokens.count
        }
    }

    private func insightLoadingKey(for title: String) -> String {
        "\(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())\n\(sourceResponseBlock)"
    }

    private static func styledText(
        for token: String,
        baseFont: Font,
        allowsInlineMarkdown: Bool
    ) -> Text {
        guard allowsInlineMarkdown,
              let markdown = inlineMarkdown(from: token) else {
            return Text(token).font(baseFont)
        }

        var text = Text(markdown.text).font(baseFont)
        if markdown.isBold { text = text.bold() }
        if markdown.isItalic { text = text.italic() }
        if !markdown.trailingPunctuation.isEmpty {
            text = text + Text(markdown.trailingPunctuation).font(baseFont)
        }
        return text
    }

    private static func inlineMarkdown(
        from token: String
    ) -> (
        text: String,
        trailingPunctuation: String,
        isBold: Bool,
        isItalic: Bool
    )? {
        let punctuation = token.reversed().prefix { ".,!?;:".contains($0) }
        let trailing = String(punctuation.reversed())
        let core = String(token.dropLast(trailing.count))
        if core.hasPrefix("**"), core.hasSuffix("**"), core.count > 4 {
            return (String(core.dropFirst(2).dropLast(2)), trailing, true, false)
        }
        if core.hasPrefix("*"), core.hasSuffix("*"), core.count > 2 {
            return (String(core.dropFirst().dropLast()), trailing, false, true)
        }
        return nil
    }
}

private struct StableAnnotatedTokenLabel: View {
    let word: String
    let leadingPunctuation: String
    let trailingPunctuation: String
    let font: Font
    let isLoading: Bool
    let isQueued: Bool
    let isVisible: Bool
    let animationDelay: Double

    var body: some View {
        // This invisible regular-weight token owns layout. Annotation is an
        // overlay, so bolding and the tap target cannot rewrap the paragraph.
        Text(leadingPunctuation + word + trailingPunctuation)
            .font(font)
            .foregroundStyle(.clear)
            .overlay(alignment: .leading) {
            if isLoading {
                HStack(spacing: 0) {
                    Text(leadingPunctuation)
                    Text(word).bold()
                    Text(trailingPunctuation)
                }
                .font(font)
                .foregroundColor(AquinasTheme.Colors.secondaryMuted)
                .modifier(
                    ThinkingShimmer(
                        isActive: true,
                        color: AquinasTheme.Colors.lightGreen
                    )
                )
            } else {
                HStack(spacing: 0) {
                    Text(leadingPunctuation)
                        .font(font)
                        .foregroundColor(AquinasTheme.Colors.secondaryMuted)
                    AnimatedInsightUnderlineText(
                        text: word,
                        font: font,
                        color: AquinasTheme.Colors.secondaryMuted,
                        isVisible: isVisible,
                        animationDelay: animationDelay,
                        underlineOpacity: 1
                    )
                    .modifier(
                        QueuedWorkBreatheModifier(
                            isQueued: isQueued
                        )
                    )
                    Text(trailingPunctuation)
                        .font(font)
                        .foregroundColor(AquinasTheme.Colors.secondaryMuted)
                }
            }
            }
            .contentShape(Rectangle())
    }
}

private struct LiveResponseToken: Identifiable {
    struct Annotation {
        let title: String
        let url: URL
        let leadingPunctuation: String
        let trailingPunctuation: String
        let sequence: Int
    }

    /// Generated prose is append-only, so the visible word ordinal remains stable
    /// when annotation metadata is attached at completion.
    let id: Int
    let source: String
    let annotation: Annotation?

    static func parse(
        _ source: String,
        annotationSequenceStart: Int
    ) -> [LiveResponseToken] {
        let rawTokens = CachedRegex.tokenizer.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        )
        .map { String(source[Range($0.range, in: source)!]) }

        var result: [LiveResponseToken] = []
        var annotationSequence = annotationSequenceStart

        for rawToken in rawTokens {
            guard let link = insightLink(from: rawToken) else {
                result.append(
                    LiveResponseToken(
                        id: result.count,
                        source: rawToken,
                        annotation: nil
                    )
                )
                continue
            }

            let visibleWords = link.title.split(whereSeparator: \.isWhitespace)
            for (index, visibleWord) in visibleWords.enumerated() {
                result.append(
                    LiveResponseToken(
                        id: result.count,
                        source: String(visibleWord),
                        annotation: Annotation(
                            title: link.title,
                            url: link.url,
                            leadingPunctuation: index == 0
                                ? link.leadingPunctuation
                                : "",
                            trailingPunctuation: index == visibleWords.count - 1
                                ? link.trailingPunctuation
                                : "",
                            sequence: annotationSequence
                        )
                    )
                )
            }
            annotationSequence += 1
        }

        return result
    }

    private static func insightLink(
        from token: String
    ) -> ParsedInsightLink? {
        ParsedInsightLink(token: token)
    }
}

private struct LiveResponseBlock: Identifiable {
    enum Kind {
        case paragraph(String)
        case heading(level: Int, text: String)
        case orderedList([String])
    }

    let id: Int
    let kind: Kind
    let annotationSequenceStart: Int

    static func parse(_ text: String) -> [LiveResponseBlock] {
        var blocks: [LiveResponseBlock] = []
        var paragraphLines: [String] = []
        var orderedItems: [String] = []
        var nextAnnotationSequence = 0

        func appendBlock(_ kind: Kind) {
            blocks.append(
                LiveResponseBlock(
                    id: blocks.count,
                    kind: kind,
                    annotationSequenceStart: nextAnnotationSequence
                )
            )
            nextAnnotationSequence += insightCount(in: kind)
        }

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            appendBlock(.paragraph(paragraphLines.joined(separator: " ")))
            paragraphLines.removeAll(keepingCapacity: true)
        }

        func flushOrderedList() {
            guard !orderedItems.isEmpty else { return }
            appendBlock(.orderedList(orderedItems))
            orderedItems.removeAll(keepingCapacity: true)
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match the completed response parser, which skips blank lines and
            // keeps adjacent prose in one paragraph flow. This prevents line
            // spacing from changing at completion.
            guard !trimmed.isEmpty else { continue }

            if let item = orderedListItem(from: trimmed) {
                flushParagraph()
                orderedItems.append(item)
                continue
            }

            flushOrderedList()
            if let heading = heading(from: trimmed) {
                flushParagraph()
                appendBlock(.heading(level: heading.level, text: heading.text))
            } else {
                paragraphLines.append(trimmed)
            }
        }

        flushParagraph()
        flushOrderedList()
        return blocks
    }

    static func insightCount(in source: String) -> Int {
        CachedRegex.tokenizer.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        )
        .reduce(into: 0) { count, match in
            let token = String(source[Range(match.range, in: source)!])
            if CachedRegex.insightLink.firstMatch(
                in: token,
                range: NSRange(token.startIndex..., in: token)
            ) != nil {
                count += 1
            }
        }
    }

    private static func insightCount(in kind: Kind) -> Int {
        switch kind {
        case .paragraph(let source), .heading(_, let source):
            insightCount(in: source)
        case .orderedList(let items):
            items.reduce(0) { $0 + insightCount(in: $1) }
        }
    }

    private static func orderedListItem(from line: String) -> String? {
        guard let match = CachedRegex.listLine.firstMatch(
            in: line,
            range: NSRange(line.startIndex..., in: line)
        ),
        let itemRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[itemRange])
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        if line.hasPrefix("### ") {
            return (3, String(line.dropFirst(4)))
        }
        if line.hasPrefix("## ") {
            return (2, String(line.dropFirst(3)))
        }
        if line.hasPrefix("# ") {
            return (1, String(line.dropFirst(2)))
        }
        if line.hasPrefix("**"), line.hasSuffix("**"), line.count > 4 {
            return (1, String(line.dropFirst(2).dropLast(2)))
        }
        if line.hasPrefix("*"), line.hasSuffix("*"), line.count > 2 {
            return (2, String(line.dropFirst().dropLast()))
        }
        return nil
    }
}


#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            StreamingMessageView(
                fullText: """
                This is what an ordered list should look like

                1. First item in the ordered list
                2. Second item in the ordered list
                3. Third item in the ordered list

                Then you should be able to type whatever you want after typing an ordered list and still have it all be a part of the same response.
                """,
                shouldStream: false
            )
            .padding()
        }
    }
    .background(AquinasTheme.Colors.canvas)
}
