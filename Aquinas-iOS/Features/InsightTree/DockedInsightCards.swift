//
//  DockedInsightCards.swift
//  Aquinas-iOS
//

import SwiftUI
import UIKit

struct DockedInsightTreeCard: View {
    let insight: InsightModel
    var isSaved: Bool = false

    /// When true, the body text fades/transforms/blurs in like a streamed model response.
    var animateIn: Bool = false
    /// Insight links grown under the card content while Make Node generates children — each
    /// appears in sync with its child's reveal haptic.
    var linkedInsights: [InsightModel] = []
    var onToggleSaved: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil
    var onFork:   (() -> Void)? = nil
    var onSelectLinkedInsight: ((InsightModel) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var textRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                DockedCardTextBubbleIcon(size: 12, delay: 0.18, color: AquinasTheme.Colors.darkGreen)

                Text(insight.title)
                    .font(.custom("Figtree-Bold", size: 18))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                ResponseButtons(
                    isSaved: isSaved,
                    canCopy: true,
                    canFork: true,
                    copyText: insight.definition,
                    tintColor: AquinasTheme.Colors.placeholderText,
                    saveTintColor: isSaved ? AquinasTheme.Colors.accentRed : nil,
                    onSave: onToggleSaved,
                    onFork: { onFork?() }
                )

                if let onRemove {
                    Button(action: onRemove) {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AquinasTheme.Colors.placeholderText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove from conversation")
                }
            }

            let definitionText = insight.definition.isEmpty || insight.definition.lowercased() == insight.title.lowercased()
                ? "This is an example of what an Insight Card will look like, the definition as relates to subject will be here"
                : insight.definition
            TruncatableParagraph(text: definitionText)
                .modifier(GlideFadeModifier(isActive: animateIn && !textRevealed))

            // Insight links grown one-by-one as Make Node reveals each child (on its haptic).
            if !linkedInsights.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(linkedInsights, id: \.id) { linked in
                        DockedInsightLinkRow(insight: linked) { onSelectLinkedInsight?($0) }
                    }
                }
                .padding(.top, 4)
            }
        }
        .onAppear {
            // The border + background fade in with the card; 0.15s later the body text
            // animates in (blur/fade/transform), like a streamed model response.
            guard animateIn else { return }
            textRevealed = false
            withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                textRevealed = true
            }
        }
        // Trim the bottom: the definition's .lineSpacing(12) leaves trailing space below the
        // last line, so a full 32 there reads as noticeably more space than the 32 up top.
        .dockedCardChrome(bottomPadding: 20)
    }
}

extension View {
    /// The docked Insight card's chrome: padding, full width, fill, 36 pt continuous corners,
    /// hairline border, and soft shadow. Shared so other docked cards match it exactly.
    /// `clipsContent` false lets content move past the card's edge (the Study tool card's
    /// sliding copy); the card itself looks the same.
    func dockedCardChrome(bottomPadding: CGFloat, clipsContent: Bool = true) -> some View {
        self
            .padding(.horizontal, 32)
            .padding(.top, 32)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(insightTreeInsightColor, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
            .modifier(DockedCardClip(isEnabled: clipsContent))
            .overlay(
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .stroke(AquinasTheme.Colors.brownBorder, lineWidth: 1)
            )
            .shadow(color: Color(red: 0.13, green: 0.06, blue: 0).opacity(0.15), radius: 24, x: 0, y: 0)
    }
}

private struct DockedCardClip: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        } else {
            content
        }
    }
}

/// A node concept's docked card. Renders identically to `DockedInsightTreeCard` (icon + title +
/// action buttons + definition), then lists links to its child/member insights underneath.
struct DockedNodeTreeCard: View {
    let node: NodeModel

    var isSaved: Bool = false
    var onSelectInsight: (InsightModel) -> Void
    var onToggleSaved: (() -> Void)? = nil
    var onFork: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    /// Fallback body when a node carries no definition of its own (auto clustered concepts).
    private var summaryText: String {
        let titles = node.insights.prefix(3).map(\.title)
        guard !titles.isEmpty else {
            return "\(node.conceptLabel) is a developing subject in this insight map."
        }

        return "\(node.conceptLabel) gathers related insights around \(titles.joined(separator: ", "))."
    }

