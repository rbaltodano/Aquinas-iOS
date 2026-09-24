//
//  PerspectivePlaneProjection.swift
//  Aquinas-iOS
//

import CoreGraphics

/// A pinhole camera pitched down onto a flat plane, for 2.5D canvases.
///
/// It operates on "flat" screen points — the ordinary top-down pan/zoom position — so a canvas
/// keeps its existing camera offset and scale and only routes final positions through here.
/// Flat points above the principal point lie farther from the camera and are foreshortened;
/// a positive elevation (in screen points) lifts a point off the plane toward the camera.
/// A pitch of zero is the identity, so shared views can opt in without changing behavior.
struct PerspectivePlaneProjection: Equatable {
    var pitch: CGFloat
    var focalLength: CGFloat
    var principalPoint: CGPoint

    struct Point: Equatable {
        let position: CGPoint
        /// Perspective magnification at this point: > 1 nearer the camera, < 1 farther away.
        let scale: CGFloat
    }

    /// Limits magnification for points far below the principal point (near/behind the camera).
    private static let maximumScale: CGFloat = 4

    func project(flat: CGPoint, elevation: CGFloat = 0) -> Point {
        let sine = sin(pitch)
        let cosine = cos(pitch)
        let u = flat.x - principalPoint.x
        let v = principalPoint.y - flat.y          // + = farther up the plane
        let depth = v * sine - elevation * cosine
        let scale = focalLength / max(focalLength + depth, focalLength / Self.maximumScale)
        return Point(
            position: CGPoint(
                x: principalPoint.x + u * scale,
                y: principalPoint.y - (v * cosine + elevation * sine) * scale
            ),
            scale: scale
        )
    }

    /// Inverse of `project` for a point known to sit at `elevation` (0 = on the plane).
    func unproject(_ screen: CGPoint, elevation: CGFloat = 0) -> CGPoint {
        let sine = sin(pitch)
        let cosine = cos(pitch)
        let x = screen.x - principalPoint.x
        let y = screen.y - principalPoint.y
        // y = -(v·cos + e·sin)·s,  s = f / (f + v·sin − e·cos)  →  solve for v.
        var denominator = y * sine + cosine * focalLength
        if abs(denominator) < 1e-3 { denominator = denominator < 0 ? -1e-3 : 1e-3 }  // horizon
        let v = (-elevation * sine * focalLength - y * focalLength + y * elevation * cosine) / denominator
        let depth = v * sine - elevation * cosine
        let scale = focalLength / max(focalLength + depth, focalLength / Self.maximumScale)
        return CGPoint(x: principalPoint.x + x / scale, y: principalPoint.y - v)
    }

    /// The flat point that places something at `elevation` exactly on the principal point.
    func flatPointCentering(elevation: CGFloat) -> CGPoint {
        CGPoint(x: principalPoint.x, y: principalPoint.y + elevation * tan(pitch))
    }
}
