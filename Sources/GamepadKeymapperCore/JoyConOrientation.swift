import Foundation

/// Horizontal-grip correction for a single Joy-Con.
///
/// GameController reports that stick in the portrait design orientation (wrist strap down).
/// Held sideways, SL/SR are on top: Joy-Con (R) is turned 90° counter-clockwise from portrait,
/// Joy-Con (L) 90° clockwise. A paired grip is a different product and is left alone.
enum JoyConOrientation: Equatable {
    case left
    case right

    /// `nil` for Pro Controllers, paired pads, and anything that is not one lone Joy-Con.
    static func matching(_ category: String) -> JoyConOrientation? {
        let name = category.lowercased()
        let right = name.contains("joy-con (r)") || name.contains("joy-con(r)")
        let left = name.contains("joy-con (l)") || name.contains("joy-con(l)")
        if left == right { return nil }
        return right ? .right : .left
    }

    /// Portrait stick (`+x` right, `+y` up) rotated into the horizontal grip.
    func horizontalStick(x: Double, y: Double) -> (x: Double, y: Double) {
        switch self {
        case .right:
            return (-y, x)
        case .left:
            return (y, -x)
        }
    }

    /// Same rotation as `horizontalStick`, for the hat buttons GameController names in portrait.
    func remapDpad(_ button: ControllerButton) -> ControllerButton {
        switch (self, button.id) {
        case (.right, "dpadUp"): return .dpadLeft
        case (.right, "dpadLeft"): return .dpadDown
        case (.right, "dpadDown"): return .dpadRight
        case (.right, "dpadRight"): return .dpadUp
        case (.left, "dpadUp"): return .dpadRight
        case (.left, "dpadRight"): return .dpadDown
        case (.left, "dpadDown"): return .dpadLeft
        case (.left, "dpadLeft"): return .dpadUp
        default:
            return button
        }
    }
}
