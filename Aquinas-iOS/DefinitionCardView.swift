//
//  DefinitionCardView.swift
//  Aquinas-iOS
//
//  Created by Ryan on 4/17/26.
//

import Foundation
import SwiftUI

// MARK: - Definition Card

/// Reusable card for a saved/generated insight definition.
struct DefinitionCardView: View {
    var word: ConceptDefinition

    let brandDarkText = AquinasTheme.Colors.primaryReadable
    let mutedText = AquinasTheme.Colors.paragraphText

    let cardBackground = AquinasTheme.Colors.cardRaised

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Word and part of speech.
            HStack(alignment: .bottom) {
                Text(word.word)
                    .font(.figtreeHeading1)
                    .foregroundColor(brandDarkText)

                Spacer()

                Text(word.partOfSpeech)
                    .font(.baskervilleHeading3)
                    .foregroundColor(AquinasTheme.Colors.paragraphText)
            }

            // Pronunciation sits close to the header.
            Text(word.pronunciation)
                .font(.baskervilleHeading3)
                .foregroundColor(mutedText)
                .padding(.top, -8)

            // Definition body.
            Text(word.meaning)
                .font(.baskervilleBody)
                .foregroundColor(brandDarkText)
                .lineSpacing(6)

            // Optional italic example.
            if !word.example.isEmpty {
                Text(word.example)
                    .font(.baskervilleQuote)
                    .foregroundColor(AquinasTheme.Colors.paragraphText)
            }
        }
        .padding(AquinasTheme.Spacing.cardPadding)
        .parchmentCard(
            radius: AquinasTheme.Spacing.smallCardRadius,
            background: cardBackground,
            border: AquinasTheme.Colors.brownBorder
        )
        .shadow(color: AquinasTheme.Colors.floatingShadow, radius: 10, x: 0, y: 4)
    }
}
