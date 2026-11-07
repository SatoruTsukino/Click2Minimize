import CoreGraphics
import Foundation

// Pure geometry and gesture classification. No AppKit, no Accessibility:
// everything here is unit-tested by Tests/main.swift (run ./test_logic.sh).
// Coordinates are global screen coordinates with the origin at the top-left
// of the primary display and y growing downward (CGEvent / AX convention).

enum Direction8: Equatable {
    case right, upRight, up, upLeft, left, downLeft, down, downRight

    var isDiagonal: Bool { [.upRight, .upLeft, .downLeft, .downRight].contains(self) }
}

enum DragShape: Equatable {
    case none
    case line(Direction8)
    case circle(clockwise: Bool)
    case shakeHorizontal
    case shakeVertical
}

enum SnapZone: Equatable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case maximize

    /// Target frame inside a screen's visible frame (same y-down coordinates).
    func frame(in v: CGRect) -> CGRect {
        let w = (v.width / 2).rounded(), h = (v.height / 2).rounded()
        switch self {
        case .leftHalf: return CGRect(x: v.minX, y: v.minY, width: w, height: v.height)
        case .rightHalf: return CGRect(x: v.maxX - w, y: v.minY, width: w, height: v.height)
        case .topHalf: return CGRect(x: v.minX, y: v.minY, width: v.width, height: h)
        case .bottomHalf: return CGRect(x: v.minX, y: v.maxY - h, width: v.width, height: h)
        case .topLeft: return CGRect(x: v.minX, y: v.minY, width: w, height: h)
        case .topRight: return CGRect(x: v.maxX - w, y: v.minY, width: w, height: h)
        case .bottomLeft: return CGRect(x: v.minX, y: v.maxY - h, width: w, height: h)
        case .bottomRight: return CGRect(x: v.maxX - w, y: v.maxY - h, width: w, height: h)
        case .maximize: return v
        }
    }

    static func from(_ d: Direction8) -> SnapZone {
        switch d {
        case .left: return .leftHalf
        case .right: return .rightHalf
        case .up: return .maximize
        case .down: return .bottomHalf
        case .upLeft: return .topLeft
        case .upRight: return .topRight
        case .downLeft: return .bottomLeft
        case .downRight: return .bottomRight
        }
    }
}

enum GestureMath {
    static let minLineLength: CGFloat = 60

    /// 8-way direction of a vector in y-down coordinates.
    static func direction(of v: CGVector) -> Direction8 {
        // Flip y so that angles read like a maths circle (counter-clockwise, up positive).
        let angle = atan2(-v.dy, v.dx)
        let sector = Int(((angle + .pi * 2 + .pi / 8).truncatingRemainder(dividingBy: .pi * 2)) / (.pi / 4)) % 8
        return [.right, .upRight, .up, .upLeft, .left, .downLeft, .down, .downRight][sector]
    }

    static func pathLength(_ pts: [CGPoint]) -> CGFloat {
        zip(pts, pts.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    /// Direction of a path that is still a roughly straight line, else nil.
    static func lineDirection(_ pts: [CGPoint], minLength: CGFloat = minLineLength) -> Direction8? {
        guard let a = pts.first, let b = pts.last else { return nil }
        let net = hypot(b.x - a.x, b.y - a.y)
        guard net >= minLength else { return nil }
        let len = pathLength(pts)
        guard len > 0, net / len > 0.8 else { return nil }
        return direction(of: CGVector(dx: b.x - a.x, dy: b.y - a.y))
    }

    /// Classifies a completed right-drag path: circle, shake, straight line, or nothing.
    static func classify(_ pts: [CGPoint]) -> DragShape {
        guard pts.count >= 4 else { return .none }
        if let c = circle(pts) { return .circle(clockwise: c) }
        if let s = shake(pts) { return s }
        if let d = lineDirection(pts) { return .line(d) }
        return .none
    }

    /// Returns clockwise/counter-clockwise if the path sweeps most of a full turn
    /// around its centroid with a roughly constant radius.
    static func circle(_ pts: [CGPoint]) -> Bool? {
        let n = CGFloat(pts.count)
        let c = CGPoint(x: pts.map(\.x).reduce(0, +) / n, y: pts.map(\.y).reduce(0, +) / n)
        let radii = pts.map { hypot($0.x - c.x, $0.y - c.y) }
        let mean = radii.reduce(0, +) / n
        guard mean >= 25 else { return nil }
        let variance = radii.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / n
        guard sqrt(variance) / mean < 0.45 else { return nil }
        var swept: CGFloat = 0
        for (p, q) in zip(pts, pts.dropFirst()) {
            swept += normalizedAngle(atan2(q.y - c.y, q.x - c.x) - atan2(p.y - c.y, p.x - c.x))
        }
        guard abs(swept) >= .pi * 1.6 else { return nil }
        // In y-down coordinates a growing angle turns clockwise on screen.
        return swept > 0
    }

    /// Detects back-and-forth movement along one dominant axis.
    static func shake(_ pts: [CGPoint], minReversals: Int = 3, minAmplitude: CGFloat = 30) -> DragShape? {
        let xs = pts.map(\.x), ys = pts.map(\.y)
        let w = (xs.max() ?? 0) - (xs.min() ?? 0), h = (ys.max() ?? 0) - (ys.min() ?? 0)
        let horizontal = w >= h
        guard max(w, h) >= minAmplitude * 2, max(w, h) > min(w, h) * 2 else { return nil }
        let values = horizontal ? xs : ys
        var reversals = 0, sign: CGFloat = 0, extreme = values[0]
        for v in values.dropFirst() {
            let d = v - extreme
            if sign == 0 {
                if abs(d) >= minAmplitude { sign = d > 0 ? 1 : -1; extreme = v }
            } else if d * sign > 0 {
                extreme = v
            } else if abs(d) >= minAmplitude {
                reversals += 1; sign = -sign; extreme = v
            }
        }
        guard reversals >= minReversals else { return nil }
        return horizontal ? .shakeHorizontal : .shakeVertical
    }

    /// Wraps an angle difference into -pi...pi.
    static func normalizedAngle(_ a: CGFloat) -> CGFloat {
        var a = a
        while a > .pi { a -= 2 * .pi }
        while a < -.pi { a += 2 * .pi }
        return a
    }

    /// Maps a window frame from one screen to another, keeping its relative
    /// position and clamping its size to the destination.
    static func relocate(_ f: CGRect, from a: CGRect, to b: CGRect) -> CGRect {
        let w = min(f.width, b.width), h = min(f.height, b.height)
        let rx = a.width > f.width ? (f.minX - a.minX) / (a.width - f.width) : 0
        let ry = a.height > f.height ? (f.minY - a.minY) / (a.height - f.height) : 0
        let x = b.minX + max(0, min(1, rx)) * (b.width - w)
        let y = b.minY + max(0, min(1, ry)) * (b.height - h)
        return CGRect(x: x.rounded(), y: y.rounded(), width: w, height: h)
    }

    /// Scales a frame around its centre, clamped to a minimum size.
    static func scaled(_ f: CGRect, by factor: CGFloat, minSize: CGFloat = 160) -> CGRect {
        let w = max(minSize, f.width * factor), h = max(minSize, f.height * factor)
        return CGRect(x: (f.midX - w / 2).rounded(), y: (f.midY - h / 2).rounded(), width: w.rounded(), height: h.rounded())
    }

    /// True when two frames are equal within a few points.
    static func roughlyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 12) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance &&
            abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    /// Semantic version comparison that tolerates a leading "v" and missing parts.
    static func isNewerVersion(_ candidate: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")).split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
