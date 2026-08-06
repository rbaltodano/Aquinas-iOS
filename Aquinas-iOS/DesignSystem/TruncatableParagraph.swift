//
//  TruncatableParagraph.swift
//  Aquinas-iOS
//

import SwiftUI
import UIKit

/// A paragraph that clamps to 4 lines with an ellipsis-capsule "…" button to expand/collapse it —
/// only shown when the text actually overflows 4 lines. The same expand affordance the
/// Conversation Card (`OpenConversationsView.ConversationCard`) uses to show/hide its Insight list
/// when there are more than 3. Tapping either the "…" button or the truncated text itself expands
/// it (tapping the text again while expanded collapses it back).
///
/// Truncation is detected via `NSString.boundingRect`, not by comparing two SwiftUI views'
/// measured heights (a dual-`GeometryReader` version of this previously existed and proved
/// unreliable — nesting one `.background(GeometryReader { … })` inside another's background chain
/// doesn't reliably report the inner view's natural, unclamped height, so the button could
/// silently never appear). Measuring the string directly against the real `UIFont` is
/// deterministic and doesn't depend on SwiftUI's live layout/timing.
struct TruncatableParagraph: View {
    let text: String
    var fontName: String = "Figtree-Regular"
    var fontSize: CGFloat = 14
    var lineSpacing: CGFloat = 12
    var color: Color = AquinasTheme.Colors.paragraphText

    @State private var isExpanded = false
    @State private var canExpand = false
    @State private var measuredWidth: CGFloat = 0

    private var uiFont: UIFont {
        UIFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.custom(fontName, size: fontSize))
                .lineSpacing(lineSpacing)
                .foregroundColor(color)
                .lineLimit(isExpanded ? nil : 4)
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard canExpand else { return }
                    toggleExpanded()
                }
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { updateCanExpand(width: geo.size.width) }
                            .onChange(of: geo.size.width) { _, width in updateCanExpand(width: width) }
                    }
                )

            if canExpand {
                Button(action: toggleExpanded) {
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
        .onChange(of: text) { _, _ in updateCanExpand(width: measuredWidth) }
    }

    private func toggleExpanded() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            isExpanded.toggle()
        }
    }

    private func updateCanExpand(width: CGFloat) {
        guard width > 0 else { return }
        measuredWidth = width
        let lineHeight = uiFont.lineHeight + lineSpacing
        guard lineHeight > 0 else { return }
        let boundingHeight = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: uiFont],
            context: nil
        ).height
        let estimatedLines = Int((boundingHeight / lineHeight).rounded(.up))
        canExpand = estimatedLines > 4
    }
}
