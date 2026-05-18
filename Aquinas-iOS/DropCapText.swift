//
//  DropCapText.swift
//  Aquinas-iOS
//
//  Created by Ryan on 4/13/26.
//
import SwiftUI
import UIKit
import Foundation

// MARK: - Drop Cap Text

/// UIKit-backed text block that wraps paragraph text around a large decorative first letter.
struct DropCapText: UIViewRepresentable {
    var dropCap: String
    var bodyText: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = .zero

        // Drop-cap letter. Adjust size/color here if the editorial style changes.
        let dropCapLabel = UILabel()
        dropCapLabel.text = dropCap
        dropCapLabel.font = UIFont(name: "LibreBaskerville-Bold", size: 50)
        dropCapLabel.textColor = .aquinasAccent
        dropCapLabel.sizeToFit()

        // Slight upward offset aligns the cap with the paragraph's first line.
        dropCapLabel.frame = CGRect(x: 0, y: -8, width: dropCapLabel.frame.width, height: dropCapLabel.frame.height)
        textView.addSubview(dropCapLabel)

        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // Paragraph styling for the body text.
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 12

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.aquinasParagraphText,
            .paragraphStyle: paragraphStyle
        ]

        uiView.attributedText = NSAttributedString(string: bodyText, attributes: attributes)

        // Exclusion path reserves space so body text wraps around the drop cap.
        let tightBox = CGRect(x: 0, y: 0, width: 50, height: 50)
        uiView.textContainer.exclusionPaths = [UIBezierPath(rect: tightBox)]
    }

    // SwiftUI asks this for the exact height needed for the wrapped UIKit text.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 375

        let fittingSize = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        let exactSize = uiView.sizeThatFits(fittingSize)

        return CGSize(width: width, height: exactSize.height)
    }
}
