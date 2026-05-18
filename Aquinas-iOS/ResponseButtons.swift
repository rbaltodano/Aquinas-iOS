//
//  ResponseButtons.swift
//  Aquinas-iOS
//

import SwiftUI
import UIKit

// MARK: - Shared Response Buttons

/// Shared action row for model responses and insight cards.
struct ResponseButtons: View {
    var isSaved: Bool = false
    var canCopy: Bool = false
    var canQuote: Bool = false
    var canFork: Bool = true
    var copyText: String? = nil
    var onSave: (() -> Void)? = nil
    var onCopy: (() -> Void)? = nil
    var onQuote: (() -> Void)? = nil
    var onFork: (() -> Void)? = nil

    @State private var visibleActionCount = 0
    @State private var showCopied = false

    private var actions: [ResponseButtonAction] {
        var items: [ResponseButtonAction] = []

        if onSave != nil {
            items.append(.save(isSaved: isSaved))
        }

        if canCopy || copyText != nil || onCopy != nil {
            items.append(.copy(isCopied: showCopied))
        }

        if canQuote, onQuote != nil {
            items.append(.quote)
        }

        if canFork, onFork != nil {
            items.append(.fork)
        }

        return items
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                if visibleActionCount > index {
                    Button {
                        handle(action)
                    } label: {
                        Image(systemName: action.systemName)
                            .font(.system(size: 16, weight: action.weight))
                            .rotationEffect(action == .fork ? .degrees(90) : .degrees(0))
                            .foregroundColor(action.foregroundColor)
                            .frame(width: 16, height: 16)
                            .sfSymbolDrawOn()
                    }
                    .buttonStyle(.plain)
                    .transition(.scale(scale: 0.88).combined(with: .opacity))
                }
            }
        }
        .onAppear(perform: revealButtons)
        .onChange(of: actions.count) { oldValue, newValue in
            revealButtons()
        }
    }

    private func handle(_ action: ResponseButtonAction) {
        switch action {
        case .save:
            onSave?()
        case .copy:
            if let copyText {
                UIPasteboard.general.string = copyText
            }
            onCopy?()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                showCopied = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showCopied = false
                }
            }
        case .quote:
            onQuote?()
        case .fork:
            onFork?()
        }
    }

    private func revealButtons() {
        visibleActionCount = 0

        for index in actions.indices {
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(index) * 0.15)) {
                withAnimation(.easeOut(duration: 0.28)) {
                    visibleActionCount = max(visibleActionCount, index + 1)
                }
            }
        }
    }
}

private enum ResponseButtonAction: Equatable {
    case save(isSaved: Bool)
    case copy(isCopied: Bool)
    case quote
    case fork

    var systemName: String {
        switch self {
        case .save(let isSaved):
            return isSaved ? "bookmark.fill" : "bookmark"
        case .copy(let isCopied):
            return isCopied ? "checkmark" : "square.on.square"
        case .quote:
            return "quote.opening"
        case .fork:
            return "arrow.triangle.branch"
        }
    }

    var weight: Font.Weight {
        switch self {
        case .fork:
            return .bold
        default:
            return .semibold
        }
    }

    var foregroundColor: Color {
        switch self {
        case .save(let isSaved):
            return isSaved ? AquinasTheme.Colors.accent : AquinasTheme.Colors.responseButton
        default:
            return AquinasTheme.Colors.responseButton
        }
    }
}
