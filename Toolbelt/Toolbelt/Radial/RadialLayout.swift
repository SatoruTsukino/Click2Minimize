import CoreGraphics
import Foundation

/// A Shift "tap": pressed and released within `maxDuration` with no other modifier involved.
struct ShiftTap {
    var maxDuration: TimeInterval = 0.35
    private var downAt: TimeInterval?

    /// Feed every modifier change. Returns true when a tap completes.
    mutating func update(shift: Bool, others: Bool, at t: TimeInterval) -> Bool {
        if others {
            downAt = nil
            return false
        }
        if shift {
            if downAt == nil { downAt = t }
            return false
        }
        defer { downAt = nil }
        guard let start = downAt else { return false }
        return t - start <= maxDuration
    }
}

/// Petal positions around the pointer: an inner ring of up to 8, the rest on an outer ring,
/// evenly spaced clockwise from 12 o'clock.
enum RadialLayout {
    static let innerCapacity = 8
    static let innerRadius: CGFloat = 92
    static let outerRadius: CGFloat = 168
    static let petalSize: CGFloat = 66

    /// Offsets from the centre (AppKit coordinates, y up).
    static func place(count: Int) -> [CGPoint] {
        let inner = min(count, innerCapacity)
        let outer = count - inner
        return ring(inner, radius: innerRadius, phase: 0)
            + ring(outer, radius: outerRadius, phase: outer > 0 ? .pi / CGFloat(outer) : 0)
    }

    private static func ring(_ n: Int, radius: CGFloat, phase: CGFloat) -> [CGPoint] {
        (0..<n).map { i in
            let angle = .pi / 2 - phase - 2 * .pi * CGFloat(i) / CGFloat(n)
            return CGPoint(x: (radius * cos(angle)).rounded(), y: (radius * sin(angle)).rounded())
        }
    }

    /// Side of the square panel that holds every petal.
    static func extent(count: Int) -> CGFloat {
        2 * ((count > innerCapacity ? outerRadius : innerRadius) + petalSize / 2 + 8)
    }
}

extension ConvertAction {
    /// Label for a ring petal.
    var shortTitle: String {
        switch self {
        case .convertImage(let f): f.rawValue.uppercased()
        case .compress: "Compress"
        case .resize(.half): "50%"
        case .resize(.fit(let px)): "\(px) px"
        case .video(.mp4): "MP4"
        case .video(.mov): "MOV"
        case .video(.shrink1080): "1080p"
        case .video(.shrink720): "720p"
        case .removeAudio: "No Audio"
        case .extractAudio: "M4A"
        case .ffmpeg(.mp4): "MP4 ffmpeg"
        case .ffmpeg(let t): t.rawValue.uppercased()
        case .toPDF: "PDF"
        }
    }
}
