//
//  GlobalInsightsModelControls.swift
//  Aquinas-iOS
//

import SwiftUI

struct GlobalInsightsModelControls: View {
    @Binding var showFilePicker: Bool
    @Binding var showPhotoPicker: Bool
    @Binding var showCamera: Bool
    @Binding var selectedPersonality: String
    @Binding var isPersonalityMenuOpen: Bool
    let hasCanvasHover: Bool
    let hasCanvasInsightHover: Bool
    let hasSelectedCanvasItems: Bool
    let selectedCanvasItemCount: Int
    let isMidpointMode: Bool
    var isStudyMode: Bool = false
    var isStudyToolsActive: Bool = false
    var onToggleStudyTools: () -> Void = {}
    var studyBranchCount: Int = 2
    var onStudyBranchCountChange: (Int) -> Void = { _ in }
    let isCanvasInsightLoading: Bool
    let modelStatusOverride: String?
    let contextWordCount: Int
    let modelTasks: ModelTaskQueue
    let modelTasksPopupState: ModelTasksPopupState
    @Binding var searchText: String
    @Binding var isSearchActive: Bool
    let searchResultIndex: Int
    let searchResultCount: Int
    var onSelectCanvasItem: () -> Void
    var onCreateCanvasConcept: () -> Void
    var onStudyCanvasInsight: () -> Void
    var onInquireConnection: () -> Void
    var onQuoteCanvasItem: () -> Void
    let usesCanvasAskFlow: Bool
    let isCanvasAskMode: Bool
    var onAskInNewConversation: () -> Void
    var onAskInExistingConversation: () -> Void
    var onCancelCanvasAsk: () -> Void
    var onMidpointConcepts: () -> Void
    var onMidpointCenter: () -> Void
    var onMidpointPlace: () -> Void
    var onSearchPrevious: () -> Void
    var onSearchNext: () -> Void
    var onSearchActivated: () -> Void
    var onClearCanvasSelection: () -> Void
    var onContextWillOpen: () -> Void
    let confirmationTitle: String?
    var onConfirmUpdate: () -> Void
    var onDeclineUpdate: () -> Void
    let contextCard: ContextCardState

    var body: some View {
        InquiryControlDock(
            isCanvasMode: true,
            showFilePicker: $showFilePicker,
            showPhotoPicker: $showPhotoPicker,
            showCamera: $showCamera,
            selectedPersonality: $selectedPersonality,
            isPersonalityMenuOpen: $isPersonalityMenuOpen,
            isAtBottom: true,
            hasCanvasHover: hasCanvasHover,
            hasCanvasInsightHover: hasCanvasInsightHover,
            hasSelectedCanvasItems: hasSelectedCanvasItems,
            selectedCanvasItemCount: selectedCanvasItemCount,
            onScrollToBottom: {},
            onViewEntireCanvas: {},
            onOpenInsights: {},
            onSelectCanvasItem: onSelectCanvasItem,
            onCreateCanvasConcept: onCreateCanvasConcept,
            onStudyCanvasInsight: onStudyCanvasInsight,
            onInquireConnection: onInquireConnection,
            onQuoteCanvasItem: onQuoteCanvasItem,
            usesCanvasAskFlow: usesCanvasAskFlow,
            isCanvasAskMode: isCanvasAskMode,
            onAskInNewConversation: onAskInNewConversation,
            onAskInExistingConversation: onAskInExistingConversation,
            onCancelCanvasAsk: onCancelCanvasAsk,
            onMidpointConcepts: onMidpointConcepts,
            isMidpointMode: isMidpointMode,
            isStudyMode: isStudyMode,
            isStudyToolsActive: isStudyToolsActive,
            onToggleStudyTools: onToggleStudyTools,
            studyBranchCount: studyBranchCount,
            onStudyBranchCountChange: onStudyBranchCountChange,
            isCanvasInsightLoading: isCanvasInsightLoading,
            modelStatusOverride: modelStatusOverride,
            modelTasks: modelTasks,
            modelTasksPopupState: modelTasksPopupState,
            canvasSearchText: $searchText,
            isCanvasSearchActive: $isSearchActive,
            canvasSearchResultIndex: searchResultIndex,
            canvasSearchResultCount: searchResultCount,
            onCanvasSearchPrevious: onSearchPrevious,
            onCanvasSearchNext: onSearchNext,
            onCanvasSearchActivated: onSearchActivated,
            confirmationTitle: confirmationTitle,
            onConfirm: onConfirmUpdate,
            onDecline: onDeclineUpdate,
            onMidpointCenter: onMidpointCenter,
            onMidpointPlace: onMidpointPlace,
            onClearCanvasSelection: onClearCanvasSelection,
            contextWordCount: contextWordCount,
            showsContextWheel: false,
            onClearConversation: {},
            onContextWillOpen: onContextWillOpen,
            contextCard: contextCard
        )
    }
}
