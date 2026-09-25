//
//  BranchModeTopBar.swift
//  Aquinas-iOS
//

import SwiftUI

struct BranchModeTopBar: View {
    let isCanvasMode: Bool
    let title: String
    let titleOpacity: Double
    let insightTreeUpdateSignal: Int
    @Binding var isEditingTitle: Bool
    @Binding var titleDraft: String
    let conversationFontSize: ConversationFontSizeOption
    var isInStudyTopic: Bool = false
    /// In Study the canvas's Back becomes the side-menu button with an Exit beside it.
    var isStudyMode: Bool = false
    var onMenuTap: () -> Void
    var onCanvasTap: () -> Void
    var onBackTap: () -> Void
    var onCommitTitle: (String) -> Void = { _ in }
    var onTapStudyTopicBadge: () -> Void = {}
    @Namespace private var titleNamespace
    @FocusState private var titleFieldFocused: Bool

    private var titleFontSize: CGFloat {
        switch conversationFontSize {
        case .large:  return 17
        case .medium: return 16
        case .small:  return 15
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Normal mode layout
            HStack(spacing: 0) {
                AquinasNavButton(onMenuTap: onMenuTap)
                    .frame(width: 88, alignment: .leading)
                Spacer(minLength: 8)
                Group {
                    if isEditingTitle {
                        TextField("Conversation title", text: $titleDraft)
                            .font(.custom("LibreBaskerville-Regular", size: titleFontSize))
                            .multilineTextAlignment(.center)
                            .foregroundColor(AquinasTheme.Colors.primaryReadable)
                            .focused($titleFieldFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                isEditingTitle = false
                                onCommitTitle(titleDraft)
                            }
                    } else if isInStudyTopic {
                        HStack(spacing: 4) {
                            Image(systemName: "square.stack")
                                .font(.system(size: titleFontSize - 3, weight: .medium))
                                .foregroundColor(AquinasTheme.Colors.lightGreen)
                            Text(title)
                                .font(.custom("LibreBaskerville-Regular", size: titleFontSize))
                                .foregroundColor(AquinasTheme.Colors.primaryReadable)
                                .lineLimit(1)
                        }
                        .id(title)
                        .transition(.blurredTitleReplacement)
                        .onTapGesture(perform: onTapStudyTopicBadge)
                    } else {
                        Text(title)
                            .font(.custom("LibreBaskerville-Regular", size: titleFontSize))
                            .foregroundColor(AquinasTheme.Colors.primaryReadable)
                            .lineLimit(1)
                            .id(title)
                            .transition(.blurredTitleReplacement)
                            .onTapGesture {
                                titleDraft = title
                                isEditingTitle = true
                                titleFieldFocused = true
                            }
                    }
                }
                .frame(maxWidth: .infinity)
                .opacity(titleOpacity)
                .animation(.easeOut(duration: 0.22), value: title)
                Spacer(minLength: 8)
                CanvasModeToggleButton(
                    isActive: false,
                    updateSignal: insightTreeUpdateSignal,
                    action: onCanvasTap
                )
                    .matchedGeometryEffect(id: "canvasModeButton", in: titleNamespace, isSource: !isCanvasMode)
                    .frame(width: 88, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .opacity(isCanvasMode ? 0 : 1)
            .offset(x: isCanvasMode ? -96 : 0)
            .allowsHitTesting(!isCanvasMode)

            // Canvas mode layout
            HStack(spacing: 8) {
                if isStudyMode {
                    AquinasNavButton(onMenuTap: onMenuTap)
                        .transition(.blurFade)
                    StudyExitButton(action: onBackTap)
                        .transition(.studyExitGrow)
                } else {
                    CanvasModeToggleButton(
                        isActive: true,
                        updateSignal: insightTreeUpdateSignal,
                        action: onBackTap
                    )
                        .matchedGeometryEffect(id: "canvasModeButton", in: titleNamespace, isSource: isCanvasMode)
                        .opacity(isCanvasMode ? 1 : 0)
                }
                Spacer()
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.84), value: isStudyMode)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .allowsHitTesting(isCanvasMode)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
