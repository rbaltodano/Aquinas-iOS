//
//  DynamicInsightSheetCard.swift
//  Aquinas-iOS
//
//  The Insight card shown when a concept link in a model response is tapped. It matches the
//  loaded card on other pages, but plays a generation sequence while the definition streams in:
//    1. icon + title (which never change) shimmer with the "Thinking" gradient sweep
//    2. the definition is skeleton bars — rounded capsules with an opacity pulse sweeping across
//    3. no action buttons yet
//    4. once the definition arrives: bars fade out → definition blurs/transforms in (like a model
//       response) → the action buttons animate in.
//

import SwiftUI

struct DynamicInsightSheetCard: View {
    let word: String
    /// nil while the definition is generating; set once ready.
    let concept: ConceptDefinition?
    let isSaved: Bool
    var onQuote: () -> Void
    var onFork: () -> Void
    var onToggleSaved: () -> Void

    @State private var showBars = true
    @State private var showDefinition = false
    @State private var showButtons = false

    private var isLoading: Bool { concept == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header: icon + title never change, so they stay put — only shimmering while loading.
            HStack(alignment: .center, spacing: 8) {
                // Icon + title share ONE sweep across their combined bounds, so the shimmer band
                // moves continuously through both as a single unit (not two independent sweeps).
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AquinasTheme.Colors.darkGreen)

                    Text(word.capitalized)
                        .font(.custom("Figtree-Bold", size: 18))
                        .foregroundColor(AquinasTheme.Colors.lightGreen)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .modifier(ShimmerSweep(isActive: isLoading, color: AquinasTheme.Colors.lightGreen))

                Spacer()

                // Buttons appear only after the definition has revealed.
                if showButtons {
                    ResponseButtons(
                        isSaved: isSaved,
                        canQuote: true,
                        canFork: true,
                        tintColor: AquinasTheme.Colors.placeholderText,
                        saveTintColor: AquinasTheme.Colors.accentRed,
                        onSave: onToggleSaved,
                        onQuote: onQuote,
                        onFork: onFork
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }

            // Body: a shimmering "Generating…" line while loading; the real definition
            // blur/transforms in after.
            ZStack(alignment: .topLeading) {
                if showBars {
                    Text("Generating relevant definition...")
                        .font(.figtreeParagraph)
                        .modifier(ShimmerSweep(isActive: true, color: AquinasTheme.Colors.placeholderText))
                        .transition(.opacity)
                }

                if showDefinition, let concept {
                    Text(concept.meaning)
                        .font(.figtreeParagraph)
                        .lineSpacing(12)
                        .foregroundColor(AquinasTheme.Colors.paragraphText)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.glideFadeUp)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AquinasTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(AquinasTheme.Colors.brownBorder, lineWidth: 1)
        )
        .shadow(color: Color(red: 0.13, green: 0.06, blue: 0).opacity(0.15), radius: 24, x: 0, y: 0)
        .onAppear {
            // Already loaded (e.g. reopened): show everything without the loading sequence.
            if concept != nil { showBars = false; showDefinition = true; showButtons = true }
        }
        .onChange(of: concept?.id) { _, newValue in
            guard newValue != nil else { return }
            runRevealSequence()
        }
    }

    private func runRevealSequence() {
        // 1. Bars fade out.
        withAnimation(.easeOut(duration: 0.3)) { showBars = false }
        // 2. Definition blur/transforms in.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            withAnimation(.easeOut(duration: 0.55)) { showDefinition = true }
        }
        // 3. Buttons animate in after the definition has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { showButtons = true }
        }
    }
}

// MARK: - Shimmer sweep

/// Sweeps a bright band across the content as ONE unit: the gradient lives in the content's own
/// combined bounds (via a masked overlay), so multiple elements — the icon + title — light up
/// continuously as the band passes, instead of each running its own independent sweep.
/// Leaves the content's own foreground color untouched when inactive.
private struct ShimmerSweep: ViewModifier {
    let isActive: Bool
    let color: Color

    func body(content: Content) -> some View {
        if isActive {
            content
                .foregroundColor(color.opacity(0.35))
                .overlay {
                    GeometryReader { geo in
                        TimelineView(.animation) { context in
                            let t = context.date.timeIntervalSinceReferenceDate
                            let cycle: Double = 2.0
                            let sweepSpan: Double = 1.0
                            let tMod = t.truncatingRemainder(dividingBy: cycle)
                            let phase = CGFloat(min(tMod / sweepSpan, 1.0))
                            let bandWidth = geo.size.width * 0.6
                            let centerX = (phase * 1.6 - 0.3) * geo.size.width
                            LinearGradient(
                                colors: [.clear, color, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: bandWidth)
                            .offset(x: centerX - bandWidth / 2)
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                        }
                    }
                    .mask(content)
                }
        } else {
            content
        }
    }
}
