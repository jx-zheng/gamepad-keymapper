import Foundation

enum EngineEffect: Equatable {
    case actionBegan(MapperAction)
    case actionEnded(MapperAction)
    case pointerDelta(dx: Double, dy: Double)
    case scrollDelta(dx: Double, dy: Double)
    case showRadial(RadialMenu, selection: Int?)
    case updateRadial(Int?)
    case hideRadial
    case layersChanged
    case captured(ControllerButton)
}

/// Turns debounced button and stick samples into actions.
///
/// Call it from one thread. Controller ids are opaque strings; each controller keeps its own
/// held buttons, layer toggles, and debounce state so two pads can be used at once.
struct MappingInterpreter {
    var debounce: TimeInterval
    var stickDeadzone: Double
    var stickReleaseZone: Double
    var captureNextPress = false

    private struct DebouncerKey: Hashable {
        var controller: String
        var button: String
    }

    private struct RadialSession: Equatable {
        var controller: String
        var menuID: UUID
        var trigger: ControllerButton
        var selection: Int?
    }

    private struct StickPair {
        var left = StickDigitalizer()
        var right = StickDigitalizer()
    }

    private var debouncers: [DebouncerKey: ButtonDebouncer] = [:]
    private var categories: [String: String] = [:]
    private var held: [String: Set<String>] = [:]
    private var toggled: [String: Set<UUID>] = [:]
    private var openHolds: [String: MapperAction] = [:]
    private var radial: RadialSession?
    private var sticks: [String: StickPair] = [:]
    private var lastStickSample: [String: TimeInterval] = [:]
    private var lastPointerTime: TimeInterval?

    init(debounce: TimeInterval = 0.015, stickDeadzone: Double = 0.28, stickReleaseZone: Double = 0.20) {
        self.debounce = debounce
        self.stickDeadzone = stickDeadzone
        self.stickReleaseZone = stickReleaseZone
    }

    func isButtonHeld(controller: String, button: ControllerButton) -> Bool {
        held[controller, default: []].contains(button.id)
    }

    func heldButtonIDs(controller: String) -> Set<String> {
        held[controller, default: []]
    }

    /// True while a held button is a continuous pointer nudge. The app should pump `poll` only then.
    var needsPointerPump: Bool {
        openHolds.values.contains { action in
            if case .mouseMove = action { return true }
            return false
        }
    }

    /// Earliest time a debounced edge should be committed. Nil when nothing is waiting.
    func nextWakeTime() -> TimeInterval? {
        var next: TimeInterval?
        for debouncer in debouncers.values {
            guard let wake = debouncer.wakeTime() else { continue }
            if let current = next {
                if wake < current { next = wake }
            } else {
                next = wake
            }
        }
        return next
    }

    /// Bound on interpreter storage. Used to prove repeated events do not accumulate history.
    var debugStateCount: Int {
        debouncers.count + openHolds.count + sticks.count + lastStickSample.count + (radial == nil ? 0 : 1)
    }

    mutating func ingestButton(
        controller: String,
        category: String?,
        button: ControllerButton,
        rawPressed: Bool,
        time: TimeInterval,
        profile: Profile
    ) -> [EngineEffect] {
        if let category {
            categories[controller] = category
        }
        let key = DebouncerKey(controller: controller, button: button.id)
        var debouncer = debouncers[key] ?? ButtonDebouncer(interval: debounce)
        debouncer.interval = debounce
        let edge = debouncer.ingest(rawPressed: rawPressed, time: time)
        debouncers[key] = debouncer
        guard let pressed = edge else { return [] }
        return apply(
            controller: controller,
            category: categories[controller],
            button: button,
            pressed: pressed,
            profile: profile
        )
    }

