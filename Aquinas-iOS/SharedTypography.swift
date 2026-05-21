//
//  SharedTypography.swift
//  Aquinas-iOS
//
//  Created by Ryan on 4/14/26.
//

import Foundation
import SwiftUI

enum AquinasTheme {
    // MARK: Colors
    // Canonical visual tokens mirrored from the Figma paint styles.
    enum Colors {
        static let canvas = Color(light: 0xFFFAF0, dark: 0x181511)
        static let canvasSecondary = Color(light: 0xFBF4E7, dark: 0x1B1714)
        static let componentBackground = Color(
            light: 0x6F6844,
            lightAlpha: 0.05,
            dark: 0x4D453B,
            darkAlpha: 0.10
        )
        static let responseButton = Color(
            light: 0x6F6844,
            lightAlpha: 0.50,
            dark: 0xFFFAF0,
            darkAlpha: 0.25
        )
        static let lightGreen = Color(light: 0x867E4F, dark: 0xB7AE78)
        static let darkGreen = Color(light: 0x6F6844, dark: 0xB7AE78)
        static let lightBrown = Color(light: 0x4A321C, dark: 0xFFFAF0)
        static let paragraphText = Color(
            light: 0x4A321C,
            lightAlpha: 0.75,
            dark: 0xFFFAF0,
            darkAlpha: 0.75
        )
        static let placeholderText = Color(
            light: 0x4A321C,
            lightAlpha: 0.50,
            dark: 0xFFFAF0,
            darkAlpha: 0.50
        )
        static let darkBrown = Color(light: 0x220F01, dark: 0xFFFAF0)
        static let brownBorder = Color(
            light: 0x220F01,
            lightAlpha: 0.10,
            dark: 0xFFFAF0,
            darkAlpha: 0.08
        )
        static let sideMenuSearchBorder = Color(
            light: 0x6F6844,
            lightAlpha: 0.25,
            dark: 0xFFFAF0,
            darkAlpha: 0.08
        )
        static let systemSelection = Color(light: 0xF0E9DA, dark: 0x110E0B)
        static let accentRed = Color(light: 0xAF4949, dark: 0xAF4949)
        static let uploadBorder = Color(light: 0xFFFFFF, dark: 0xFFFAF0)

        // Compatibility aliases used by older views. New code should prefer the tokens above.
        static let primary = lightBrown
        static let primaryReadable = lightBrown
        static let secondary = lightGreen
        static let secondaryMuted = darkGreen
        static let secondaryLight = lightGreen
        static let linkGreen = lightGreen
        static let background = componentBackground
        static let card = componentBackground
        static let cardRaised = canvas
        static let surface = canvas
        static let sideMenuSurface = canvasSecondary
        static let activeInquiryChrome = componentBackground
        static let darkText = darkBrown
        static let bodyText = paragraphText
        static let accent = accentRed
        static let accentMuted = accentRed
        static let divider = brownBorder
        static let border = brownBorder
        static let quietBorder = brownBorder
        static let controlBorder = brownBorder
        static let mutedIcon = responseButton
        static let controlGlow = canvas
        static let floatingShadow = Color(
            light: 0x220F01,
            lightAlpha: 0.20,
            dark: 0x220F01
        )
        static let dropShadow = floatingShadow
        static let mediaShadow = dropShadow
    }

    // MARK: Typography
    // Libre Baskerville carries the editorial/conversation voice.
    // Figtree carries UI labels, body copy, buttons, and cards.
    enum Typography {
        static let title = Font.custom("LibreBaskerville-Regular", size: 24)
        static let titleLarge = Font.custom("LibreBaskerville-Regular", size: 34)
        static let heading = Font.custom("LibreBaskerville-Regular", size: 20)
        static let quote = Font.custom("LibreBaskerville-Italic", size: 16)
        static let baskervilleSmall = Font.custom("LibreBaskerville-Bold", size: 12)
        static let uiHeading = Font.custom("Figtree-Bold", size: 18)
        static let uiSubheading = Font.custom("Figtree-Bold", size: 14)
        static let uiLabel = Font.custom("Figtree-Bold", size: 12)
        static let body = Font.custom("Figtree-Regular", size: 14)
        static let bodyLarge = Font.custom("Figtree-Regular", size: 16)
        static let inlineInsight = Font.custom("Figtree-Bold", size: 16)
        static let chipLabel = Font.custom("Figtree-Bold", size: 12)
    }

