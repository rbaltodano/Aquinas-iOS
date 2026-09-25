//
//  CanvasModeModel.swift
//  Aquinas-iOS
//
//  Canvas Mode state for CurrentConversationView, extracted from the view's
//  @State so the conversation screen owns a smaller, focused set of properties.
//
//  Held as `@State private var canvasMode = CanvasModeModel()` in the view.
//  Because it is @Observable, only views that read a specific property are
//  invalidated when that property changes, and `$canvasMode.x` still yields a
//  Binding for passing into ConversationTopicCanvasView and the control dock.
//

import Foundation
import Observation

@Observable
final class CanvasModeModel {
    /// Whether the topic canvas overlay is currently presented.
    var isTopicCanvasVisible: Bool = false
    var hasCanvasHover: Bool = false
    var hasHoveredCanvasInsight: Bool = false

    /// Concept the user chose to quote out of the canvas.
    var canvasQuoteTarget: ConceptDefinition? = nil
    var canvasSelectedItemCount: Int = 0

    // Request counters — incremented by the view to fire one-shot actions in the canvas.
    var canvasSelectionRequest: Int = 0
    var canvasClearSelectionRequest: Int = 0
    var canvasDismissHoverRequest: Int = 0
    var canvasCreateConceptRequest: Int = 0
    /// Opens the focused Insight in the single-concept Study experience.
    var canvasStudyRequest: Int = 0
    /// Returns Study to its selected Insight without leaving the tree.
    var canvasStudyExitRequest: Int = 0
    var isCanvasStudyMode: Bool = false
    /// The dock's Tools button toggles Study's tools; the tree reports whether they're open.
    var canvasStudyToolsToggleRequest: Int = 0
    var isCanvasStudyToolsActive: Bool = false
    var canvasStudyBranchCount: Int = 2
    var canvasInquireConnectionRequest: Int = 0

    /// The concepts selected for a connection inquiry.
    var canvasConnectionConcepts: [ConceptDefinition]? = nil

    // Midpoint placement flow.
    var canvasMidpointEnterRequest: Int = 0
    var canvasMidpointCenterRequest: Int = 0
    var canvasMidpointPlaceRequest: Int = 0
    var isCanvasMidpointMode: Bool = false
    /// True while a just-placed midpoint insight is "generating" (loading on the canvas).
    var isCanvasInsightGenerating: Bool = false

    // Search flow.
    var isCanvasSearchActive: Bool = false
    var canvasSearchQuery: String = ""
    var canvasSearchResultIndex: Int = 0
    var canvasSearchResultCount: Int = 0
    var canvasSearchPreviousRequest: Int = 0
    var canvasSearchNextRequest: Int = 0

    /// Insight IDs the user promoted from the canvas into the conversation.
    var promotedCanvasInsightIDs: [UUID] = []
}
