import AppKit
import CoreGraphics
import Foundation
import GamepadKeymapperCore

/// Posts keyboard, mouse, and media events for actions the user configured.
///
/// This type does not install an event tap. Each `CGEvent` is created, posted, and released.
/// Call it from the mapper queue only.
final class InputSynthesizer {
    private var keyCounts: [CGKeyCode: Int] = [:]
    private var mouseButtons: Set<CGMouseButton> = []
    private var pointerX = 0.0
    private var pointerY = 0.0
    private var scrollX = 0.0
    private var scrollY = 0.0
    private var nextKeyboardToken = 0
    private var keyboardRuns: [KeyboardRun] = []
    private let queue: DispatchQueue

    /// One in-flight keyboard action. Cancelling it does not cancel other actions.
    private final class KeyboardRun {
        let token: Int
        let command: KeyboardCommand
        var cancelled = false
        /// Key codes this action currently holds, one entry per press, so release uses the ref count.
        var held: [CGKeyCode] = []

        init(token: Int, command: KeyboardCommand) {
            self.token = token
            self.command = command
        }
    }

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func begin(_ action: MapperAction) {
        switch action {
        case .keyboard(let command):
            beginKeyboard(command)
        case .media(let key):
            tapMedia(key)
        case .mouseClick(let button, let clicks):
            if clicks <= 1 {
                mouse(button, down: true, clickState: 1)
            } else {
                for click in 1...clicks {
                    mouse(button, down: true, clickState: click)
                    mouse(button, down: false, clickState: click)
                }
            }
        case .mouseScroll(let dx, let dy):
            scroll(dx: dx, dy: dy)
        case .mouseMove:
            break
        case .typeText(let text):
            type(String(text.prefix(ProfileSanitizer.maxSnippetLength)))
        case .shortcut, .launchApp:
            break
        }
    }

    func end(_ action: MapperAction) {
        switch action {
        case .keyboard(let command):
            endKeyboard(command)
        case .mouseClick(let button, let clicks) where clicks <= 1:
            mouse(button, down: false, clickState: 1)
        default:
            break
        }
    }