    // MARK: Spacing and Shape
    // Shared dimensions for cards, capsules, and icon controls.
    enum Spacing {
        static let unit: CGFloat = 8
        static let screenPadding: CGFloat = 16
        static let cardPadding: CGFloat = 24
        static let cardRadius: CGFloat = 24
        static let smallCardRadius: CGFloat = 16
        static let controlHeight: CGFloat = 44
        static let iconButtonSize: CGFloat = 44
    }
}

extension Color {
    // Older views still use these brand names. They point back to the canonical theme tokens above.
    static let brandRed = AquinasTheme.Colors.accent
    static let brandDarkText = AquinasTheme.Colors.darkText
    static let brandGreen = AquinasTheme.Colors.linkGreen
    static let brandBrown = AquinasTheme.Colors.primary
    static let brandLightGreen = AquinasTheme.Colors.linkGreen
    static let chatBubbleColor = AquinasTheme.Colors.card
    static let backgroundColor = AquinasTheme.Colors.background

    init(hex: UInt, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    init(light: UInt, lightAlpha: Double = 1, dark: UInt, darkAlpha: Double = 1) {
        self.init(UIColor(light: light, lightAlpha: lightAlpha, dark: dark, darkAlpha: darkAlpha))
    }
}

extension UIColor {
    static let aquinasAccent = UIColor(light: 0xAF4949, dark: 0xAF4949)
    static let aquinasParagraphText = UIColor(
        light: 0x4A321C,
        lightAlpha: 0.75,
        dark: 0xFFFAF0,
        darkAlpha: 0.75
    )

    convenience init(hex: UInt, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    convenience init(light: UInt, lightAlpha: Double = 1, dark: UInt, darkAlpha: Double = 1) {
        self.init { traits in
            switch traits.userInterfaceStyle {
            case .dark:
                return UIColor(hex: dark, alpha: CGFloat(darkAlpha))
            default:
                return UIColor(hex: light, alpha: CGFloat(lightAlpha))
            }
        }
    }
}

extension Font {
    // MARK: Figtree aliases
    static let figtreeHeading1 = AquinasTheme.Typography.uiHeading
    static let figtreeHeading2 = AquinasTheme.Typography.uiSubheading
    static let figtreeHeading3 = AquinasTheme.Typography.uiLabel
    static let figtreeParagraph = AquinasTheme.Typography.body
    static let figtreeParagraphLarge = AquinasTheme.Typography.bodyLarge
    static let figtreeParagraphInsight = AquinasTheme.Typography.inlineInsight
    static let figtreeChipLabel = AquinasTheme.Typography.chipLabel
    static let figtreeSmall = Font.custom("Figtree-Regular", size: 12)

    // MARK: Libre Baskerville aliases
    static let baskervilleHeading1 = AquinasTheme.Typography.title
    static let baskervilleHeading2 = AquinasTheme.Typography.heading
    static let baskervilleHeading3 = Font.custom("LibreBaskerville-Regular", size: 14)
    static let baskervilleBody = Font.custom("LibreBaskerville-Regular", size: 16)
    static let baskervilleParagraph = Font.custom("LibreBaskerville-Regular", size: 14)
    static let baskervilleQuote = AquinasTheme.Typography.quote
    static let baskervilleSmall = AquinasTheme.Typography.baskervilleSmall
}

struct ParchmentCardStyle: ViewModifier {
    var radius: CGFloat = AquinasTheme.Spacing.cardRadius
    var background: Color = AquinasTheme.Colors.card
    var border: Color = AquinasTheme.Colors.quietBorder

