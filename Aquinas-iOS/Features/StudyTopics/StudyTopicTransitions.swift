//
//  StudyTopicTransitions.swift
//  Aquinas-iOS
//

import SwiftUI

private struct AddButtonEntranceModifier: ViewModifier {
    let scale: CGFloat
    let opacity: Double
    let blurRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .blur(radius: blurRadius)
    }
}

extension AnyTransition {
    /// Scales down from 1.1 → 1, fades 0 → 1 opacity, and un-blurs 4pt → 0pt.
    /// Symmetric, so removal automatically plays the same recipe in reverse.
    static var addButtonEntrance: AnyTransition {
        .modifier(
            active: AddButtonEntranceModifier(scale: 1.1, opacity: 0, blurRadius: 4),
            identity: AddButtonEntranceModifier(scale: 1, opacity: 1, blurRadius: 0)
        )
    }

    /// Scales up 5%, blurs by 8pt, and fades to 0 opacity. Symmetric, so the button
    /// reverses the same recipe on the way back in.
    static var canvasToggleFade: AnyTransition {
        .modifier(
            active: AddButtonEntranceModifier(scale: 1.05, opacity: 0, blurRadius: 8),
            identity: AddButtonEntranceModifier(scale: 1, opacity: 1, blurRadius: 0)
        )
    }
}