    private var bodyText: String {
        node.definition.isEmpty ? summaryText : node.definition
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                DockedCardTextBubbleIcon(size: 12, delay: 0.18, color: AquinasTheme.Colors.darkGreen)

                Text(node.conceptLabel)
                    .font(.custom("Figtree-Bold", size: 18))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                ResponseButtons(
                    isSaved: isSaved,
                    canCopy: true,
                    canFork: onFork != nil,
                    copyText: bodyText,
                    tintColor: AquinasTheme.Colors.placeholderText,
                    saveTintColor: AquinasTheme.Colors.accentRed,
                    onSave: onToggleSaved,
                    onFork: onFork
                )
            }

            TruncatableParagraph(text: bodyText)

            // Links to the concept's child / member insights.
            if !node.insights.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(node.insights, id: \.id) { insight in
                        DockedInsightLinkRow(insight: insight, onTap: onSelectInsight)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(insightTreeInsightColor)
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(AquinasTheme.Colors.brownBorder, lineWidth: 1)
        )
        .shadow(color: Color(red: 0.13, green: 0.06, blue: 0).opacity(0.15), radius: 24, x: 0, y: 0)
    }
}

/// One tappable Insight link row — shared under both the insight and node concept cards for
/// child/member insights (bubble icon + underlined title in the muted link color). Appears with a
/// fade/rise/scale insertion so links added mid-animation (Make Node) glide in one at a time.
private struct DockedInsightLinkRow: View {
    let insight: InsightModel
    var onTap: (InsightModel) -> Void

    var body: some View {
        Button {
            onTap(insight)
        } label: {
            HStack(spacing: 8) {
                DockedCardTextBubbleIcon(size: 14, delay: 0, color: AquinasTheme.Colors.darkGreen)

                // No minimumScaleFactor: it interacts with the insertion transition below and
                // locks later-inserted rows at a slightly reduced scale. Fixed size + truncation
                // keeps every link identical.
                Text(insight.title)
                    .font(.figtreeParagraph)
                    .bold()
                    .foregroundColor(AquinasTheme.Colors.secondaryMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Glide in with a fade + gentle rise. No .scale here — scaling the row makes the text's
        // layout resolve at a smaller size and it stays shrunk after the transition settles.
        .transition(.opacity.combined(with: .offset(y: 10)))
    }
}

struct DockedConceptCard: View {
    let concept: ConceptDefinition
    let isSaved: Bool
    var onToggleSaved: () -> Void
    var onFork: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                DockedCardTextBubbleIcon(size: 12, delay: 0.18, color: AquinasTheme.Colors.darkGreen)
                Text(concept.word.capitalized)
                    .font(.custom("Figtree-Bold", size: 18))
                    .foregroundColor(AquinasTheme.Colors.lightGreen)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
                ResponseButtons(
                    isSaved: isSaved,
                    canCopy: true,
                    canFork: true,
                    copyText: concept.semanticDefinition,
                    tintColor: AquinasTheme.Colors.placeholderText,
                    saveTintColor: AquinasTheme.Colors.accentRed,
                    onSave: onToggleSaved,
                    onFork: onFork
                )
            }
            InsightDefinitionsContent(
                definitions: concept.contextualDefinitions
            )
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(insightTreeInsightColor)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AquinasTheme.Colors.brownBorder, lineWidth: 1)
        )
    }
}

/// Docked card shown during Midpoint Selection mode: lists the selected insights and the
/// blend percentage of the new insight. For two insights the percentage is editable
/// (tap to type, drag to scrub); for 3+ the weights are shown read-only.
struct MidpointPercentCard: View {
    let concepts: [ConceptDefinition]
    let weights: [Double]
    var onSetPercent: (Int, Int) -> Void