    mutating func poll(time: TimeInterval, profile: Profile) -> [EngineEffect] {
        var effects: [EngineEffect] = []
        let keys = debouncers.keys.sorted { lhs, rhs in
            if lhs.controller == rhs.controller { return lhs.button < rhs.button }
            return lhs.controller < rhs.controller
        }
        for key in keys {
            guard var debouncer = debouncers[key] else { continue }
            debouncer.interval = debounce
            let edge = debouncer.poll(time: time)
            debouncers[key] = debouncer
            if let pressed = edge {
                effects += apply(
                    controller: key.controller,
                    category: categories[key.controller],
                    button: ControllerButton(id: key.button),
                    pressed: pressed,
                    profile: profile
                )
            }
        }
        if needsPointerPump {
            if let lastPointerTime {
                let step = min(0.05, max(0, time - lastPointerTime))
                if step > 0 {
                    for key in openHolds.keys.sorted() {
                        if let action = openHolds[key], case .mouseMove(let dx, let dy) = action {
                            effects.append(.pointerDelta(dx: dx * step, dy: dy * step))
                        }
                    }
                }
            }
            lastPointerTime = time
        } else {
            lastPointerTime = nil
        }
        return effects
    }

    mutating func ingestStick(
        controller: String,
        category: String?,
        side: StickSide,
        x: Double,
        y: Double,
        time: TimeInterval,
        profile: Profile
    ) -> [EngineEffect] {
        if let category {
            categories[controller] = category
        }
        let x = min(1, max(-1, x))
        let y = min(1, max(-1, y))

        if var session = radial,
           session.controller == controller,
           let menu = profile.radialMenus.first(where: { $0.id == session.menuID }),
           menu.selection.matches(side: side) {
            let index = RadialGeometry.sliceIndex(dx: x, dy: y, count: menu.items.count, deadzone: stickDeadzone)
            if index != session.selection {
                session.selection = index
                radial = session
                return [.updateRadial(index)]
            }
            return []
        }

        var pair = sticks[controller] ?? StickPair()
        let mode = side == .left ? profile.sticks.left : profile.sticks.right
        var effects: [EngineEffect] = []

        switch mode {
        case .digital:
            var digitalizer = side == .left ? pair.left : pair.right
            digitalizer.deadzone = stickDeadzone
            digitalizer.releaseZone = stickReleaseZone
            let change = digitalizer.update(x: x, y: y, side: side)
            if side == .left { pair.left = digitalizer } else { pair.right = digitalizer }
            sticks[controller] = pair
            for button in change.released {
                effects += ingestButton(
                    controller: controller,
                    category: category,
                    button: button,
                    rawPressed: false,
                    time: time,
                    profile: profile
                )
            }
            for button in change.pressed {
                effects += ingestButton(
                    controller: controller,
                    category: category,
                    button: button,
                    rawPressed: true,
                    time: time,
                    profile: profile
                )
            }
        case .mouse(let sensitivity):
            effects += releaseLatchedStick(
                controller: controller,
                category: category,
                side: side,
                pair: &pair,
                time: time,
                profile: profile
            )
            sticks[controller] = pair
            let dt = stickDelta(controller: controller, side: side, time: time)
            if dt > 0, let shaped = StickMath.shaped(x: x, y: y, deadzone: stickDeadzone) {
                effects.append(.pointerDelta(
                    dx: shaped.x * sensitivity * dt,
                    dy: -shaped.y * sensitivity * dt
                ))
            }
        case .scroll(let sensitivity):
            effects += releaseLatchedStick(
                controller: controller,
                category: category,
                side: side,
                pair: &pair,
                time: time,
                profile: profile
            )
            sticks[controller] = pair
            let dt = stickDelta(controller: controller, side: side, time: time)
            if dt > 0, let shaped = StickMath.shaped(x: x, y: y, deadzone: stickDeadzone) {
                effects.append(.scrollDelta(
                    dx: shaped.x * sensitivity * dt,
                    dy: shaped.y * sensitivity * dt
                ))
            }
        }
        return effects
    }

