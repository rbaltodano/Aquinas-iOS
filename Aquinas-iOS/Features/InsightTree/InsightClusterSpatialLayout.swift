//
//  InsightClusterSpatialLayout.swift
//  Aquinas-iOS
//

import CoreGraphics
import Foundation

/// Local 3D placement for the Insights around their owning Node Concept.
///
/// Clusters are flat relative to each other: every Node Concept lies on the graph plane. Only a
/// cluster's own Insights leave it, each at an elevation angle within ±45° of the plane as seen
/// from its Node Concept, so none can sit over it. An Insight's height is its horizontal
/// distance from the Node Concept times the tangent of that angle, so the bound holds wherever
/// the Insight is, including while it is dragged.
///
/// Within a cluster, Insights spread as far apart in 3D as the ±45° band allows
/// (`elevationTargets`). This is purely geometric and identical for global and
/// per-conversation trees; up and down carry no meaning.
enum InsightClusterSpatialLayout {
    /// The hard guardrail for an Insight's elevation above or below the cluster plane.
    static let maximumElevationRadians: CGFloat = .pi / 4

    static func clampedElevationAngle(_ angle: CGFloat) -> CGFloat {
        min(max(angle, -maximumElevationRadians), maximumElevationRadians)
    }

    /// Height above (+) or below (−) the plane for an Insight at `angle`, `horizontalDistance`
    /// from its Node Concept.
    static func elevation(angle: CGFloat, horizontalDistance: CGFloat) -> CGFloat {
        max(horizontalDistance, 0) * tan(clampedElevationAngle(angle))
    }

    /// The elevation angle as a fraction of the guardrail, in [-1, 1].
    static func normalizedDepth(angle: CGFloat) -> CGFloat {
        clampedElevationAngle(angle) / maximumElevationRadians
    }

    struct Member: Equatable {
        let id: UUID
        /// Bond direction on the plane, in radians.
        let azimuth: Double
    }

    /// Elevation angles that put one cluster's Insights as far apart in 3D as the ±45° band
    /// allows: going around the Node Concept, neighbors alternate between the top and bottom of
    /// the band. With an odd count one Insight must break the alternation, so the lowest-ID one
    /// stays level and the two beside it take opposite sides. A lone Insight stays level.
    ///
    /// Only the order around the node and the IDs matter, never exact bond directions, so the
    /// same Insights in the same order get the same heights every time the tree opens, and
    /// bonds rotating past 0 never flip the cluster. Adding or removing an Insight, or dragging
    /// one past a neighbor, can reassign sides.
    static func elevationTargets(_ members: [Member]) -> [UUID: CGFloat] {
        guard members.count > 1 else {
            return members.first.map { [$0.id: 0] } ?? [:]
        }
        let ring = members.sorted { first, second in
            let a = normalizedAzimuth(first.azimuth), b = normalizedAzimuth(second.azimuth)
            return a != b ? a < b : first.id.uuidString < second.id.uuidString
        }
        let count = ring.count
        var start = 0
        var targets: [UUID: CGFloat] = [:]
        if count % 2 == 1 {
            let level = ring.indices.min { ring[$0].id.uuidString < ring[$1].id.uuidString } ?? 0
            targets[ring[level].id] = 0
            start = level + 1
        }
        let alternating = (0..<(count % 2 == 1 ? count - 1 : count)).map { ring[(start + $0) % count] }
        // The lowest-ID alternating Insight always goes up.
        let anchor = alternating.indices.min { alternating[$0].id.uuidString < alternating[$1].id.uuidString } ?? 0
        for (step, member) in alternating.enumerated() {
            let isUp = (step - anchor).isMultiple(of: 2)
            targets[member.id] = isUp ? maximumElevationRadians : -maximumElevationRadians
        }
        return targets
    }

    private static func normalizedAzimuth(_ azimuth: Double) -> Double {
        let value = azimuth.truncatingRemainder(dividingBy: 2 * .pi)
        return value < 0 ? value + 2 * .pi : value
    }
}