    func body(content: Content) -> some View {
        // Shared flat card shell. Use this before adding one-off card styling.
        content
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
    }
}

struct AquinasCapsuleControlStyle: ViewModifier {
    var isSelected: Bool = false

    func body(content: Content) -> some View {
        // Shared pill controls for the bottom dock and canvas controls.
        content
            .foregroundColor(AquinasTheme.Colors.primaryReadable)
            .frame(minHeight: AquinasTheme.Spacing.controlHeight)
            .background(isSelected ? AquinasTheme.Colors.secondaryMuted : AquinasTheme.Colors.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(AquinasTheme.Colors.controlBorder, lineWidth: isSelected ? 0 : 1)
            )
    }
}

struct AquinasIconControlStyle: ViewModifier {
    var isPrimary: Bool = false

    func body(content: Content) -> some View {
        // Shared circular icon buttons, including plus and scroll-to-bottom.
        content
            .foregroundColor(isPrimary ? AquinasTheme.Colors.canvas : AquinasTheme.Colors.linkGreen)
            .frame(width: AquinasTheme.Spacing.iconButtonSize, height: AquinasTheme.Spacing.iconButtonSize)
            .background(isPrimary ? AquinasTheme.Colors.secondaryMuted : AquinasTheme.Colors.surface)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(AquinasTheme.Colors.controlBorder, lineWidth: isPrimary ? 0 : 1)
            )
    }
}

struct SFSymbolDrawOnStyle: ViewModifier {
    var delay: TimeInterval = 0
    @State private var isVisible = false

    func body(content: Content) -> some View {
        Group {
            if isVisible {
                animatedContent(content)
            } else {
                content.hidden()
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 0.55)) {
                    isVisible = true
                }
            }
        }
    }

    @ViewBuilder
    private func animatedContent(_ content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // Draw On is a symbol transition effect, so it runs when this wrapper inserts the icon.
            content.transition(.symbolEffect(.drawOn))
        } else {
            // Earlier OS versions still get a gentle entrance instead of a hard pop-in.
            content.transition(.opacity.combined(with: .scale(scale: 0.94)))
        }
    }
}

extension View {
    func parchmentCard(
        radius: CGFloat = AquinasTheme.Spacing.cardRadius,
        background: Color = AquinasTheme.Colors.card,
        border: Color = AquinasTheme.Colors.quietBorder
    ) -> some View {
        modifier(ParchmentCardStyle(radius: radius, background: background, border: border))
    }

    func aquinasCapsuleControl(isSelected: Bool = false) -> some View {
        modifier(AquinasCapsuleControlStyle(isSelected: isSelected))
    }

    func aquinasIconControl(isPrimary: Bool = false) -> some View {
        modifier(AquinasIconControlStyle(isPrimary: isPrimary))
    }

    func sfSymbolDrawOn(delay: TimeInterval = 0) -> some View {
        modifier(SFSymbolDrawOnStyle(delay: delay))
    }
}

// MARK: - Text Helpers

/// Reusable paragraph text with the app's body color and line spacing.
struct BodyText: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.figtreeParagraph)
            .lineSpacing(6)
            .foregroundColor(AquinasTheme.Colors.bodyText)
    }
}

/// Builds a Libre Baskerville title with one italic highlighted keyword.
func createEditorialTitle(
    fullText: String,
    keyword: String,
    fontSize: CGFloat,
    baseColor: Color = AquinasTheme.Colors.darkText,
    keywordColor: Color = AquinasTheme.Colors.accent
) -> AttributedString {
    var attributedString = AttributedString(fullText)

    attributedString.font = .custom("LibreBaskerville-Regular", size: fontSize)
    attributedString.foregroundColor = baseColor

    if let range = attributedString.range(of: keyword) {
        attributedString[range].font = .custom("LibreBaskerville-Italic", size: fontSize)
        attributedString[range].foregroundColor = keywordColor
    }

    return attributedString
}
