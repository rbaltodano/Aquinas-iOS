//
//  OrbitCamera.swift
//  Aquinas-iOS
//

import CoreGraphics
import simd

/// A perspective camera orbiting a 3D target, for spatial views of the Insight Tree.
///
/// World axes: x to the right, y up the graph plane, z out of the plane toward an overhead
/// viewer. With `yaw` and `pitch` at zero the camera looks straight down z, which reproduces the
/// Insight Tree canvas's overhead perspective exactly; with a nonzero `pitch` it matches
/// `PerspectivePlaneProjection` at that pitch. So a spatial view can start from the tree's
/// current framing and rotate away from it without a jump.
struct OrbitCamera: Equatable {
    /// The world point that projects onto `principalPoint`.
    var target: SIMD3<Double>
    /// Rotation about the plane's normal, in radians.
    var yaw: Double = 0
    /// Tilt away from overhead, in radians. Positive tips the far (+y) side of the plane away.
    var pitch: Double = 0
    /// Eye distance from `target` along the view axis, in world units. Smaller = stronger depth.
    var distance: Double
    /// Screen points per world unit at the target's depth.
    var zoom: Double
    var principalPoint: CGPoint
    /// What `yaw` turns the world around (vertically through this point). Nil turns it around
    /// `target`, a true orbit. Separating them lets the axis move without moving the view.
    var rotationCenter: SIMD3<Double>? = nil

    struct Projection: Equatable {
        let position: CGPoint
        /// Perspective magnification relative to the target's depth: > 1 is nearer the eye.
        let scale: Double
        /// Distance in front of the eye along the view axis, for back-to-front ordering.
        let depth: Double
    }

    /// Screen position of a world point, or nil when it is at or behind the eye.
    func project(_ point: SIMD3<Double>) -> Projection? {
        let view = viewSpace(point)
        let depth = distance - view.z
        guard depth > 1e-6 else { return nil }
        let scale = distance / depth
        return Projection(
            position: CGPoint(
                x: principalPoint.x + view.x * scale * zoom,
                y: principalPoint.y - view.y * scale * zoom
            ),
            scale: scale,
            depth: depth
        )
    }

    /// The point relative to `target`, rotated into the camera's frame (z toward the eye).
    private func viewSpace(_ point: SIMD3<Double>) -> SIMD3<Double> {
        let center = rotationCenter ?? target
        let turned = Self.turn(point - center, by: yaw) + (center - target)
        let (pitchSine, pitchCosine) = (sin(pitch), cos(pitch))
        return SIMD3(
            turned.x,
            turned.y * pitchCosine + turned.z * pitchSine,
            -turned.y * pitchSine + turned.z * pitchCosine
        )
    }

    /// `offset` turned about the vertical axis the way `yaw` turns the world.
    static func turn(_ offset: SIMD3<Double>, by yaw: Double) -> SIMD3<Double> {
        let (yawSine, yawCosine) = (sin(yaw), cos(yaw))
        return SIMD3(
            offset.x * yawCosine + offset.y * yawSine,
            -offset.x * yawSine + offset.y * yawCosine,
            offset.z
        )
    }

    /// The target that keeps the view identical when the rotation center moves from
    /// `oldCenter` to `newCenter` at the current yaw.
    func target(keepingViewWhenCenterMovesFrom oldCenter: SIMD3<Double>, to newCenter: SIMD3<Double>) -> SIMD3<Double> {
        let delta = newCenter - oldCenter
        return target + delta - Self.turn(delta, by: yaw)
    }
}
