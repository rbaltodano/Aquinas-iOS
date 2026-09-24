//
//  StudyNodeLayout.swift
//  Aquinas-iOS
//

import Foundation
import simd

/// Geometry for studying one Node Concept in full 3D. In Study the tree's ±45° guardrail is
/// lifted: the Node Concept's Insights spread over a whole sphere around it, as far apart as
/// possible, starting from their directions in the tree so the move from tree to Study is
/// continuous and the result is the same every time for the same arrangement.
enum StudyNodeLayout {
    /// Unit directions that spread `starts` over the sphere, maximizing their separation
    /// (inverse-square repulsion, Thomson-style). Each result corresponds to the start at the
    /// same index. A single direction, or none, is returned unchanged.
    static func sphereSpread(
        from starts: [SIMD3<Double>],
        iterations: Int = 600
    ) -> [SIMD3<Double>] {
        guard starts.count > 1 else {
            return starts.map { simd_length($0) > 1e-9 ? simd_normalize($0) : SIMD3(1, 0, 0) }
        }
        var points = starts.enumerated().map { index, start in
            // A zero or duplicate start would give no direction to push; nudge it by index.
            let fallback = SIMD3<Double>(cos(Double(index)), sin(Double(index)), 0.3)
            guard simd_length(start) > 1e-9 else { return simd_normalize(fallback) }
            // A tree cluster is a perfectly alternating ring, symmetric enough to trap the
            // spread in a poor arrangement. A small, index-based nudge breaks the symmetry
            // without depending on anything random.
            let golden = Double(index) * 2.399963
            let nudge = SIMD3(cos(golden), sin(golden), cos(golden * 1.7)) * 0.08
            return simd_normalize(simd_normalize(start) + nudge)
        }
        for iteration in 0..<iterations {
            // A shrinking step settles smoothly instead of oscillating at equilibrium.
            let step = 0.1 * (1 - Double(iteration) / Double(iterations)) + 0.002
            var forces = [SIMD3<Double>](repeating: .zero, count: points.count)
            for i in points.indices {
                for j in points.indices where j > i {
                    var offset = points[i] - points[j]
                    var distanceSquared = simd_length_squared(offset)
                    if distanceSquared < 1e-8 {
                        // Coincident: separate deterministically along a tangent.
                        offset = simd_normalize(simd_cross(points[i], SIMD3(0.3, 0.5, 0.8)))
                        distanceSquared = 1e-4
                    }
                    let push = offset / (distanceSquared * distanceSquared.squareRoot())
                    forces[i] += push
                    forces[j] -= push
                }
            }
            for i in points.indices {
                // Only the tangential part moves a point along the sphere.
                let tangential = forces[i] - simd_dot(forces[i], points[i]) * points[i]
                let length = simd_length(tangential)
                guard length > 1e-12 else { continue }
                let moved = points[i] + tangential / length * min(length, 1) * step
                points[i] = simd_normalize(moved)
            }
        }
        return points
    }

    /// Spherical interpolation between two unit directions, `t` in 0...1.
    static func slerp(_ from: SIMD3<Double>, _ to: SIMD3<Double>, _ t: Double) -> SIMD3<Double> {
        let cosine = min(max(simd_dot(from, to), -1), 1)
        let angle = acos(cosine)
        guard angle > 1e-6 else { return simd_normalize(from + (to - from) * t) }
        if abs(angle - .pi) < 1e-6 {
            // Antipodal: any great circle works; go through a stable perpendicular.
            let axis = simd_normalize(simd_cross(from, abs(from.z) < 0.9 ? SIMD3(0, 0, 1) : SIMD3(1, 0, 0)))
            let half = t * .pi
            return simd_normalize(from * cos(half) + axis * sin(half))
        }
        let sine = sin(angle)
        return from * (sin((1 - t) * angle) / sine) + to * (sin(t * angle) / sine)
    }
}
