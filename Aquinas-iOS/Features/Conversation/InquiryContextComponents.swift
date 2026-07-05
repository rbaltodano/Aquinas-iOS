//
//  InquiryContextComponents.swift
//  Aquinas-iOS
//

import SwiftUI
import UIKit

// MARK: - Context Chips

/// Small locked/removable pill above a question. Used for insights and response forks.
struct BranchContextChip: View {
    let title: String
    let icon: String
    var animationKey: String = "static"
    var isFilled: Bool = false
    var fillColor: Color = AquinasTheme.Colors.canvasSecondary
    var appearDelay: TimeInterval = 0
    var animatesAppearance: Bool = true
    var showRemove: Bool = false
    var onRemove: (() -> Void)? = nil
    /// When true: no padding, no background, no border — just icon + text.
    var isMinimal: Bool = false
    @State private var borderDrawProgress: CGFloat = 0
    @State private var isVisible: Bool = false

    private var isInsightChip: Bool {
        icon == "text.bubble" || icon == "text.bubble.fill"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: isInsightChip ? 14 : 12, weight: .bold))
                .foregroundColor(AquinasTheme.Colors.darkGreen)
                .rotationEffect(icon == "arrow.triangle.branch" ? .degrees(90) : .degrees(0))
                .id(icon)
                .sfSymbolDrawOn(delay: appearDelay + 0.25)
            Text(title)
                .font(isInsightChip ? .figtreeHeading2 : .figtreeChipLabel)
                .foregroundColor(AquinasTheme.Colors.darkGreen)
                .lineLimit(1)
            if showRemove, let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AquinasTheme.Colors.darkGreen)
                        .sfSymbolDrawOn()
                }
                .padding(.leading, 4)
            }
        }
        .padding(.horizontal, isMinimal ? 0 : 20)
        .padding(.vertical, isMinimal ? 0 : 16)
        .background(isFilled && !isMinimal ? fillColor : Color.clear)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .inset(by: 0.5)
                .trim(from: 0, to: isMinimal ? 0 : borderDrawProgress)
                .stroke(AquinasTheme.Colors.brownBorder, lineWidth: 1)
        )
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.96)
        .onAppear(perform: revealChip)
        .onChange(of: animationKey) { oldValue, newValue in
            if !isMinimal { drawBorder() }
        }
        .transition(.scale.combined(with: .opacity))
    }

    private func revealChip() {
        guard animatesAppearance else {
            isVisible = true
            borderDrawProgress = isMinimal ? 0 : 1
            return
        }

        isVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + appearDelay) {
            withAnimation(.easeOut(duration: 0.25)) {
                isVisible = true
            }
            if !isMinimal { drawBorder() }
        }
    }

    private func drawBorder() {
        borderDrawProgress = 0
        withAnimation(.easeOut(duration: 0.55).delay(0.05)) {
            borderDrawProgress = 1
        }
    }
}

// MARK: - Connection Context Chip (two-concept inquire connection)

struct ConnectionContextChip: View {
    let conceptA: ConceptDefinition
    let conceptB: ConceptDefinition
    var onRemove: (() -> Void)? = nil
    @State private var borderDrawProgress: CGFloat = 0
    @State private var isVisible: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(conceptA.word.capitalized)
                .font(.figtreeHeading2)
                .foregroundColor(AquinasTheme.Colors.darkGreen)
                .lineLimit(1)

            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AquinasTheme.Colors.darkGreen)

            Text(conceptB.word.capitalized)
                .font(.figtreeHeading2)
                .foregroundColor(AquinasTheme.Colors.darkGreen)
                .lineLimit(1)

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AquinasTheme.Colors.darkGreen)
                        .sfSymbolDrawOn()
                }
                .padding(.leading, 4)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .inset(by: 0.5)
                .trim(from: 0, to: borderDrawProgress)
                .stroke(AquinasTheme.Colors.brownBorder, lineWidth: 1)
        )
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.96)
        .onAppear {
            withAnimation(.easeOut(duration: 0.25)) { isVisible = true }
            withAnimation(.easeOut(duration: 0.55).delay(0.05)) { borderDrawProgress = 1 }
        }
        .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - Uploaded File Thumbnails

struct UploadedFileStrip: View {
    let files: [UploadedFile]
    var onRemove: ((UploadedFile) -> Void)? = nil

    var body: some View {
        if !files.isEmpty {
            HStack(alignment: .center, spacing: 18) {
                ForEach(files) { file in
                    UploadedFileThumbnail(file: file, onRemove: onRemove.map { remove in
                        { remove(file) }
                    })
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }
}

struct UploadedFileThumbnail: View {
    let file: UploadedFile
    var onRemove: (() -> Void)? = nil

    var body: some View {
        // Thumbnail size, border thickness, and shadow are tuned here.
        ZStack(alignment: .topTrailing) {
            ZStack {
                if let imageData = file.imageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .sfSymbolDrawOn()
                        Text(file.name)
                            .font(.system(size: 8, weight: .semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 4)
                    }
                    .foregroundColor(AquinasTheme.Colors.secondaryMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AquinasTheme.Colors.cardRaised)
                }
            }
            .frame(width: 76, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(5)
            .background(AquinasTheme.Colors.uploadBorder)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: AquinasTheme.Colors.mediaShadow, radius: 18, x: 0, y: 10)

            if let onRemove {
                Button(action: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        onRemove()
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(AquinasTheme.Colors.canvasInverse)
                        .sfSymbolDrawOn()
                        .frame(width: 22, height: 22)
                        .background(AquinasTheme.Colors.uploadBorder)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AquinasTheme.Colors.quietBorder, lineWidth: 1))
                        .shadow(color: AquinasTheme.Colors.mediaShadow, radius: 8, x: 0, y: 4)
                }
                .offset(x: 7, y: -7)
                .buttonStyle(.plain)
            }
        }
        .rotationEffect(.degrees(file.rotationDegrees))
        .accessibilityLabel(file.name)
    }
}
