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
    // The fix: use SwiftUI's built-in Layout cache to remember each word's CGSize
    // by its subview index. Words are append-only during streaming, so a cached
    // size is always valid for the lifetime of the layout. New words get measured
    // once; all previous words are a free dictionary lookup.
    //
    // Expected reduction: ~188,000 → ~1,000 total measurements for a 500-word stream.

    typealias Cache = [Int: CGSize]

    func makeCache(subviews: Subviews) -> Cache { [:] }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        if cache.count > subviews.count {
            cache = cache.filter { $0.key < subviews.count }
        }
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

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat, alignment: TextAlignment, cache: inout [Int: CGSize]) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            // Track each row's subview range and packed width so we can center
            // every row horizontally once the full row is known.
            var rowRanges: [(range: Range<Int>, width: CGFloat)] = []
            var rowStart = 0

            for (idx, subview) in subviews.enumerated() {
                let wordSize: CGSize
                if let hit = cache[idx] {
                    wordSize = hit
                } else {
                    wordSize = subview.sizeThatFits(.unspecified)
                    cache[idx] = wordSize
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
    static let insightLink = try! NSRegularExpression(pattern: #"^\[([^\]]+)\]\(([^)]+)\)([.,!?;:]*)$"#)
    static let tokenizer   = try! NSRegularExpression(pattern: #"\[[^\]]+\]\([^)]+\)[.,!?;]*|\S+"#)
}

// MARK: - Response Segment Model

/// A parsed block of text — either a normal paragraph or a numbered list.
private struct ResponseSegment: Identifiable {
    enum Kind {
        case paragraph
        case orderedList([String])  // item texts, already stripped of "1." prefix
    }

    let id = UUID()
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
    let responseTextAlignment: ResponseTextAlignmentOption
    let responseFont: ConversationFontOption
    let conversationFontSize: ConversationFontSizeOption
    var onQuote: ((String) -> Void)? = nil
    var onBranch: (() -> Void)? = nil
    var onFinish: (() -> Void)? = nil

    private let segments: [ResponseSegment]
    private let responseWords: [String]
    private let streamBatchSize = 4
    private let streamBatchDelay: UInt64 = 55_000_000

    // Process-level cache keyed by response text. parseSegments + tokenize is
    // O(words) and called every time a parent view re-renders (SwiftUI creates new
    // struct values for comparison). Caching makes repeated inits a O(1) lookup.
    private static var parseCache: [String: (segments: [ResponseSegment], words: [String])] = [:]

    @State private var displayedWords: [String] = []
    @State private var isFinished: Bool = false
    @Environment(\.openURL) private var openURL

    init(
        fullText: String,
        shouldStream: Bool = true,
        responseTextAlignment: ResponseTextAlignmentOption = .center,
        responseFont: ConversationFontOption = .sans,
        conversationFontSize: ConversationFontSizeOption = .large,
        onQuote: ((String) -> Void)? = nil,
        onBranch: (() -> Void)? = nil,
        onFinish: (() -> Void)? = nil
    ) {
        self.fullText = fullText
        self.shouldStream = shouldStream
        self.responseTextAlignment = responseTextAlignment
        self.responseFont = responseFont
        self.conversationFontSize = conversationFontSize
        self.onQuote = onQuote
        self.onBranch = onBranch
        self.onFinish = onFinish

        let cached: (segments: [ResponseSegment], words: [String])
        if let hit = Self.parseCache[fullText] {
            cached = hit
        } else {
            let segs = Self.parseSegments(from: fullText)
            let words = segs.flatMap { $0.words }
            cached = (segments: segs, words: words)
            Self.parseCache[fullText] = cached
        }
        self.segments = cached.segments
        self.responseWords = cached.words
        _displayedWords = State(initialValue: shouldStream ? [] : cached.words)
        _isFinished = State(initialValue: !shouldStream)
    }

    var body: some View {
        VStack(alignment: responseTextAlignment.horizontalAlignment, spacing: 12) {

            // Reserve the final response height up front so the card doesn't jump,
            // then reveal content on top of the ghost via streaming progress.
            ZStack(alignment: .top) {
                segmentsView(displayedCount: responseWords.count)
                    .hidden()

                segmentsView(displayedCount: displayedWords.count)
                    .textSelection(.enabled)   // let the user highlight / copy the response text
            }
            .animation(.easeOut(duration: 0.55), value: displayedWords.count)

            if isFinished {
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
        }
        .frame(maxWidth: .infinity, alignment: responseTextAlignment.frameAlignment)
        .task {
            if shouldStream { await streamText() }
        }
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
                wordFlow(words: segment.words, visibleCount: available)

            case .orderedList(let items):
                orderedListBubble(
                    items: items,
                    allWords: segment.words,
                    itemOffsets: segment.itemWordOffsets,
                    available: available
                )
            }
        }
    }

    // MARK: - Ordered list bubble

    @ViewBuilder
    private func orderedListBubble(
        items: [String],
        allWords: [String],
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
                    wordFlow(words: itemWords, visibleCount: max(0, available - itemStart))
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
    private func wordFlow(words: [String], visibleCount: Int) -> some View {
        FlowLayout(alignment: responseTextAlignment.textAlignment) {
            ForEach(Array(words.enumerated()), id: \.offset) { idx, word in
                Group {
                    if let link = insightLink(from: word) {
                        Button(action: { openURL(link.url) }) {
                            HStack(spacing: 0) {
                                Text(link.title).underline().bold()
                                Text(link.trailingPunctuation)
                            }
                            .font(responseFont.textFont(size: conversationFontSize))
                            .foregroundColor(AquinasTheme.Colors.secondaryMuted)
                            .padding(.horizontal, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(word)
                            .font(responseFont.textFont(size: conversationFontSize))
                            .foregroundColor(AquinasTheme.Colors.bodyText)
                    }
                }
                // All words are laid out up front, so positions are final; reveal
                // each word with a slow fade + upward drift. The offset is purely
                // visual (doesn't affect layout), so positions never shift.
                .opacity(idx < visibleCount ? 1 : 0)
                .offset(y: idx < visibleCount ? 0 : 10)
                .blur(radius: idx < visibleCount ? 0 : 3)
            }
        }
    }

    // MARK: - Parsing

    /// Splits fullText into paragraph and ordered-list segments.
    /// Consecutive lines matching `^\d+[.)]\s+` form one orderedList segment.
    private static func parseSegments(from text: String) -> [ResponseSegment] {
        // Matches "1. ", "2) ", "10. " etc. and captures the item text.
        let listLineRegex = CachedRegex.listLine

        struct RawLine { let isListItem: Bool; let content: String }

        var rawLines: [RawLine] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if let match = listLineRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let itemRange = Range(match.range(at: 1), in: trimmed) {
                rawLines.append(RawLine(isListItem: true, content: String(trimmed[itemRange])))
            } else {
                rawLines.append(RawLine(isListItem: false, content: trimmed))
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
                    kind: .orderedList(items),
                    words: allWords,
                    wordStart: wordCursor,
                    itemWordOffsets: itemOffsets
                ))
                wordCursor += allWords.count
            } else {
                // Gather consecutive non-list lines into one paragraph segment.
                var paraWords: [String] = []
                while i < rawLines.count && !rawLines[i].isListItem {
                    paraWords.append(contentsOf: tokenize(rawLines[i].content))
                    i += 1
                }
                result.append(ResponseSegment(
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

    /// Tokenises a single line into words (and markdown links as single tokens).
    private static func tokenize(_ text: String) -> [String] {
        return CachedRegex.tokenizer.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .map { String(text[Range($0.range, in: text)!]) }
    }

    private func insightLink(from word: String) -> (title: String, url: URL, trailingPunctuation: String)? {
        guard let match = CachedRegex.insightLink.firstMatch(in: word, range: NSRange(word.startIndex..., in: word)),
              match.numberOfRanges == 4,
              let titleRange = Range(match.range(at: 1), in: word),
              let urlRange = Range(match.range(at: 2), in: word),
              let punctuationRange = Range(match.range(at: 3), in: word),
              let url = URL(string: String(word[urlRange])) else { return nil }
        return (
            title: String(word[titleRange]),
            url: url,
            trailingPunctuation: String(word[punctuationRange])
        )
    }

    // MARK: - Prototype Stream

    private func streamText() async {
        try? await Task.sleep(nanoseconds: 400_000_000)
        let words = responseWords

        for batchStart in stride(from: 0, to: words.count, by: streamBatchSize) {
            let batchEnd = min(batchStart + streamBatchSize, words.count)
            displayedWords.append(contentsOf: words[batchStart..<batchEnd])
            try? await Task.sleep(nanoseconds: streamBatchDelay)
        }

        try? await Task.sleep(nanoseconds: 300_000_000)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0)) {
            isFinished = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            onFinish?()
        }
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
