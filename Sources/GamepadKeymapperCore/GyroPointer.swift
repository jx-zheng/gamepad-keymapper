import Foundation

enum GyroPointer {
    /// Converts a rotation rate (radians/second) into a pointer delta for this time step.
    ///
    /// Yaw (`rotationY`) moves the pointer horizontally. Pitch (`rotationX`) moves it vertically.
    /// Controllers disagree about sign, so profiles carry invert switches.
    static func delta(
        rotationX: Double,
        rotationY: Double,
        deadzone: Double,
        sensitivity: Double,
        invertX: Bool,
        invertY: Bool,
        dt: Double
    ) -> (dx: Double, dy: Double)? {
        guard dt > 0, sensitivity != 0 else { return nil }
        let zone = max(0, deadzone)
        var yaw = rotationY
        var pitch = rotationX
        if abs(yaw) < zone { yaw = 0 }
        if abs(pitch) < zone { pitch = 0 }
        if yaw == 0 && pitch == 0 { return nil }
        var dx = yaw * sensitivity * dt
        var dy = pitch * sensitivity * dt
        if invertX { dx = -dx }
        if invertY { dy = -dy }
        return (dx, dy)
    }
}