    mutating func clearController(_ controller: String) -> [EngineEffect] {
        var effects: [EngineEffect] = []
        let prefix = controller + "|"
        for key in Array(openHolds.keys) where key.hasPrefix(prefix) {
            if let action = openHolds.removeValue(forKey: key) {
                effects.append(.actionEnded(action))
            }
        }
        if radial?.controller == controller {
            radial = nil
            effects.append(.hideRadial)
        }
        held[controller] = nil
        toggled[controller] = nil
        categories[controller] = nil
        sticks[controller] = nil
        debouncers = debouncers.filter { $0.key.controller != controller }
        let samplePrefix = controller + "|"
        lastStickSample = lastStickSample.filter { !$0.key.hasPrefix(samplePrefix) }
        return effects
    }

    /// Releases sustained keys and the radial menu without forgetting which buttons are still down.
    /// A profile switch uses this so a button that is still held does not immediately fire the new profile.
    mutating func endSustainedActions() -> [EngineEffect] {
        var effects: [EngineEffect] = []
        for key in openHolds.keys.sorted() {
            if let action = openHolds[key] {
                effects.append(.actionEnded(action))
            }
        }
        openHolds.removeAll()
        toggled.removeAll()
        if radial != nil {
            radial = nil
            effects.append(.hideRadial)
        }
        captureNextPress = false
        lastPointerTime = nil
        // Drop stick timestamps so the next sample cannot fling the pointer across a profile change.
        lastStickSample.removeAll()
        return effects
    }

    /// Ends held keys and drops controller state. Used when mapping is turned off.
    mutating func resetInteractions() -> [EngineEffect] {
        var effects: [EngineEffect] = []
        for key in openHolds.keys.sorted() {
            if let action = openHolds[key] {
                effects.append(.actionEnded(action))
            }
        }
        openHolds.removeAll()
        if radial != nil {
            radial = nil
            effects.append(.hideRadial)
        }
        held.removeAll()
        toggled.removeAll()
        debouncers.removeAll()
        sticks.removeAll()
        categories.removeAll()
        lastStickSample.removeAll()
        lastPointerTime = nil
        captureNextPress = false
        return effects
    }

    private mutating func stickDelta(controller: String, side: StickSide, time: TimeInterval) -> TimeInterval {
        let key = "\(controller)|\(side.rawValue)"
        let previous = lastStickSample[key]
        lastStickSample[key] = time
        guard let previous else { return 0 }
        return min(0.05, max(0, time - previous))
    }

    private mutating func releaseLatchedStick(
        controller: String,
        category: String?,
        side: StickSide,
        pair: inout StickPair,
        time: TimeInterval,
        profile: Profile
    ) -> [EngineEffect] {
        var digitalizer = side == .left ? pair.left : pair.right
        let released = digitalizer.releaseAll()
        guard !released.isEmpty else { return [] }
        if side == .left { pair.left = digitalizer } else { pair.right = digitalizer }
        var effects: [EngineEffect] = []
        for button in released {
            effects += ingestButton(
                controller: controller,
                category: category,
                button: button,
                rawPressed: false,
                time: time,
                profile: profile
            )
        }
        return effects
    }

