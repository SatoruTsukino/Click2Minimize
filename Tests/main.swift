import CoreGraphics
import Foundation

// Logic tests for GestureMath. Run with ./test_logic.sh
var failures = 0
func check(_ cond: @autoclosure () -> Bool, _ msg: String, line: Int = #line) {
    if !cond() { failures += 1; print("FAIL [\(line)]: \(msg)") }
}

// Directions (y-down)
check(GestureMath.direction(of: CGVector(dx: 100, dy: 0)) == .right, "right")
check(GestureMath.direction(of: CGVector(dx: 0, dy: -100)) == .up, "up is negative y")
check(GestureMath.direction(of: CGVector(dx: 0, dy: 100)) == .down, "down")
check(GestureMath.direction(of: CGVector(dx: -100, dy: 0)) == .left, "left")
check(GestureMath.direction(of: CGVector(dx: -70, dy: -70)) == .upLeft, "up-left")
check(GestureMath.direction(of: CGVector(dx: 70, dy: 70)) == .downRight, "down-right")

// Lines
let line = (0...20).map { CGPoint(x: 100, y: 100 + CGFloat($0) * 6) }
check(GestureMath.classify(line) == .line(.down), "straight down line")
check(GestureMath.lineDirection(Array(line.prefix(3))) == nil, "too short for a line")

// Circles: clockwise on screen with y-down means angle increasing
func circlePts(clockwise: Bool) -> [CGPoint] {
    (0...40).map { i -> CGPoint in
        let t = CGFloat(i) / 40 * 2 * .pi * (clockwise ? 1 : -1)
        return CGPoint(x: 300 + 60 * cos(t), y: 300 + 60 * sin(t))
    }
}
check(GestureMath.classify(circlePts(clockwise: true)) == .circle(clockwise: true), "clockwise circle")
check(GestureMath.classify(circlePts(clockwise: false)) == .circle(clockwise: false), "counter-clockwise circle")
let half = Array(circlePts(clockwise: true).prefix(18))
check(GestureMath.circle(half) == nil, "half circle is not a circle")

// Shakes
var shakeH: [CGPoint] = []
for k in 0..<5 { for s in 0...10 { let x = CGFloat(s) * 8; shakeH.append(CGPoint(x: 200 + (k % 2 == 0 ? x : 80 - x), y: 200 + CGFloat(s % 2))) } }
check(GestureMath.classify(shakeH) == .shakeHorizontal, "horizontal shake")
let shakeV = shakeH.map { CGPoint(x: $0.y, y: $0.x) }
check(GestureMath.classify(shakeV) == .shakeVertical, "vertical shake")

// Snap zones
let vis = CGRect(x: 0, y: 25, width: 1440, height: 875)
check(SnapZone.leftHalf.frame(in: vis) == CGRect(x: 0, y: 25, width: 720, height: 875), "left half")
check(SnapZone.bottomRight.frame(in: vis).maxX == vis.maxX && SnapZone.bottomRight.frame(in: vis).maxY == vis.maxY, "bottom-right corner anchored")
check(SnapZone.from(.upLeft) == .topLeft, "diagonal maps to quarter")

// Relocate between screens
let a = CGRect(x: 0, y: 0, width: 1000, height: 800), b = CGRect(x: 1000, y: 0, width: 2000, height: 1200)
let moved = GestureMath.relocate(CGRect(x: 0, y: 0, width: 500, height: 400), from: a, to: b)
check(moved.minX == 1000 && moved.minY == 0 && moved.width == 500, "relocate keeps top-left anchored")
let big = GestureMath.relocate(CGRect(x: 0, y: 0, width: 1000, height: 800), from: a, to: CGRect(x: 1000, y: 0, width: 800, height: 600))
check(big.width == 800 && big.height == 600, "relocate clamps size")

// Scaling
let s = GestureMath.scaled(CGRect(x: 100, y: 100, width: 400, height: 300), by: 1.5)
check(abs(s.midX - 300) <= 1 && abs(s.midY - 250) <= 1 && s.width == 600, "scale around centre")
check(GestureMath.scaled(CGRect(x: 0, y: 0, width: 200, height: 200), by: 0.1).width == 160, "scale min size")

// Trackpad -> window offset
let slow = GestureMath.trackpadDelta(dx: 0.001, dy: 0, screenWidth: 1000)
check(abs(slow.dx - 1.125) < 0.01 && slow.dy == 0, "slow movement is near 1:1 with screen width")
let fast = GestureMath.trackpadDelta(dx: 0.02, dy: 0, screenWidth: 1000)
check(abs(fast.dx - 50) < 0.01, "fast movement is accelerated up to 2.5x")
let up = GestureMath.trackpadDelta(dx: 0, dy: 0.0062, screenWidth: 1000)
check(up.dy < 0 && up.dx == 0, "fingers moving up move the window up (y-down offset)")

// Versions
check(GestureMath.isNewerVersion("v2.2", than: "2.1"), "v-prefixed newer")
check(!GestureMath.isNewerVersion("v2.1", than: "2.1"), "equal not newer")
check(GestureMath.isNewerVersion("3.0", than: "2.9.9"), "major bump")
check(!GestureMath.isNewerVersion("2.1", than: "2.1.1"), "older patch")
check(GestureMath.isNewerVersion("2.1.1", than: "2.1"), "patch bump")

print(failures == 0 ? "All GestureMath tests passed" : "\(failures) failure(s)")
exit(failures == 0 ? 0 : 1)
