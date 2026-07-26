//
//  ListAwareTextField.swift
//  Aquinas-iOS
//
//  Created by Ryan on 5/25/26.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - TextInputRelay

/// A lightweight reference-type bridge that lets submit logic synchronously read
/// the UITextView's current text without requiring per-keystroke binding writes.
/// Assign a `TextInputRelay` instance to `ListAwareTextField.relay`; call
/// `relay.currentText()` just before submitting to get the latest typed value.
final class TextInputRelay {
    var currentText: () -> String = { "" }
    /// Replaces the entire buffer (e.g. inserting a picked slash command) and moves
    /// the caret to the end, without blurring the field. Callers are responsible for
    /// any follow-up state updates (placeholder emptiness, text-change bubbling).
    var replaceAll: (String) -> Void = { _ in }
    /// Moves keyboard focus into the underlying text view.
    var focus: () -> Void = {}
}

// MARK: - ListAwareTextField

/// A UITextView-backed text input that:
/// 1. Does NOT write to the SwiftUI binding on every keystroke — text stays in the
///    UITextView's own buffer, so `onChange(of: activeBranches)` never fires while
///    typing (eliminating the primary source of typing lag).
/// 2. Intercepts the Return key (via UITextViewDelegate.shouldChangeTextIn) to
///    submit when `onSubmit` is provided, otherwise auto-continue ordered lists
///    ("1. ") and unordered lists ("- ") at UIKit speed, with zero SwiftUI overhead.
/// 3. Flushes text → binding when `submitTrigger` increments (the dock arrow button).
/// 4. Flushes text → binding on blur (textViewDidEndEditing).
struct ListAwareTextField: UIViewRepresentable {

    // MARK: - Public API

