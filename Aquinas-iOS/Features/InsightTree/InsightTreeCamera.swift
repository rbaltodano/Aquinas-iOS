//
//  InsightTreeCamera.swift
//  Aquinas-iOS
//

import SwiftUI
import Observation
import simd

@MainActor
@Observable
final class InsightTreeCanvasCameraState {
    var scale: CGFloat = 1
    var offset: CGSize = .zero
    var isDragging = false
    var lastDragEndedAt: Date = .distantPast
    var pinchStartScale: CGFloat?
    var pinchStartOffset: CGSize?
    var preFocusSnapshot: InsightTreeCameraSnapshot?
    var userMovedSincePlacement = false
}

struct InsightTreeCameraSnapshot {
    let scale: CGFloat
    let offset: CGSize
}

// MARK: - Camera Projection

struct InsightTreeCamera {
    var scale: CGFloat
    var offset: CGSize
    /// In Study, every projection goes through this camera instead of the tree's, so the whole
    /// canvas moves with it.
    var orbit: OrbitCamera? = nil
    /// The studied Node Concept, for ordering its Insights in front of or behind it.
    var studyNodeCenter: SIMD3<Double>? = nil

    /// The camera looks straight down, so the plane (grid, edges, Node Concepts) stays flat on
    /// screen while Insights above or below it get a faint perspective parallax.
    /// Camera height in world units: an Insight at the full 45° on a typical 190-unit bond sits
    /// 5% farther from screen center and pans 5% faster than the plane (190 · 1.05 / 0.05). It
    /// scales with zoom, so the parallax depends only on elevation. The Study view is where
    /// Insights are seen in full 3D.
    static let focalLength: CGFloat = 3990

    func projection(in size: CGSize) -> PerspectivePlaneProjection {
        PerspectivePlaneProjection(
            pitch: 0,
            focalLength: Self.focalLength * scale,
            principalPoint: CGPoint(x: size.width / 2, y: size.height / 2)
        )
    }

    /// The top-down pan/zoom position, before perspective.
    func flatPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width / 2 + point.x * scale + offset.width,
            y: size.height / 2 - point.y * scale + offset.height
        )
    }

    func world(fromFlat flat: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: (flat.x - size.width / 2 - offset.width) / scale,
            y: -(flat.y - size.height / 2 - offset.height) / scale
        )
    }

    /// Projects a world point at `elevation` world units above the graph plane.
    func project(_ point: CGPoint, elevation: CGFloat = 0, in size: CGSize) -> PerspectivePlaneProjection.Point {
        if let orbit {
            guard let projected = orbit.project(SIMD3(Double(point.x), Double(point.y), Double(elevation))) else {
                return PerspectivePlaneProjection.Point(position: CGPoint(x: -10_000, y: -10_000), scale: 0.01)
            }
            return PerspectivePlaneProjection.Point(position: projected.position, scale: CGFloat(projected.scale))
        }
        return projection(in: size).project(flat: flatPoint(point, in: size), elevation: elevation * scale)
    }

    /// The flat point that puts something at `elevation` exactly on screen center.
    func flatPointCentering(elevation: CGFloat, in size: CGSize) -> CGPoint {
        projection(in: size).flatPointCentering(elevation: elevation * scale)
    }

    func worldToScreen(_ point: CGPoint, in size: CGSize) -> CGPoint {
        project(point, in: size).position
    }

    /// This camera's current framing as an `OrbitCamera` (yaw and pitch zero), exactly.
    func currentOrbitCamera(in size: CGSize) -> OrbitCamera {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let target = world(fromFlat: center, in: size)
        return OrbitCamera(
            target: SIMD3(Double(target.x), Double(target.y), 0),
            distance: Double(Self.focalLength),
            zoom: Double(scale),
            principalPoint: center
        )
    }

    /// The world point under `point`, assuming it lies `elevation` world units above the plane.
    func screenToWorld(_ point: CGPoint, elevation: CGFloat = 0, in size: CGSize) -> CGPoint {
        world(fromFlat: projection(in: size).unproject(point, elevation: elevation * scale), in: size)
    }
}

/// Drives a per-frame tick from a `CADisplayLink`. The callback fires as a run-loop event
/// OUTSIDE SwiftUI body evaluation, so the sim can safely assign `@State` each frame (doing
/// that inside a `TimelineView` closure would be "modifying state during view update").
@MainActor
final class DisplayLinkDriver {
    private var link: CADisplayLink?
    var onTick: ((CFTimeInterval) -> Void)?

    private final class Proxy: NSObject {
        let fire: (CFTimeInterval) -> Void
        init(_ fire: @escaping (CFTimeInterval) -> Void) { self.fire = fire }
        @objc func step(_ link: CADisplayLink) { fire(link.timestamp) }
    }

    func start() {
        guard link == nil else { return }
        let proxy = Proxy { [weak self] ts in self?.onTick?(ts) }
        let l = CADisplayLink(target: proxy, selector: #selector(Proxy.step(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
    }
}