    private var percents: [Int] {
        guard weights.count == concepts.count, !weights.isEmpty else { return [] }
        return weights.map { Int(($0 * 100).rounded()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select Midpoint")
                .font(.custom("Figtree-Bold", size: 18))
                .foregroundColor(AquinasTheme.Colors.headingText)

            ForEach(Array(concepts.enumerated()), id: \.offset) { index, concept in
                row(index: index, concept: concept)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(insightTreeInsightColor)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AquinasTheme.Colors.brownBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func row(index: Int, concept: ConceptDefinition) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AquinasTheme.Colors.lightGreen)
            Text(concept.word.capitalized)
                .font(.custom("Figtree-Bold", size: 14))
                .foregroundColor(AquinasTheme.Colors.lightGreen)
                .lineLimit(1)
                .layoutPriority(1)

            DottedConnector()

            if let percent = index < percents.count ? percents[index] : nil {
                PercentStepper(
                    percent: percent,
                    onChange: { newValue in onSetPercent(index, newValue) }
                )
            }
        }
    }
}

/// `‹ XX% ›` percentage control: chevrons step by 1%, the number itself can be tapped to type
/// or dragged to scrub. Fires a light haptic for every 1% change.
private struct PercentStepper: View {
    let percent: Int
    var onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            chevron("chevron.left") { step(-1) }
            EditablePercent(percent: percent, onChange: onChange)
            chevron("chevron.right") { step(1) }
        }
    }

    private func chevron(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AquinasTheme.Colors.headingText)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func step(_ delta: Int) {
        let newValue = min(100, max(0, percent + delta))
        guard newValue != percent else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
        onChange(newValue)
    }
}

/// A faint dotted line that fills the available horizontal space.
private struct DottedConnector: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
            }
            .stroke(
                AquinasTheme.Colors.paragraphText.opacity(0.3),
                style: StrokeStyle(lineWidth: 1, dash: [1.5, 4])
            )
        }
        .frame(height: 1)
        .frame(maxWidth: .infinity)
    }
}

/// A percentage value that can be tapped to type an exact number or dragged horizontally to
/// scrub. Fires a light haptic for every 1% change while scrubbing.
private struct EditablePercent: View {
    let percent: Int
    var onChange: (Int) -> Void

    @State private var isEditing = false
    @State private var text = ""
    @State private var dragStartPercent: Int? = nil
    @State private var lastHapticPercent: Int = 0
    @State private var flashOpacity: CGFloat = 1.0
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField("", text: $text)
                    .keyboardType(.numberPad)
                    .focused($focused)
                    .font(.custom("Figtree-Bold", size: 16))
                    .foregroundColor(AquinasTheme.Colors.headingText)
                    .fixedSize()
                    .opacity(flashOpacity)
                    .onSubmit(commit)
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { commit() }
                    }
                    .onAppear {
                        flashOpacity = 1.0
                        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                            flashOpacity = 0.5
                        }
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button(action: commit) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(AquinasTheme.Colors.lightGreen)
                            }
                        }
                    }
            } else {
                Text("\(percent)%")
                    .font(.custom("Figtree-Bold", size: 16))
                    .foregroundColor(AquinasTheme.Colors.headingText)
                    .monospacedDigit()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        text = "\(percent)"
                        isEditing = true
                        focused = true
                    }
                    .gesture(scrubGesture)
            }
        }
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragStartPercent == nil {
                    dragStartPercent = percent
                    lastHapticPercent = percent
                }
                let base = dragStartPercent ?? percent
                let delta = Int((value.translation.width / 4).rounded())
                let newValue = min(100, max(0, base + delta))
                if newValue != lastHapticPercent {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred(intensity: 0.55)
                    lastHapticPercent = newValue
                }
                if newValue != percent { onChange(newValue) }
            }
            .onEnded { _ in dragStartPercent = nil }
    }

    private func commit() {
        guard isEditing else { return }
        isEditing = false
        focused = false
        let digits = text.filter(\.isNumber)
        guard let value = Int(digits) else { return }
        onChange(min(100, max(0, value)))
    }
}

private struct DockedCardTextBubbleIcon: View {
    let size: CGFloat
    var delay: TimeInterval = 0
    var color: Color = AquinasTheme.Colors.darkGreenDarkMode
    @State private var isVisible = false

    var body: some View {
        Image(systemName: "text.bubble.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(color)
            .scaleEffect(isVisible ? 1 : 0.86)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                isVisible = false
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                        isVisible = true
                    }
                }
            }
    }
}