    @Binding var text: String
    var placeholder: String = ""
    var font: UIFont = UIFont(name: "LibreBaskerville-Regular", size: 16) ?? .systemFont(ofSize: 16)
    var lineHeight: CGFloat? = nil
    var isLocked: Bool = false
    var textColor: UIColor = .aquinasPrimaryReadable
    var textAlignment: NSTextAlignment = .natural
    var onFocusChange: (Bool) -> Void = { _ in }
    /// Optional relay that exposes the UITextView's live text for synchronous
    /// reads at submit time (avoids per-keystroke binding writes).
    var relay: TextInputRelay? = nil
    /// Called every time the text changes (for placeholder visibility etc.).
    var onTextChange: ((String) -> Void)? = nil
    /// Called when Return should submit the current question instead of inserting a newline.
    var onSubmit: (() -> Void)? = nil

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = font
        tv.textColor = textColor
        tv.tintColor = textColor
        tv.textAlignment = textAlignment
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.showsVerticalScrollIndicator = false
        tv.showsHorizontalScrollIndicator = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.autocorrectionType = .yes
        tv.autocapitalizationType = .sentences
        tv.returnKeyType = onSubmit == nil ? .default : .send
        tv.typingAttributes = makeTypingAttributes()
        tv.attributedText = NSAttributedString(
            string: text,
            attributes: makeTypingAttributes()
        )
        // Allow SwiftUI to compress the view horizontally — without this the
        // UITextView demands its ideal (unbounded) width and stretches the layout.
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        relay?.currentText = { [weak tv] in tv?.text ?? "" }
        relay?.replaceAll = { [weak tv] newText in
            guard let tv else { return }
            tv.text = newText
            let end = tv.endOfDocument
            tv.selectedTextRange = tv.textRange(from: end, to: end)
            tv.invalidateIntrinsicContentSize()
        }
        relay?.focus = { [weak tv] in
            guard let tv else { return }
            tv.becomeFirstResponder()
            let end = tv.endOfDocument
            tv.selectedTextRange = tv.textRange(from: end, to: end)
        }
        return tv
    }

    private func makeTypingAttributes() -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        if let lineHeight {
            style.minimumLineHeight = lineHeight
            style.maximumLineHeight = lineHeight
        } else {
            style.lineSpacing = font.lineHeight * 0.2
        }
        style.alignment = textAlignment
        return [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: style
        ]
    }

    /// Tell SwiftUI exactly how tall the view needs to be for the available width.
    /// Without this, SwiftUI never constrains the width and the text never wraps.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let fittingSize = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(fittingSize.height, uiView.font?.lineHeight ?? 20))
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // Keep coordinator's parent reference current every render.
        context.coordinator.parent = self

        // Always safe to update visual properties
        if uiView.font != font { uiView.font = font }
        if uiView.textColor != textColor { uiView.textColor = textColor }
        if uiView.tintColor != textColor { uiView.tintColor = textColor }
        if uiView.backgroundColor != .clear { uiView.backgroundColor = .clear }
        if uiView.textAlignment != textAlignment {
            UIView.transition(
                with: uiView,
                duration: 0.18,
                options: [.transitionCrossDissolve, .allowUserInteraction]
            ) {
                uiView.textAlignment = textAlignment
            }
        }
        if uiView.isEditable == isLocked {
            uiView.isEditable   = !isLocked
            uiView.isSelectable = !isLocked
        }
        if !isLocked {
            let attributes = makeTypingAttributes()
            uiView.typingAttributes = attributes
            if !uiView.textStorage.string.isEmpty,
               let paragraphStyle = attributes[.paragraphStyle] {
                uiView.textStorage.addAttribute(
                    .paragraphStyle,
                    value: paragraphStyle,
                    range: NSRange(location: 0, length: uiView.textStorage.length)
                )
            }
        }
        let returnKeyType: UIReturnKeyType = onSubmit == nil ? .default : .send
        if uiView.returnKeyType != returnKeyType {
            uiView.returnKeyType = returnKeyType
            uiView.reloadInputViews()
        }

        // Sync binding → UITextView only when NOT focused.
        // While focused the UITextView is authoritative (textViewDidChange
        // writes every keystroke to the binding directly).
        if !uiView.isFirstResponder {
            let bindingText = text
            if (uiView.text ?? "") != bindingText {
                if bindingText.isEmpty {
                    uiView.text = ""
                } else {
                    uiView.attributedText = NSAttributedString(string: bindingText, attributes: makeTypingAttributes())
                }
            }
        }
        // Refresh relay so it always points at the live UITextView.
        relay?.currentText = { [weak uiView] in uiView?.text ?? "" }
        relay?.replaceAll = { [weak uiView] newText in
            guard let uiView else { return }
            uiView.text = newText
            let end = uiView.endOfDocument
            uiView.selectedTextRange = uiView.textRange(from: end, to: end)
            uiView.invalidateIntrinsicContentSize()
        }
        relay?.focus = { [weak uiView] in
            guard let uiView else { return }
            uiView.becomeFirstResponder()
            let end = uiView.endOfDocument
            uiView.selectedTextRange = uiView.textRange(from: end, to: end)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    // MARK: - Coordinator

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: ListAwareTextField

        // Compiled once per Coordinator instance (effectively once per field lifetime)
        private let orderedListPattern  = try! NSRegularExpression(pattern: #"^(\d+)\.\s+\S"#)
        private let orderedEmptyPattern = try! NSRegularExpression(pattern: #"^(\d+)\.\s*$"#)
        private let unorderedListPattern  = try! NSRegularExpression(pattern: #"^-\s+\S"#)
        private let unorderedEmptyPattern = try! NSRegularExpression(pattern: #"^-\s*$"#)

        init(parent: ListAwareTextField) {
            self.parent = parent
        }

        // MARK: - Return-key list interception

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n" else { return true }
            if let onSubmit = parent.onSubmit, !parent.isLocked {
                flushText(tv)
                parent.onTextChange?(tv.text ?? "")
                onSubmit()
                return false
            }
            guard let fullText = tv.text else { return true }

            let nsText = fullText as NSString
            let cursorPos = range.location

            // Find the current line (from its start up to the cursor)
            let lineRange = nsText.lineRange(for: NSRange(location: cursorPos, length: 0))
            let lineEnd = min(cursorPos, lineRange.location + lineRange.length)
            let currentLine = nsText.substring(with: NSRange(location: lineRange.location,
                                                              length: lineEnd - lineRange.location))

            let fullRange = NSRange(currentLine.startIndex..., in: currentLine)

            // ── Ordered list ──────────────────────────────────────────────────
            if let m = orderedListPattern.firstMatch(in: currentLine, range: fullRange),
               let numRange = Range(m.range(at: 1), in: currentLine),
               let num = Int(currentLine[numRange]) {
                let insertion = "\n\(num + 1). "
                insertText(tv, in: range, text: insertion)
                return false
            }

            // ── Ordered empty item (exit list) ────────────────────────────────
            if orderedEmptyPattern.firstMatch(in: currentLine, range: fullRange) != nil {
                // Strip "N. " from the current line up to cursor, insert plain newline
                let strippedPrefixLen = lineEnd - lineRange.location
                let stripRange = NSRange(location: lineRange.location, length: strippedPrefixLen)
                replaceText(tv, in: stripRange, with: "")
                return false
            }

            // ── Unordered list ────────────────────────────────────────────────
            if unorderedListPattern.firstMatch(in: currentLine, range: fullRange) != nil {
                insertText(tv, in: range, text: "\n- ")
                return false
            }

            // ── Unordered empty item (exit list) ──────────────────────────────
            if unorderedEmptyPattern.firstMatch(in: currentLine, range: fullRange) != nil {
                let stripRange = NSRange(location: lineRange.location, length: lineEnd - lineRange.location)
                replaceText(tv, in: stripRange, with: "\n")
                return false
            }

            return true
        }

        // MARK: - Helpers

        private func insertText(_ tv: UITextView, in range: NSRange, text: String) {
            guard let textRange = tv.textRange(from: range, in: tv) else {
                // Fallback: just append
                tv.insertText(text)
                return
            }
            tv.replace(textRange, withText: text)
            notifyChange(tv)
        }

        private func replaceText(_ tv: UITextView, in range: NSRange, with text: String) {
            guard let textRange = tv.textRange(from: range, in: tv) else { return }
            tv.replace(textRange, withText: text)
            notifyChange(tv)
        }

        private func notifyChange(_ tv: UITextView) {
            parent.onTextChange?(tv.text ?? "")
        }

        // MARK: - UITextViewDelegate

        func textViewDidChange(_ tv: UITextView) {
            let current = tv.text ?? ""
            // Do NOT write to parent.text here — doing so mutates activeBranches on
            // every keystroke, which triggers an ActiveInquiryView re-render, which
            // re-creates every StreamingMessageView (parseSegments + regex) per character.
            // Text is flushed to the binding in textViewDidEndEditing (blur) and via
            // the relay at submit time, so nothing is lost.
            parent.onTextChange?(current)
            // Invalidate SwiftUI's size cache so sizeThatFits is re-evaluated
            // and the view grows/shrinks vertically as lines wrap.
            tv.invalidateIntrinsicContentSize()
        }

        func textViewShouldEndEditing(_ tv: UITextView) -> Bool {
            flushText(tv)
            return true
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            // Flush once when focus leaves, then re-sync placeholder visibility with
            // the final UIKit buffer in case no change event fired during blur.
            flushText(tv)
            parent.onTextChange?(tv.text ?? "")
            parent.onFocusChange(false)
        }

        func textViewDidBeginEditing(_ tv: UITextView) {
            parent.onFocusChange(true)
        }

        private func flushText(_ tv: UITextView) {
            parent.text = tv.text ?? ""
        }
    }
}

// MARK: - Convenience extensions for Aquinas types

extension ConversationFontOption {
    var uiFont: UIFont {
        uiFont(size: .large)
    }

    func uiFont(size: ConversationFontSizeOption) -> UIFont {
        uiFont(pointSize: size.pointSize)
    }

    func uiFont(pointSize: CGFloat) -> UIFont {
        switch self {
        case .serif:
            return UIFont(name: "LibreBaskerville-Regular", size: pointSize) ?? .systemFont(ofSize: pointSize)
        case .sans:
            return UIFont(name: "Figtree-Regular", size: pointSize) ?? .systemFont(ofSize: pointSize)
        }
    }
}

extension InputTextAlignmentOption {
    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .center: return .center
        case .left:   return .natural
        }
    }
}

// MARK: - NSRange ↔ UITextRange helper

private extension UITextView {
    /// Converts an NSRange in the text view's string to a UITextRange.
    func textRange(from nsRange: NSRange, in textView: UITextView) -> UITextRange? {
        guard let start = textView.position(from: textView.beginningOfDocument, offset: nsRange.location),
              let end   = textView.position(from: start, offset: nsRange.length) else { return nil }
        return textView.textRange(from: start, to: end)
    }
}
