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
            .blur(radius: isActive ? 4 : 0)
            .opacity(isActive ? 0 : 1)
            .offset(y: isActive ? 6 : 0)
            .scaleEffect(isActive ? 0.97 : 1)
    }
}

/// Compatibility name for older response-card code.
typealias BlurFadeModifier = GlideFadeModifier

/// Simple wrapping layout for streamed words and inline insight links.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4.5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            let point = result.points[index]
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var points: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + 8
                    lineHeight = 0
                }
                points.append(CGPoint(x: currentX, y: currentY))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
            }
            size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

// Shared transition shorthand.
extension AnyTransition {
    static var glideFadeUp: AnyTransition {
        .modifier(active: GlideFadeModifier(isActive: true), identity: GlideFadeModifier(isActive: false))
    }

    static var blurSlideUp: AnyTransition {
        glideFadeUp
    }
}

// MARK: - Streaming Message View

/// Renders the model response body, animated word-by-word, with bookmark/copy/fork actions.
struct StreamingMessageView: View {
    let fullText: String
    let shouldStream: Bool
    var onQuote: ((String) -> Void)? = nil
    var onBranch: (() -> Void)? = nil
    var onFinish: (() -> Void)? = nil
    private let responseWords: [String]
    private let streamBatchSize = 4
    private let streamBatchDelay: UInt64 = 55_000_000

    @State private var displayedWords: [String] = []
    @State private var isFinished: Bool = false
    @Environment(\.openURL) private var openURL

    init(
        fullText: String,
        shouldStream: Bool = true,
        onQuote: ((String) -> Void)? = nil,
        onBranch: (() -> Void)? = nil,
        onFinish: (() -> Void)? = nil
    ) {
        self.fullText = fullText
        self.shouldStream = shouldStream
        self.onQuote = onQuote
        self.onBranch = onBranch
        self.onFinish = onFinish
        let words = Self.words(from: fullText)
        self.responseWords = words
        _displayedWords = State(initialValue: shouldStream ? [] : words)
        _isFinished = State(initialValue: !shouldStream)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Reserve the final response height up front, then stream visible words inside it.
            ZStack(alignment: .topLeading) {
                wordFlow(words: responseWords)
                    .hidden()

                wordFlow(words: displayedWords)
            }
            .animation(.easeOut(duration: 0.18), value: displayedWords.count)

            // Response actions shown after the streamed text finishes.
            if isFinished {
                ResponseButtons(
                    canCopy: true,
                    canFork: onBranch != nil,
                    copyText: fullText,
                    onSave: {
                        print("Saved to bookmarks!")
                    },
                    onQuote: onQuote.map { quote in { quote(fullText) } },
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

        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            if shouldStream {
                await streamText()
            }
        }
    }

    // MARK: Prototype Stream

    @ViewBuilder
    private func wordFlow(words: [String]) -> some View {
        FlowLayout {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                if let link = insightLink(from: word) {
                    Button(action: {
                        openURL(link.url)
                    }) {
                        HStack(spacing: 0) {
                            Text(link.title)
                                .underline()
                            Text(link.trailingPunctuation)
                        }
                        .font(.figtreeParagraphInsight)
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

    private func insightLink(from word: String) -> (title: String, url: URL, trailingPunctuation: String)? {
        let pattern = #"^\[([^\]]+)\]\(([^)]+)\)([.,!?;:]*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: word, range: NSRange(word.startIndex..., in: word)),
              match.numberOfRanges == 4,
              let titleRange = Range(match.range(at: 1), in: word),
              let urlRange = Range(match.range(at: 2), in: word),
              let punctuationRange = Range(match.range(at: 3), in: word),
              let url = URL(string: String(word[urlRange])) else {
            return nil
        }

        return (
            title: String(word[titleRange]),
            url: url,
            trailingPunctuation: String(word[punctuationRange])
        )
    }

    private static func words(from text: String) -> [String] {
        let pattern = "\\[[^\\]]+\\]\\([^\\)]+\\)[.,!?;]*|\\S+"
        let regex = try! NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.map { String(text[Range($0.range, in: text)!]) }
    }

    /// Temporary word-by-word renderer. Replace delays with real model streaming later.
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

        // Tell the parent card it can show the next input.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            onFinish?()
        }
    }

}


#Preview {
    ZStack {
        AquinasTheme.Colors.surface.ignoresSafeArea()

        VStack(alignment: .leading) {
            StreamingMessageView(
                fullText: "The Didache, also known as The Lord's Teaching Through the Twelve Apostles to the Nations, is a brief anonymous early Christian treatise written in Koine Greek."
            )
            .padding()

            Spacer()
        }
    }
}
