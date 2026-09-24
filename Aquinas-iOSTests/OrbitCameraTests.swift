import CoreGraphics
import Foundation
import Testing
import simd
@testable import Aquinas_iOS

@Suite("Orbit Camera")
struct OrbitCameraTests {
    /// The tree canvas's pipeline for a world point centered at `target`: top-down pan/zoom to a
    /// flat point, then the plane projection with its focal length scaled by zoom.
    private func treeProjection(
        _ point: SIMD3<Double>, target: SIMD3<Double>, pitch: CGFloat, zoom: CGFloat
    ) -> PerspectivePlaneProjection.Point {
        let center = CGPoint(x: 200, y: 420)
        let flat = CGPoint(
            x: center.x + CGFloat(point.x - target.x) * zoom,
            y: center.y - CGFloat(point.y - target.y) * zoom
        )
        return PerspectivePlaneProjection(pitch: pitch, focalLength: 600 * zoom, principalPoint: center)
            .project(flat: flat, elevation: CGFloat(point.z) * zoom)
    }

    @Test("With no yaw, the orbit camera reproduces the tree's projection at any pitch and zoom")
    func orbitCameraMatchesTree() throws {
        let target = SIMD3<Double>(40, -25, 0)
        let points: [SIMD3<Double>] = [[40, -25, 0], [180, 60, 90], [-90, -140, -70], [10, 200, 45]]
        for pitch in [0, CGFloat.pi * 34 / 180] {
            for zoom in [CGFloat(0.5), 1.15, 2.2] {
                let camera = OrbitCamera(
                    target: target, pitch: Double(pitch), distance: 600, zoom: Double(zoom),
                    principalPoint: CGPoint(x: 200, y: 420)
                )
                for point in points {
                    let orbit = try #require(camera.project(point))
                    let tree = treeProjection(point, target: target, pitch: pitch, zoom: zoom)
                    #expect(abs(orbit.position.x - tree.position.x) < 1e-6)
                    #expect(abs(orbit.position.y - tree.position.y) < 1e-6)
                    #expect(abs(orbit.scale - Double(tree.scale)) < 1e-9)
                }
            }
        }
    }

    @Test("Orbiting keeps the target centered and hides points behind the eye")
    func orbitingKeepsTargetCentered() {
        var camera = OrbitCamera(
            target: [5, 5, 0], distance: 600, zoom: 1, principalPoint: CGPoint(x: 200, y: 420)
        )
        for (yaw, pitch) in [(0.0, 0.0), (0.8, 0.3), (-2.1, 1.2)] {
            camera.yaw = yaw
            camera.pitch = pitch
            let center = camera.project(camera.target)
            #expect(center?.position == camera.principalPoint)
            #expect(center?.scale == 1)
        }
        camera.yaw = 0
        camera.pitch = 0
        #expect(camera.project([5, 5, 700]) == nil)
    }
}

extension OrbitCameraTests {
    @Test("Moving the rotation center with the compensating target keeps every point in place")
    func rotationCenterMoveKeepsView() throws {
        var camera = OrbitCamera(
            target: [30, 10, 40], yaw: 0.9, pitch: 1.2, distance: 900, zoom: 1.3,
            principalPoint: CGPoint(x: 200, y: 400)
        )
        camera.rotationCenter = [30, 10, 40]
        let before = camera
        let newCenter = SIMD3<Double>(-60, 120, 0)
        camera.target = before.target(keepingViewWhenCenterMovesFrom: [30, 10, 40], to: newCenter)
        camera.rotationCenter = newCenter
        for point: SIMD3<Double> in [[0, 0, 0], [150, -40, 90], [-200, 300, -60]] {
            let a = try #require(before.project(point)), b = try #require(camera.project(point))
            #expect(abs(a.position.x - b.position.x) < 1e-6)
            #expect(abs(a.position.y - b.position.y) < 1e-6)
        }
    }
}
