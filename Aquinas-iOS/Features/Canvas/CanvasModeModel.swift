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
    var canvasInquireConnectionRequest: Int = 0

    /// The two concepts selected for a connection inquiry.
    var canvasConnectionConcepts: (ConceptDefinition, ConceptDefinition)? = nil

    // Midpoint placement flow.
    var canvasMidpointEnterRequest: Int = 0
    var canvasMidpointCenterRequest: Int = 0
    var canvasMidpointPlaceRequest: Int = 0
    var isCanvasMidpointMode: Bool = false

    /// Insight IDs the user promoted from the canvas into the conversation.
    var promotedCanvasInsightIDs: [UUID] = []
}