    private mutating func apply(
        controller: String,
        category: String?,
        button: ControllerButton,
        pressed: Bool,
        profile: Profile
    ) -> [EngineEffect] {
        if pressed {
            held[controller, default: []].insert(button.id)
        } else {
            held[controller, default: []].remove(button.id)
        }

        if pressed && captureNextPress {
            captureNextPress = false
            return [.captured(button)]
        }

        if var session = radial, session.controller == controller {
            if let menu = profile.radialMenus.first(where: { $0.id == session.menuID }) {
                if pressed, menu.selection == .dpad, let cardinal = button.cardinal {
                    let index = RadialGeometry.index(for: cardinal, count: menu.items.count)
                    if index != session.selection {
                        session.selection = index
                        radial = session
                        return [.updateRadial(index)]
                    }
                    return []
                }
                if pressed && button.id == "b" && menu.trigger.id != "b" {
                    radial = nil
                    return [.hideRadial]
                }
                if !pressed && button.id == menu.trigger.id {
                    let action = session.selection.flatMap { index -> MapperAction? in
                        guard menu.items.indices.contains(index) else { return nil }
                        return menu.items[index].action
                    }
                    radial = nil
                    var effects: [EngineEffect] = [.hideRadial]
                    if let action {
                        effects += fireTap(action)
                    }
                    return effects
                }
            } else {
                radial = nil
                return [.hideRadial]
            }
            // Ignore other buttons from the controller that opened the menu.
            return []
        }

        if pressed {
            if let menu = profile.radialMenus.first(where: { $0.trigger.id == button.id }) {
                radial = RadialSession(controller: controller, menuID: menu.id, trigger: button, selection: nil)
                return [.showRadial(menu, selection: nil)]
            }
            if toggleLayers(controller: controller, button: button, profile: profile) {
                return [.layersChanged]
            }
            if profile.layers.contains(where: { layer in
                if case .hold(let activator) = layer.activation { return activator.id == button.id }
                return false
            }) {
                return [.layersChanged]
            }
            if let action = resolve(button: button, controller: controller, category: category, profile: profile) {
                if action.sustainsWhileHeld {
                    openHolds[holdKey(controller, button)] = action
                    return [.actionBegan(action)]
                }
                return fireTap(action)
            }
            return []
        }

        var effects: [EngineEffect] = []
        if profile.layerActivatorIDs.contains(button.id) {
            effects.append(.layersChanged)
        }
        if let action = openHolds.removeValue(forKey: holdKey(controller, button)) {
            effects.append(.actionEnded(action))
        }
        return effects
    }

    private mutating func toggleLayers(controller: String, button: ControllerButton, profile: Profile) -> Bool {
        var set = toggled[controller, default: []]
        var didToggle = false
        for layer in profile.layers {
            if case .toggle(let activator) = layer.activation, activator.id == button.id {
                didToggle = true
                if set.contains(layer.id) {
                    set.remove(layer.id)
                } else {
                    set.insert(layer.id)
                }
            }
        }
        if didToggle {
            toggled[controller] = set
        }
        return didToggle
    }

    private func resolve(
        button: ControllerButton,
        controller: String,
        category: String?,
        profile: Profile
    ) -> MapperAction? {
        let active = profile.layers.filter { isActive($0, controller: controller) }
        for layer in active.reversed() {
            let matches = layer.bindings.filter { binding in
                binding.button.id == button.id && binding.controllerMatch.matches(category)
            }
            if let specific = matches.first(where: {
                if case .productCategory = $0.controllerMatch { return true }
                return false
            }) {
                return specific.action
            }
            if let any = matches.first {
                return any.action
            }
            if layer.activation.activator != nil && !layer.allowsFallthrough {
                return nil
            }
        }
        return nil
    }

    private func isActive(_ layer: Layer, controller: String) -> Bool {
        switch layer.activation {
        case .base:
            return true
        case .hold(let button):
            return held[controller, default: []].contains(button.id)
        case .toggle:
            return toggled[controller, default: []].contains(layer.id)
        }
    }

    private func holdKey(_ controller: String, _ button: ControllerButton) -> String {
        "\(controller)|\(button.id)"
    }

    /// Radial commits and other momentary triggers always complete, even if the action can be held.
    private func fireTap(_ action: MapperAction) -> [EngineEffect] {
        switch action {
        case .mouseMove(let dx, let dy):
            // One-shot nudge (radial menus). Held pointer actions are integrated by `poll`.
            return [.pointerDelta(dx: dx / 60, dy: dy / 60)]
        case .mouseClick(let button, let clicks) where clicks <= 1:
            let click = MapperAction.mouseClick(button, clicks: 1)
            return [.actionBegan(click), .actionEnded(click)]
        case .keyboard(var command) where command.holdLast:
            command.holdLast = false
            return [.actionBegan(.keyboard(command))]
        default:
            return [.actionBegan(action)]
        }
    }
}
