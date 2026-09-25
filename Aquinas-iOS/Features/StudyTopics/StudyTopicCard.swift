//
//  StudyTopicCard.swift
//  Aquinas-iOS
//

import SwiftUI

struct StudyTopicCard: View {
    let topic: StudyTopic
    let subItems: [InquiryConversation]
    var subItemTitle: (InquiryConversation) -> String
    var onSelect: () -> Void
    var onRename: () -> Void = {}
    var onDelete: () -> Void = {}
    var onSelectSubItem: (InquiryConversation) -> Void = { _ in }

    @State private var isExpanded = false
    @State private var isShowingLongPressFeedback = false

    private let longPressDuration: TimeInterval = 0.25

    private var visibleSubItems: [InquiryConversation] {
        isExpanded ? subItems : Array(subItems.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header: title + options button
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.stack")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AquinasTheme.Colors.lightGreen)

                        Text(displayTitle)
                            .font(.custom("Figtree-Bold", size: 18))
                            .foregroundColor(AquinasTheme.Colors.lightGreen)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .scaleEffect(isShowingLongPressFeedback ? 1.02 : 1, anchor: .leading)

                    Spacer(minLength: 8)

                    Menu {
                        Button("Rename", systemImage: "pencil.line") { onRename() }
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive) { onDelete() }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AquinasTheme.Colors.paragraphText)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .padding(11)
                    .contentShape(Rectangle())
                    .padding(-11)
                    .accessibilityLabel("Topic options")
                }

                if !displayDescription.isEmpty {
                    Text(displayDescription)
                        .font(.custom("Figtree-Regular", size: 14))
                        .foregroundColor(AquinasTheme.Colors.paragraphText)
                        .lineSpacing(4)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Sub-items: branch / question titles
            if !subItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleSubItems, id: \.id) { conversation in
                        Button(action: { onSelectSubItem(conversation) }) {
                            Text(subItemTitle(conversation))
                                .font(.custom("Figtree-Bold", size: 14))
                                .foregroundColor(AquinasTheme.Colors.headingText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .buttonStyle(.plain)
                    }

                    if subItems.count > 3 {
                        Button(action: {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                isExpanded.toggle()
                            }
                        }) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(AquinasTheme.Colors.lightGreen)
                                .frame(width: 34, height: 18)
                                .background(AquinasTheme.Colors.canvas.opacity(0.72))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AquinasTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .trim(from: 0, to: isShowingLongPressFeedback ? 1 : 0)
                .stroke(
                    AquinasTheme.Colors.border,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
                .opacity(isShowingLongPressFeedback ? 1 : 0)
                .padding(1)
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture(perform: onSelect)
        .onLongPressGesture(
            minimumDuration: longPressDuration,
            maximumDistance: 18,
            pressing: { isPressing in
                withAnimation(.linear(duration: isPressing ? longPressDuration : 0.12)) {
                    isShowingLongPressFeedback = isPressing
                }
            },
            perform: {}
        )
    }

    private var displayTitle: String {
        let trimmed = topic.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Study Topic" : trimmed
    }

    private var displayDescription: String {
        topic.description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