    func move(dx: Double, dy: Double) {
        pointerX += dx
        pointerY += dy
        let wholeX = pointerX.rounded(.towardZero)
        let wholeY = pointerY.rounded(.towardZero)
        guard wholeX != 0 || wholeY != 0 else { return }
        pointerX -= wholeX
        pointerY -= wholeY
        let stepX = min(400, max(-400, wholeX))
        let stepY = min(400, max(-400, wholeY))
        guard let source = CGEvent(source: nil) else { return }
        let next = clampToDisplays(CGPoint(x: source.location.x + stepX, y: source.location.y + stepY))
        let (eventType, button) = dragEvent
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: eventType,
            mouseCursorPosition: next,
            mouseButton: button
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    func scroll(dx: Double, dy: Double) {
        scrollX += dx
        scrollY += dy
        let wholeX = Int32(scrollX.rounded(.towardZero))
        let wholeY = Int32(scrollY.rounded(.towardZero))
        guard wholeX != 0 || wholeY != 0 else { return }
        scrollX -= Double(wholeX)
        scrollY -= Double(wholeY)
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: wholeY,
            wheel2: wholeX,
            wheel3: 0
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    func releaseAll() {
        for run in keyboardRuns {
            run.cancelled = true
        }
        keyboardRuns.removeAll()
        for code in keyCounts.keys {
            postKey(code, down: false, flags: [])
        }
        keyCounts.removeAll()
        for button in mouseButtons {
            postMouse(button, down: false, clickState: 1)
        }
        mouseButtons.removeAll()
    }

    private var dragEvent: (CGEventType, CGMouseButton) {
        if mouseButtons.contains(.left) { return (.leftMouseDragged, .left) }
        if mouseButtons.contains(.right) { return (.rightMouseDragged, .right) }
        if mouseButtons.contains(.center) { return (.otherMouseDragged, .center) }
        return (.mouseMoved, .left)
    }

    private func beginKeyboard(_ command: KeyboardCommand) {
        nextKeyboardToken += 1
        let run = KeyboardRun(token: nextKeyboardToken, command: command)
        keyboardRuns.append(run)
        runSteps(run, steps: Array(command.steps.prefix(8)), holdLast: command.holdLast, index: 0)
    }

    private func endKeyboard(_ command: KeyboardCommand) {
        guard let index = keyboardRuns.firstIndex(where: { $0.command == command && !$0.cancelled }) else { return }
        let run = keyboardRuns.remove(at: index)
        run.cancelled = true
        for code in run.held.reversed() {
            releaseKey(code, flags: [])
        }
        run.held.removeAll()
    }

    private func runSteps(_ run: KeyboardRun, steps: [KeyStep], holdLast: Bool, index: Int) {
        guard !run.cancelled, run.token > 0 else { return }
        if index >= steps.count {
            return
        }
        let isLast = index == steps.count - 1
        if holdLast && isLast {
            holdDown(steps[index], run: run)
            return
        }
        tap(steps[index])
        let delay = min(2_000, max(0, steps[index].delayMilliseconds))
        let next = index + 1
        if delay == 0 {
            runSteps(run, steps: steps, holdLast: holdLast, index: next)
        } else {
            let token = run.token
            queue.asyncAfter(deadline: .now() + .milliseconds(delay)) { [weak self, weak run] in
                guard let self, let run, !run.cancelled, run.token == token else { return }
                self.runSteps(run, steps: steps, holdLast: holdLast, index: next)
            }
        }
    }

    private func tap(_ step: KeyStep) {
        let flags = cgFlags(step.modifiers)
        let modifiers = modifierCodes(step.modifiers)
        for code in modifiers { pressKey(code, flags: flags) }
        pressKey(step.keyCode, flags: flags)
        releaseKey(step.keyCode, flags: flags)
        for code in modifiers.reversed() { releaseKey(code, flags: flags) }
    }

    private func holdDown(_ step: KeyStep, run: KeyboardRun) {
        let flags = cgFlags(step.modifiers)
        for code in modifierCodes(step.modifiers) {
            pressKey(code, flags: flags)
            run.held.append(code)
        }
        pressKey(step.keyCode, flags: flags)
        run.held.append(step.keyCode)
    }

    private func pressKey(_ code: CGKeyCode, flags: CGEventFlags) {
        let count = keyCounts[code, default: 0]
        if count == 0 {
            postKey(code, down: true, flags: flags)
        }
        keyCounts[code] = count + 1
    }

    private func releaseKey(_ code: CGKeyCode, flags: CGEventFlags) {
        guard let count = keyCounts[code], count > 0 else { return }
        if count == 1 {
            keyCounts[code] = nil
            postKey(code, down: false, flags: flags)
        } else {
            keyCounts[code] = count - 1
        }
    }

    private func postKey(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private func mouse(_ kind: MouseButtonKind, down: Bool, clickState: Int) {
        let button = cgButton(kind)
        let type = mouseType(kind, down: down)
        if down {
            mouseButtons.insert(button)
        } else {
            mouseButtons.remove(button)
        }
        guard let location = CGEvent(source: nil)?.location else { return }
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: button
        ) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
        event.post(tap: .cghidEventTap)
    }

    private func postMouse(_ button: CGMouseButton, down: Bool, clickState: Int) {
        let type: CGEventType
        switch button {
        case .right: type = down ? .rightMouseDown : .rightMouseUp
        case .center: type = down ? .otherMouseDown : .otherMouseUp
        default: type = down ? .leftMouseDown : .leftMouseUp
        }
        guard let location = CGEvent(source: nil)?.location else { return }
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: button
        ) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
        event.post(tap: .cghidEventTap)
    }

    private func type(_ text: String) {
        guard !text.isEmpty else { return }
        var units = Array(text.utf16)
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return }
        units.withUnsafeBufferPointer { buffer in
            down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Media keys use the public system-defined aux-control event (NX_SUBTYPE_AUX_CONTROL_BUTTONS).
    private func tapMedia(_ key: MediaKey) {
        postMedia(key, down: true)
        postMedia(key, down: false)
    }

    private func postMedia(_ key: MediaKey, down: Bool) {
        let keyCode = mediaCode(key)
        let flags = down ? 0xA00 : 0xB00
        let data1 = Int((Int(keyCode) << 16) | flags)
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }

    private func mediaCode(_ key: MediaKey) -> Int32 {
        switch key {
        case .volumeUp: return 0
        case .volumeDown: return 1
        case .brightnessUp: return 2
        case .brightnessDown: return 3
        case .mute: return 7
        case .playPause: return 16
        case .nextTrack: return 17
        case .previousTrack: return 18
        }
    }

    private func cgFlags(_ modifiers: KeyModifiers) -> CGEventFlags {
        var flags = CGEventFlags()
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }

    private func modifierCodes(_ modifiers: KeyModifiers) -> [CGKeyCode] {
        var codes: [CGKeyCode] = []
        if modifiers.contains(.control) { codes.append(59) }
        if modifiers.contains(.option) { codes.append(58) }
        if modifiers.contains(.shift) { codes.append(56) }
        if modifiers.contains(.command) { codes.append(55) }
        if modifiers.contains(.function) { codes.append(63) }
        return codes
    }

    private func cgButton(_ kind: MouseButtonKind) -> CGMouseButton {
        switch kind {
        case .left: return .left
        case .right: return .right
        case .middle: return .center
        }
    }

    private func mouseType(_ kind: MouseButtonKind, down: Bool) -> CGEventType {
        switch (kind, down) {
        case (.left, true): return .leftMouseDown
        case (.left, false): return .leftMouseUp
        case (.right, true): return .rightMouseDown
        case (.right, false): return .rightMouseUp
        case (.middle, true): return .otherMouseDown
        case (.middle, false): return .otherMouseUp
        }
    }

    private func clampToDisplays(_ point: CGPoint) -> CGPoint {
        var union = CGRect.null
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? NSNumber else {
                continue
            }
            union = union.union(CGDisplayBounds(CGDirectDisplayID(number.uint32Value)))
        }
        guard !union.isNull, union.width > 2, union.height > 2 else { return point }
        let inset = union.insetBy(dx: 1, dy: 1)
        return CGPoint(
            x: min(max(point.x, inset.minX), inset.maxX),
            y: min(max(point.y, inset.minY), inset.maxY)
        )
    }
}
