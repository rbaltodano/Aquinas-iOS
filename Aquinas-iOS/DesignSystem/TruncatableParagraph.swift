//
//  TruncatableParagraph.swift
//  Aquinas-iOS
//

import SwiftUI

/// A paragraph that clamps to 4 lines with an ellipsis-capsule "…" button to expand/collapse it —
/// only shown when the text actually overflows 4 lines. The same expand affordance the
/// Conversation Card (`OpenConversationsView.ConversationCard`) uses to show/hide its Insight list
/// when there are more than 3.
struct TruncatableParagraph: View {
    let text: String
    var font: Font = .figtreeParagraph
    var lineSpacing: CGFloat = 12
    var color: Color = AquinasTheme.Colors.paragraphText

    @State private var isExpanded = false
    @State private var canExpand = false
    @State private var fullHeight: CGFloat = 0
    @State private var clampedHeight: CGFloat = 0

    private var paragraph: Text {
        Text(text)
            .font(font)
            .foregroundColor(color)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            paragraph
                .lineSpacing(lineSpacing)
                .lineLimit(isExpanded ? nil : 4)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: ClampedHeightKey.self, value: geo.size.height)
                    }
                )
                .background(
                    // Invisible, unclamped copy — its height reveals whether 4 lines actually cuts
                    // the text off, without a hardcoded line-height estimate.
                    paragraph
                        .lineSpacing(lineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: FullHeightKey.self, value: geo.size.height)
                            }
                        )
                )
                .onPreferenceChange(FullHeightKey.self) { fullHeight = $0; updateCanExpand() }
                .onPreferenceChange(ClampedHeightKey.self) { clampedHeight = $0; updateCanExpand() }

            if canExpand {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AquinasTheme.Colors.lightGreen)
                        .frame(width: 32, height: 18)
                        .background(AquinasTheme.Colors.canvas.opacity(0.72))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Once truncation is detected while collapsed, the button stays available so the text can
    /// also be collapsed back — never reset to false.
    private func updateCanExpand() {
        guard fullHeight > 0, clampedHeight > 0, fullHeight > clampedHeight + 1 else { return }
        canExpand = true
    }
}

private struct FullHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ClampedHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
