//
//  InsightTreeSemanticPolicy.swift
//  Aquinas-iOS
//

import Foundation

/// Tunable semantic decisions, deliberately separate from visual distance mapping. Similarity is
/// cosine similarity in the bundled MiniLM space; it is not a probability.
enum InsightTreeSemanticPolicy {
    /// Matches the backend's current `DEFAULT_MEMBERSHIP_THRESHOLD` until a labeled conversation
    /// set provides a better calibrated value.
    static let membershipSimilarity = 0.40

    /// A conversation turn below this similarity to every existing subject seeds a new Node.
    /// Kept stricter than Insight membership so normal follow-ups do not grow duplicate subjects.
    static let newSubjectSimilarity = 0.60
}
