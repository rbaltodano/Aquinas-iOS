//
//  PageModelControls.swift
//  Aquinas-iOS
//

import SwiftUI
import UIKit

/// Compact global controls for non-conversation pages. Idle model status stays out of the way
/// here; it returns whenever the shared queue becomes active. Page-specific actions remain.
struct PageModelControls: View {
    let modelTasks: ModelTaskQueue
    let popupState: ModelTasksPopupState
    var alwaysShowModelStatus: Bool = false
    var actionTitle: String? = nil
    var secondaryActionTitle: String? = nil
    var secondaryAction: () -> Void = {}
    var confirmationTitle: String? = nil
    var onConfirm: () -> Void = {}
    var onDecline: () -> Void = {}
    var action: () -> Void = {}

    @State private var isControlButtonPressed = false
    @AppStorage(SettingsStorageKey.modelActivityDisplay)
    private var activityDisplay: ModelActivityDisplayOption = .detailed

    private var showsModelStatus: Bool {
        (alwaysShowModelStatus || modelTasks.isBusy) && activityDisplay != .hidden
    }

    private var showsControlPill: Bool {
        showsModelStatus || actionTitle != nil || secondaryActionTitle != nil
    }

    private var controlLayoutKey: String {
        let taskKey = modelTasks.isBusy
            ? "\(modelTasks.currentPosition)/\(modelTasks.totalCount)"
            : "idle"
        return "\(taskKey)|\(actionTitle ?? "")|\(secondaryActionTitle ?? "")"
    }

    var body: some View {
        ModelControlsStack(
            modelTasksPopupState: popupState,
            modelTasks: modelTasks,
            confirmationTitle: confirmationTitle,
            onConfirm: onConfirm,
            onDecline: onDecline,
            controlsUpdateKey: controlLayoutKey
        ) {
            if showsControlPill {
                HStack(
                    alignment: .center,
                    spacing: secondaryActionTitle == nil ? 24 : 16
                ) {
                    if showsModelStatus {
                        ModelStatusButton(
                            modelTasks: modelTasks,
                            action: toggleModelTasksPopup,
                            controlIsPressed: $isControlButtonPressed
                        )
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }

                    if let actionTitle {
                        PageModelControlActionButton(
                            title: actionTitle,
                            controlIsPressed: $isControlButtonPressed,
                            action: action
                        )
                    }

                    if let secondaryActionTitle {
                        PageModelControlActionButton(
                            title: secondaryActionTitle,
                            controlIsPressed: $isControlButtonPressed,
                            action: secondaryAction
                        )
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, secondaryActionTitle == nil ? 32 : 24)
                .padding(.vertical, 24)
                .fixedSize(horizontal: true, vertical: true)
                .background(AquinasTheme.Colors.canvasSecondary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1))
                .modifier(FloatingControlPressFeedback(isButtonPressed: isControlButtonPressed))
                .transition(.scale(scale: 0.4).combined(with: .opacity))
                .animation(.spring(response: 0.38, dampingFraction: 0.78), value: controlLayoutKey)
            }
        }
        .padding(.bottom, 24)
        .background(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: AquinasTheme.Colors.canvas.opacity(0.95), location: 0),
                    .init(color: AquinasTheme.Colors.canvas.opacity(0), location: 1)
                ],
                startPoint: UnitPoint(x: 0.5, y: 0.52),
                endPoint: UnitPoint(x: 0.5, y: 0)
            )
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
        .onChange(of: modelTasks.isBusy) { _, isBusy in
            guard !isBusy else { return }
            popupState.reset()
        }
    }

    private func toggleModelTasksPopup() {
        if !popupState.isOpen {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred(intensity: 0.65)
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            popupState.isOpen.toggle()
        }
    }
}

/// Reader-specific controls surface the shared Model Status button only while work is active,
/// allowing a document table of contents to occupy the same expanding dock position.
struct LibraryModelControls<Contents: View>: View {
    let modelTasks: ModelTaskQueue
    let modelTasksPopupState: ModelTasksPopupState
    @Binding var isContentsOpen: Bool
    var previousChapterTitle: String? = nil
    var nextChapterTitle: String? = nil
    var onPreviousChapter: () -> Void = {}
    var onNextChapter: () -> Void = {}
    let contents: Contents
    @State private var isControlButtonPressed = false

