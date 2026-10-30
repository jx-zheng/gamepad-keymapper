import SwiftUI

/// A small original mark for a controller control.
///
/// Letters and simple arrows stand in for every layout (Xbox, PlayStation, Switch).
/// The row title still carries the dual name, such as “A / Cross”.
struct ControlGlyph: View {
    var button: ControllerButton

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(plate)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
            mark
                .foregroundStyle(Color.primary)
        }
        .frame(width: 34, height: 24)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var mark: some View {
        switch button.id {
        case "a":
            face("A", tint: Color(red: 0.22, green: 0.55, blue: 0.32))
        case "b":
            face("B", tint: Color(red: 0.66, green: 0.24, blue: 0.24))
        case "x":
            face("X", tint: Color(red: 0.22, green: 0.40, blue: 0.72))
        case "y":
            face("Y", tint: Color(red: 0.72, green: 0.54, blue: 0.16))
        case "leftShoulder":
            shoulder("L")
        case "rightShoulder":
            shoulder("R")
        case "leftTrigger":
            shoulder("ZL")
        case "rightTrigger":
            shoulder("ZR")
        case "dpadUp":
            Image(systemName: "arrow.up")
                .font(.system(size: 11, weight: .bold))
        case "dpadDown":
            Image(systemName: "arrow.down")
                .font(.system(size: 11, weight: .bold))
        case "dpadLeft":
            Image(systemName: "arrow.left")
                .font(.system(size: 11, weight: .bold))
        case "dpadRight":
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .bold))
        case "leftStickUp", "rightStickUp":
            stickArrow("arrow.up")
        case "leftStickDown", "rightStickDown":
            stickArrow("arrow.down")
        case "leftStickLeft", "rightStickLeft":
            stickArrow("arrow.left")
        case "leftStickRight", "rightStickRight":
            stickArrow("arrow.right")
        case "leftStickClick":
            stickPress("L3")
        case "rightStickClick":
            stickPress("R3")
        case "menu":
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
        case "options":
            Image(systemName: "minus")
                .font(.system(size: 11, weight: .bold))
        case "home":
            Image(systemName: "house.fill")
                .font(.system(size: 11, weight: .semibold))
        case "touchpad":
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(Color.primary, lineWidth: 1.2)
                .frame(width: 16, height: 10)
        default:
            Image(systemName: "gamecontroller")
                .font(.system(size: 11, weight: .semibold))
        }
    }

    private var plate: Color {
        Color.primary.opacity(0.06)
    }

    private func face(_ letter: String, tint: Color) -> some View {
        ZStack {
            Circle().fill(tint)
            Text(letter)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
        }
        .frame(width: 16, height: 16)
    }

    private func shoulder(_ label: String) -> some View {
        Text(label)
            .font(.system(size: label.count > 1 ? 9 : 11, weight: .bold, design: .rounded))
            .padding(.horizontal, 2)
    }

    private func stickArrow(_ symbol: String) -> some View {
        ZStack {
            Circle()
                .strokeBorder(Color.primary, lineWidth: 1.2)
                .frame(width: 16, height: 16)
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .bold))
        }
    }

    private func stickPress(_ label: String) -> some View {
        ZStack {
            Circle().strokeBorder(Color.primary, lineWidth: 1.2)
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .rounded))
        }
        .frame(width: 16, height: 16)
    }
}

struct ControlSection: Identifiable {
    var title: String
    var buttons: [ControllerButton]
    var id: String { title }

    static let editor: [ControlSection] = [
        ControlSection(title: "Face", buttons: [.a, .b, .x, .y]),
        ControlSection(title: "Shoulders", buttons: [.leftShoulder, .rightShoulder]),
        ControlSection(title: "Triggers", buttons: [.leftTrigger, .rightTrigger]),
        ControlSection(title: "D-Pad", buttons: [.dpadUp, .dpadDown, .dpadLeft, .dpadRight]),
        ControlSection(title: "Left Stick", buttons: [.leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight, .leftStickClick]),
        ControlSection(title: "Right Stick", buttons: [.rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight, .rightStickClick]),
        ControlSection(title: "Center", buttons: [.menu, .options, .home, .touchpad])
    ]
}
