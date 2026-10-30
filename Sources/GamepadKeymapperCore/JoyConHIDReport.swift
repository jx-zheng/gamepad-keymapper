import Foundation

/// Buttons a lone Joy-Con hides from GameController, read from the public HID report.
///
/// macOS delivers simple report `0x3F` for a Joy-Con used as a normal controller.
/// Byte 2 bit `0x40` is physical L or R, and bit `0x80` is ZL or ZR. SL and SR are
/// other bits in that report; GameController already surfaces those as shoulders.
/// Full reports `0x21` and `0x30`–`0x33` use the same two bits on byte 3 (right) or byte 5 (left).
enum JoyConHIDReport {
    static let vendorID = 0x057E
    static let leftProductID = 0x2006
    static let rightProductID = 0x2007

    static func side(productID: Int) -> JoyConOrientation? {
        switch productID {
        case leftProductID: return .left
        case rightProductID: return .right
        default: return nil
        }
    }

    /// Physical shoulder and trigger only. Rail buttons are intentionally absent.
    static func supplementalButtons(packet: [UInt8], side: JoyConOrientation) -> Set<ControllerButton>? {
        guard let reportID = packet.first else { return nil }
        switch reportID {
        case 0x3F:
            guard packet.count >= 3 else { return nil }
            return shoulderAndTrigger(bits: packet[2], side: side)
        case 0x21, 0x30, 0x31, 0x32, 0x33:
            guard packet.count >= 6 else { return nil }
            let bits = side == .right ? packet[3] : packet[5]
            return shoulderAndTrigger(bits: bits, side: side)
        default:
            return nil
        }
    }

    private static func shoulderAndTrigger(bits: UInt8, side: JoyConOrientation) -> Set<ControllerButton> {
        var down: Set<ControllerButton> = []
        if bits & 0x40 != 0 {
            down.insert(side == .left ? .leftShoulder : .rightShoulder)
        }
        if bits & 0x80 != 0 {
            down.insert(side == .left ? .leftTrigger : .rightTrigger)
        }
        return down
    }
}