    init(
        modelTasks: ModelTaskQueue,
        modelTasksPopupState: ModelTasksPopupState,
        isContentsOpen: Binding<Bool>,
        previousChapterTitle: String? = nil,
        nextChapterTitle: String? = nil,
        onPreviousChapter: @escaping () -> Void = {},
        onNextChapter: @escaping () -> Void = {},
        @ViewBuilder contents: () -> Contents
    ) {
        self.modelTasks = modelTasks
        self.modelTasksPopupState = modelTasksPopupState
        _isContentsOpen = isContentsOpen
        self.previousChapterTitle = previousChapterTitle
        self.nextChapterTitle = nextChapterTitle
        self.onPreviousChapter = onPreviousChapter
        self.onNextChapter = onNextChapter
        self.contents = contents()
    }

    var body: some View {
        ModelControlsStack(
            modelTasksPopupState: modelTasksPopupState,
            modelTasks: modelTasks,
            supplementalPopupIsOpen: isContentsOpen,
            supplementalPopup: AnyView(contents),
            controlsUpdateKey: controlLayoutKey
        ) {
            HStack(spacing: 24) {
                if let previousChapterTitle {
                    ReaderChapterControlButton(
                        title: previousChapterTitle,
                        icon: "chevron.left",
                        iconFirst: true,
                        action: onPreviousChapter
                    )
                    .id(previousChapterTitle)
                        .transition(.blurFade)
                }

                if modelTasks.isBusy {
                    ModelStatusButton(
                        modelTasks: modelTasks,
                        action: toggleModelTasks,
                        controlIsPressed: $isControlButtonPressed
                    )
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                }

                Button(action: toggleContents) {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Contents")
                            .font(.custom("Figtree-SemiBold", size: 14))
                    }
                    .foregroundStyle(AquinasTheme.Colors.paragraphText)
                    .frame(minHeight: 21)
                }
                .buttonStyle(FloatingControlButtonStyle(isPressed: $isControlButtonPressed))

                if let nextChapterTitle {
                    ReaderChapterControlButton(
                        title: nextChapterTitle,
                        icon: "chevron.right",
                        iconFirst: false,
                        action: onNextChapter
                    )
                    .id(nextChapterTitle)
                        .transition(.blurFade)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .fixedSize(horizontal: true, vertical: true)
            .background(AquinasTheme.Colors.canvasSecondary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1))
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: controlLayoutKey)
        }
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            LinearGradient(
                colors: [AquinasTheme.Colors.canvas.opacity(0.95), AquinasTheme.Colors.canvas.opacity(0)],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 300)
                .allowsHitTesting(false)
        }
        .onChange(of: modelTasks.isBusy) { _, isBusy in
            if !isBusy {
                modelTasksPopupState.reset()
            }
        }
    }

    private func toggleModelTasks() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            isContentsOpen = false
            modelTasksPopupState.isOpen.toggle()
        }
    }

    private func toggleContents() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            modelTasksPopupState.isOpen = false
            isContentsOpen.toggle()
        }
    }

    private var controlLayoutKey: String {
        let taskKey = modelTasks.isBusy
            ? "\(modelTasks.currentPosition)/\(modelTasks.totalCount)"
            : "idle"
        return "\(previousChapterTitle ?? "")|\(nextChapterTitle ?? "")|\(taskKey)"
    }

}

private struct ReaderChapterControlButton: View {
    let title: String
    let icon: String
    let iconFirst: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if iconFirst { iconView }
                Text(title)
                if !iconFirst { iconView }
            }
            .font(.custom("Figtree-SemiBold", size: 14))
            .foregroundStyle(AquinasTheme.Colors.lightGreen)
            .frame(minHeight: 21)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var iconView: some View {
        Image(systemName: icon)
            .font(.system(size: 11, weight: .semibold))
            .sfSymbolDrawOn()
    }
}

private struct PageModelControlActionButton: View {
    let title: String
    @Binding var controlIsPressed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16, height: 16)

                Text(title)
                    .font(.custom("Figtree-SemiBold", size: 14))
                    .contentTransition(.opacity)
            }
            .foregroundColor(AquinasTheme.Colors.lightGreen)
            .frame(minHeight: 21)
            .contentShape(Rectangle())
        }
        .buttonStyle(FloatingControlButtonStyle(isPressed: $controlIsPressed))
        .accessibilityLabel(title)
    }
}
