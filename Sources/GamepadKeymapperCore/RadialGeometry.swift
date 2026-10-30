import Foundation

enum RadialGeometry {
    /// Index of the slice under a stick vector. Index 0 is up; indexes increase clockwise.
    /// `dy` is positive upward, `dx` is positive to the right.
    static func sliceIndex(dx: Double, dy: Double, count: Int, deadzone: Double) -> Int? {
        guard count > 0 else { return nil }
        let magnitude = hypot(dx, dy)
        guard magnitude >= max(0, deadzone), magnitude > 0 else { return nil }
        var angle = atan2(dx, dy)
        if angle < 0 { angle += 2 * .pi }
        return index(forAngle: angle, count: count)
    }

    static func index(for cardinal: CardinalDirection, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let angle: Double
        switch cardinal {
        case .up: angle = 0
        case .right: angle = .pi / 2
        case .down: angle = .pi
        case .left: angle = 3 * .pi / 2
        }
        return index(forAngle: angle, count: count)
    }

    /// Center of a slice on a unit ring. `x` is positive right and `y` is positive up.
    /// SwiftUI’s y axis points down, so a view should offset by `(x, -y)`.
    static func sliceCenter(index: Int, count: Int) -> (x: Double, y: Double) {
        guard count > 0 else { return (0, 0) }
        let theta = (Double.pi / 2) - (Double(index) * (2 * Double.pi / Double(count)))
        return (cos(theta), sin(theta))
    }

    static func index(forAngle angle: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let slice = (2 * .pi) / Double(count)
        var normalized = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if normalized < 0 { normalized += 2 * .pi }
        var index = Int((normalized + slice / 2) / slice) % count
        if index < 0 { index += count }
        return index
    }
}
