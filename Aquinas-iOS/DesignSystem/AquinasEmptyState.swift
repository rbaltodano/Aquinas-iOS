//
//  AquinasEmptyState.swift
//  Aquinas-iOS
//

import SwiftUI

/// Shared empty-state treatment: icon, heading, and supporting copy, centered.
/// Mirrors the Insight Tree's empty state so list screens read as one system.
struct AquinasEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(AquinasTheme.Colors.lightGreen)
                .sfSymbolDrawOn()

            Text(title)
                .font(.baskervilleHeading1)
                .foregroundColor(AquinasTheme.Colors.primaryReadable)

            Text(message)
                .font(.figtreeParagraph)
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .foregroundColor(AquinasTheme.Colors.paragraphText)
                .frame(maxWidth: 280)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
