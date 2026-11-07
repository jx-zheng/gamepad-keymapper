import Foundation

enum StickMath {
    /// Radial deadzone. Returns a vector scaled so the edge of the deadzone is 0 and full deflection is 1.
    static func shaped(x: Double, y: Double, deadzone: Double) -> (x: Double, y: Double)? {
        let clampedX = min(1, max(-1, x))
        let clampedY = min(1, max(-1, y))
        let magnitude = hypot(clampedX, clampedY)
        let zone = min(0.95, max(0, deadzone))
        guard magnitude >= zone, magnitude > 0 else { return nil }
        let scaled = (magnitude - zone) / (1 - zone)
        return (clampedX / magnitude * scaled, clampedY / magnitude * scaled)
    }
}

struct StickDigitalizer: Equatable {
    var deadzone: Double
    var releaseZone: Double
    private var down: Set<String> = []

    struct Change: Equatable {
        var pressed: [ControllerButton]
        var released: [ControllerButton]
    }

    init(deadzone: Double = 0.28, releaseZone: Double = 0.20) {
        self.deadzone = deadzone
        self.releaseZone = releaseZone
    }

    mutating func update(x: Double, y: Double, side: StickSide) -> Change {
        let zone = min(0.95, max(0, deadzone))
        let release = min(zone, max(0, releaseZone))
        let axes: [(id: String, magnitude: Double)] = [
            (side.buttonID(.up), y),
            (side.buttonID(.right), x),
            (side.buttonID(.down), -y),
            (side.buttonID(.left), -x)
        ]
        var pressed: [ControllerButton] = []
        var released: [ControllerButton] = []
        for axis in axes {
            let isDown = down.contains(axis.id)
            // A resting axis has magnitude 0. `>= 0` would latch every direction when the
            // deadzone or release zone is 0, and the key would never come back up.
            let active = axis.magnitude > 0 && axis.magnitude >= (isDown ? release : zone)
            if active && !isDown {
                down.insert(axis.id)
                pressed.append(ControllerButton(id: axis.id))
            } else if !active && isDown {
                down.remove(axis.id)
                released.append(ControllerButton(id: axis.id))
            }
        }
        return Change(pressed: pressed, released: released)
    }

    mutating func releaseAll() -> [ControllerButton] {
        let ids = down.sorted()
        down.removeAll()
        return ids.map { ControllerButton(id: $0) }
    }

    var heldIDs: Set<String> { down }
}
