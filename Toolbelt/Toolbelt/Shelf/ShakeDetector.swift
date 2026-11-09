import CoreGraphics
import Foundation

/// Detects a "shake" of the pointer: several quick direction reversals along either axis.
/// Pure value type so it can be unit tested with synthetic pointer paths. (Ported from Ledge.)
struct ShakeDetector {
    struct Tuning: Equatable {
        var reversals: Int
        var stroke: CGFloat
        var window: TimeInterval

        static func `for`(_ s: ShakeSensitivity) -> Tuning {
            switch s {
            case .normal: Tuning(reversals: 4, stroke: 34, window: 0.75)
            case .high: Tuning(reversals: 3, stroke: 24, window: 0.8)
            case .highest: Tuning(reversals: 2, stroke: 16, window: 0.9)
            }
        }
    }

    private struct Axis {
        var anchor: CGFloat?
        var extreme: CGFloat = 0
        var direction: CGFloat = 0
        var reversals: [TimeInterval] = []

        mutating func add(_ v: CGFloat, at t: TimeInterval, tuning: Tuning) -> Bool {
            guard let a = anchor else {
                anchor = v
                extreme = v
                return false
            }
            if direction == 0 {
                if abs(v - a) >= 4 {
                    direction = v > a ? 1 : -1
                    extreme = v
                }
                return false
            }
            if (v - extreme) * direction > 0 {
                extreme = v
                return false
            }
            guard (extreme - v) * direction >= tuning.stroke * 0.5 else { return false }
            if abs(extreme - a) >= tuning.stroke {
                reversals.append(t)
            } else {
                reversals.removeAll()
            }
            anchor = extreme
            direction = -direction
            extreme = v
            reversals.removeAll { t - $0 > tuning.window }
            return reversals.count >= tuning.reversals
        }
    }

    var tuning: Tuning
    private var x = Axis()
    private var y = Axis()
    private var lastTime: TimeInterval?

    init(tuning: Tuning = .for(.normal)) { self.tuning = tuning }

    mutating func reset() {
        x = Axis()
        y = Axis()
        lastTime = nil
    }

    /// Feed one pointer sample. Returns true once per detected shake.
    mutating func add(_ p: CGPoint, at t: TimeInterval) -> Bool {
        if let last = lastTime, t - last > 0.35 { reset() }
        lastTime = t
        let hitX = x.add(p.x, at: t, tuning: tuning)
        let hitY = y.add(p.y, at: t, tuning: tuning)
        if hitX || hitY {
            reset()
            return true
        }
        return false
    }
}
