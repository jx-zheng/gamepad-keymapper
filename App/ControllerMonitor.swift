import Foundation
import GameController
import QuartzCore

struct ControllerSnapshot: Identifiable, Equatable {
    var id: String
    var name: String
    var category: String
    var battery: String?
    var hasMotion: Bool
    var elementNames: [String]
    var pressed: [String]
}

struct InputBatch {
    struct Edge {
        var sessionID: String
        var category: String
        var button: ControllerButton
        var pressed: Bool
        var time: TimeInterval
    }

    struct Stick {
        var sessionID: String
        var category: String
        var side: StickSide
        var x: Double
        var y: Double
        var time: TimeInterval
        /// This stick is the controller’s only direction pad, as on a single Joy-Con.
        var directsDpad: Bool = false
    }

    struct Motion {
        var sessionID: String
        var category: String
        var rotationX: Double
        var rotationY: Double
        var time: TimeInterval
    }

    var edges: [Edge] = []
    var sticks: [Stick] = []
    var motion: [Motion] = []
}

/// Listens to GameController callbacks and coalesces them onto one queue.
///
/// Each pad gets its own serial handler queue. GameController does not deliver button,
/// stick, or motion callbacks on the main thread, so an editor update cannot stall input.
///
/// Hardware callbacks are not polled. At most one drain block is queued, and stick/motion
/// samples keep only the latest value so a noisy gyro cannot grow memory.
final class ControllerMonitor: NSObject {
    var onBatch: ((InputBatch) -> Void)?
    var onTopology: (() -> Void)?
    var onDisconnected: ((String) -> Void)?

    private let queue: DispatchQueue
    private let lock = NSLock()
    private var sessions: [ObjectIdentifier: ControllerSession] = [:]
    private var pendingEdges: [InputBatch.Edge] = []
    private var pendingSticks: [String: InputBatch.Stick] = [:]
    private var pendingMotion: [String: InputBatch.Motion] = [:]
    private var drainScheduled = false

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func start() {
        // Menu-bar apps are not frontmost. Without this, GameController delivers no events.
        GCController.shouldMonitorBackgroundEvents = true
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(controllerConnected(_:)), name: .GCControllerDidConnect, object: nil)
        center.addObserver(self, selector: #selector(controllerDisconnected(_:)), name: .GCControllerDidDisconnect, object: nil)
        for controller in GCController.controllers() {
            attach(controller)
        }
        onTopology?()
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        lock.lock()
        let current = Array(sessions.values)
        sessions.removeAll()
        pendingEdges.removeAll()
        pendingSticks.removeAll()
        pendingMotion.removeAll()
        drainScheduled = false
        lock.unlock()
        for session in current {
            session.detach()
        }
    }

    func setMotionEnabled(_ enabled: (String) -> Bool) {
        lock.lock()
        let current = Array(sessions.values)
        lock.unlock()
        for session in current {
            session.setMotionHandler(enabled: enabled(session.sessionID))
        }
    }

    func snapshots(pressed: (String) -> [String]) -> [ControllerSnapshot] {
        lock.lock()
        let current = sessions.values.sorted { $0.displayName < $1.displayName }
        lock.unlock()
        return current.map { session in
            ControllerSnapshot(
                id: session.sessionID,
                name: session.displayName,
                category: session.category,
                battery: session.batteryText(),
                hasMotion: session.hasMotion,
                elementNames: session.elementNames,
                pressed: pressed(session.sessionID)
            )
        }
    }

    @objc private func controllerConnected(_ note: Notification) {
        guard let controller = note.object as? GCController else { return }
        attach(controller)
        onTopology?()
    }

    @objc private func controllerDisconnected(_ note: Notification) {
        guard let controller = note.object as? GCController else { return }
        let id = ObjectIdentifier(controller)
        lock.lock()
        let session = sessions.removeValue(forKey: id)
        lock.unlock()
        session?.detach()
        if let session {
            onDisconnected?(session.sessionID)
        }
        onTopology?()
    }

    private func attach(_ controller: GCController) {
        let id = ObjectIdentifier(controller)
        lock.lock()
        if sessions[id] != nil {
            lock.unlock()
            return
        }
        lock.unlock()
        assignPlayerIndex(controller)
        let session = ControllerSession(controller: controller, owner: self)
        session.installHandlers()
        lock.lock()
        sessions[id] = session
        lock.unlock()
    }

    fileprivate func enqueueEdge(_ edge: InputBatch.Edge) {
        lock.lock()
        pendingEdges.append(edge)
        if pendingEdges.count > 64 {
            pendingEdges = Self.collapseEdges(pendingEdges)
        }
        scheduleDrainLocked()
        lock.unlock()
    }

    fileprivate func enqueueStick(_ stick: InputBatch.Stick) {
        lock.lock()
        pendingSticks["\(stick.sessionID)|\(stick.side.rawValue)"] = stick
        scheduleDrainLocked()
        lock.unlock()
    }

    fileprivate func enqueueMotion(_ motion: InputBatch.Motion) {
        lock.lock()
        pendingMotion[motion.sessionID] = motion
        scheduleDrainLocked()
        lock.unlock()
    }

    private func scheduleDrainLocked() {
        guard !drainScheduled else { return }
        drainScheduled = true
        queue.async { [weak self] in
            self?.drain()
        }
    }

    private func drain() {
        lock.lock()
        let batch = InputBatch(
            edges: pendingEdges,
            sticks: Array(pendingSticks.values),
            motion: Array(pendingMotion.values)
        )
        pendingEdges.removeAll(keepingCapacity: true)
        pendingSticks.removeAll(keepingCapacity: true)
        pendingMotion.removeAll(keepingCapacity: true)
        drainScheduled = false
        lock.unlock()
        guard !batch.edges.isEmpty || !batch.sticks.isEmpty || !batch.motion.isEmpty else { return }
        onBatch?(batch)
    }

    /// Coalesce repeated samples but keep press/release pairs, in arrival order.
    private static func collapseEdges(_ edges: [InputBatch.Edge]) -> [InputBatch.Edge] {
        var collapsed: [InputBatch.Edge] = []
        var lastIndex: [String: Int] = [:]
        for edge in edges {
            let key = "\(edge.sessionID)|\(edge.button.id)"
            if let index = lastIndex[key], collapsed[index].pressed == edge.pressed {
                collapsed[index] = edge
            } else {
                lastIndex[key] = collapsed.count
                collapsed.append(edge)
            }
        }
        guard collapsed.count > 64 else { return collapsed }
        var drop = Set<Int>()
        var index = 0
        while collapsed.count - drop.count > 64, index < collapsed.count {
            if !drop.contains(index), collapsed[index].pressed {
                let key = "\(collapsed[index].sessionID)|\(collapsed[index].button.id)"
                if let release = (index + 1..<collapsed.count).first(where: { offset in
                    !drop.contains(offset)
                        && !collapsed[offset].pressed
                        && "\(collapsed[offset].sessionID)|\(collapsed[offset].button.id)" == key
                }) {
                    drop.insert(index)
                    drop.insert(release)
                }
            }
            index += 1
        }
        return collapsed.enumerated().compactMap { drop.contains($0.offset) ? nil : $0.element }
    }

    private func assignPlayerIndex(_ controller: GCController) {
        let used = Set(GCController.controllers().map(\.playerIndex))
        let slots: [GCControllerPlayerIndex] = [.index1, .index2, .index3, .index4]
        if let free = slots.first(where: { !used.contains($0) && $0 != .indexUnset }) {
            controller.playerIndex = free
        }
    }
}

private final class ControllerSession {
    let sessionID: String
    let category: String
    let displayName: String
    var elementNames: [String]
    let controller: GCController
    private weak var owner: ControllerMonitor?
    private var buttons: [GCControllerButtonInput] = []
    private var dpads: [GCControllerDirectionPad] = []
    private var axes: [GCControllerAxisInput] = []
    private var bound: Set<String> = []
    /// Last edge sent for an analog trigger, so value and pressed callbacks share one press.
    private var triggerLatched: [String: Bool] = [:]
    private var motionInstalled = false
    private let lock = NSLock()
    /// Serial queue GameController uses for this pad. Never the main queue.
    let handlerQueue: DispatchQueue

    init(controller: GCController, owner: ControllerMonitor) {
        self.controller = controller
        self.owner = owner
        category = controller.productCategory
        let vendor = controller.vendorName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let vendor, !vendor.isEmpty, vendor != category {
            displayName = "\(vendor) · \(category)"
        } else if category.isEmpty {
            displayName = "Controller"
        } else {
            displayName = category
        }
        let bits = UInt(bitPattern: ObjectIdentifier(controller))
        sessionID = "\(category)#\(bits)"
        let profile = controller.physicalInputProfile
        elementNames = (Array(profile.buttons.keys) + Array(profile.dpads.keys)).sorted()
        handlerQueue = DispatchQueue(label: "app.gamepadkeymapper.pad.\(sessionID)", qos: .userInteractive)
        controller.handlerQueue = handlerQueue
    }

    func installHandlers() {
        let profile = controller.physicalInputProfile
        let extended = controller.extendedGamepad
        let micro = controller.microGamepad
        // Lock a lone Joy-Con to its portrait frame, then rotate into the horizontal grip.
        // Leaving the system rotation on fights that correction and the hat names stay wrong.
        let orientation = JoyConOrientation.matching(category)
        if orientation != nil {
            micro?.reportsAbsoluteDpadValues = true
        }

        for (name, button) in profile.buttons {
            let names = [name] + Self.elementNames(button)
            bind(button, to: oriented(Self.bestButton(for: names, fallback: name), orientation))
        }
        // Analog ZR/ZL often exist on the extended profile but are absent from `profile.buttons`.
        // ConMapper still sees them there. Dedup keeps a button that was already bound.
        bindExtendedControls(extended)
        bindShoulderAndTriggerElements(in: profile)

        var left = profile.dpads[GCInputLeftThumbstick] ?? extended?.leftThumbstick
        let right = profile.dpads[GCInputRightThumbstick] ?? extended?.rightThumbstick
        var hat = profile.dpads[GCInputDirectionPad] ?? extended?.dpad
        var leftDirectsDpad = false

        // A lone Joy-Con often exposes its stick as the micro gamepad d-pad and nothing else.
        if left == nil, let microPad = micro?.dpad {
            left = microPad
            leftDirectsDpad = true
            if hat === microPad {
                hat = nil
            }
        }
        if let hat, hat !== left, hat !== right {
            bind(hat.up, to: oriented(.dpadUp, orientation))
            bind(hat.down, to: oriented(.dpadDown, orientation))
            bind(hat.left, to: oriented(.dpadLeft, orientation))
            bind(hat.right, to: oriented(.dpadRight, orientation))
        }
        if bound.isEmpty, let micro {
            bind(micro.buttonA, to: .a)
            bind(micro.buttonX, to: .x)
        }

        watchStick(left, side: .left, directsDpad: leftDirectsDpad, orientation: orientation)
        watchStick(right, side: .right, directsDpad: false, orientation: orientation)
        elementNames = bound.sorted().map { ControllerButton(id: $0).displayName }
        schedulePropertyRefresh()
    }

    func setMotionHandler(enabled: Bool) {
        lock.lock()
        guard enabled != motionInstalled else {
            lock.unlock()
            return
        }
        motionInstalled = enabled
        lock.unlock()
        let controller = controller
        handlerQueue.async { [weak self] in
            guard let self, let motion = controller.motion else { return }
            if motion.sensorsRequireManualActivation {
                motion.sensorsActive = enabled
            }
            if enabled {
                motion.valueChangedHandler = { [weak self] motion in
                    guard let self, motion.hasRotationRate else { return }
                    let rate = motion.rotationRate
                    self.owner?.enqueueMotion(InputBatch.Motion(
                        sessionID: self.sessionID,
                        category: self.category,
                        rotationX: rate.x,
                        rotationY: rate.y,
                        time: CACurrentMediaTime()
                    ))
                }
            } else {
                motion.valueChangedHandler = nil
            }
        }
    }

    func detach() {
        lock.lock()
        motionInstalled = false
        let buttons = self.buttons
        let dpads = self.dpads
        let axes = self.axes
        self.buttons.removeAll()
        self.dpads.removeAll()
        self.axes.removeAll()
        self.triggerLatched.removeAll()
        lock.unlock()
        let controller = controller
        handlerQueue.async {
            if let motion = controller.motion {
                if motion.sensorsRequireManualActivation {
                    motion.sensorsActive = false
                }
                motion.valueChangedHandler = nil
            }
            for button in buttons {
                button.pressedChangedHandler = nil
                button.valueChangedHandler = nil
            }
            for dpad in dpads {
                dpad.valueChangedHandler = nil
            }
            for axis in axes {
                axis.valueChangedHandler = nil
            }
        }
    }

    func batteryText() -> String? {
        schedulePropertyRefresh()
        lock.lock()
        defer { lock.unlock() }
        return cachedBattery
    }

    var hasMotion: Bool {
        schedulePropertyRefresh()
        lock.lock()
        defer { lock.unlock() }
        return cachedHasMotion
    }

    /// Shoulders and triggers from the extended profile, including ones missing from `profile.buttons`.
    private func bindExtendedControls(_ extended: GCExtendedGamepad?) {
        guard let extended else { return }
        bind(extended.buttonA, to: .a)
        bind(extended.buttonB, to: .b)
        bind(extended.buttonX, to: .x)
        bind(extended.buttonY, to: .y)
        bind(extended.leftShoulder, to: .leftShoulder)
        bind(extended.rightShoulder, to: .rightShoulder)
        bind(extended.leftTrigger, to: .leftTrigger)
        bind(extended.rightTrigger, to: .rightTrigger)
        bind(extended.buttonMenu, to: .menu)
        if let options = extended.buttonOptions {
            bind(options, to: .options)
        }
        if let home = extended.buttonHome {
            bind(home, to: .home)
        }
        if let click = extended.leftThumbstickButton {
            bind(click, to: .leftStickClick)
        }
        if let click = extended.rightThumbstickButton {
            bind(click, to: .rightStickClick)
        }
    }

    /// Elements and axes whose names say ZL/ZR or Trigger, even when they are not dictionary buttons.
    private func bindShoulderAndTriggerElements(in profile: GCPhysicalInputProfile) {
        // Buttons first. An analog axis with a similar name must not claim ZR ahead of the real button.
        // `elements` is a name → element dictionary, so the loop variable is the element, not the pair.
        for (_, element) in profile.elements {
            guard let input = element as? GCControllerButtonInput,
                  let button = Self.shoulderOrTrigger(in: Self.elementNames(element)) else { continue }
            bind(input, to: button)
        }
        for (_, element) in profile.elements {
            guard let axis = element as? GCControllerAxisInput,
                  let button = Self.shoulderOrTrigger(in: Self.elementNames(element)),
                  button.isAnalogTrigger else { continue }
            bindAxis(axis, to: button)
        }
        for (name, axis) in profile.axes {
            guard let button = ControllerButton.standardShoulderOrTrigger(matching: name), button.isAnalogTrigger else { continue }
            bindAxis(axis, to: button)
        }
    }

    private func bind(_ input: GCControllerButtonInput, to button: ControllerButton) {
        guard bound.insert(button.id).inserted else { return }
        buttons.append(input)
        if button.id == ControllerButton.home.id || button.id == ControllerButton.options.id {
            input.preferredSystemGestureState = .disabled
        }
        let trigger = button.isAnalogTrigger
        input.pressedChangedHandler = { [weak self] _, value, pressed in
            guard let self else { return }
            if trigger {
                self.emitTrigger(button, value: value, pressed: pressed)
            } else {
                self.emit(button, pressed: pressed)
            }
        }
        // ZR/ZL are analog. Some pads update `value` and never flip `pressed`.
        if trigger {
            input.valueChangedHandler = { [weak self] _, value, pressed in
                self?.emitTrigger(button, value: value, pressed: pressed)
            }
        }
    }

    private func bindAxis(_ axis: GCControllerAxisInput, to button: ControllerButton) {
        guard button.isAnalogTrigger, bound.insert(button.id).inserted else { return }
        axes.append(axis)
        axis.valueChangedHandler = { [weak self] _, value in
            self?.emitTrigger(button, value: value, pressed: false)
        }
    }

    private func emit(_ button: ControllerButton, pressed: Bool) {
        owner?.enqueueEdge(InputBatch.Edge(
            sessionID: sessionID,
            category: category,
            button: button,
            pressed: pressed,
            time: CACurrentMediaTime()
        ))
    }

    /// Press at 0.25, release at 0.12, so a partial ZR pull still becomes one edge.
    private func emitTrigger(_ button: ControllerButton, value: Float, pressed: Bool) {
        let was = triggerLatched[button.id] ?? false
        let down: Bool
        if pressed || value >= 0.25 {
            down = true
        } else if value <= 0.12 {
            down = false
        } else {
            down = was
        }
        guard down != was else { return }
        triggerLatched[button.id] = down
        emit(button, pressed: down)
    }

    private func watchStick(
        _ pad: GCControllerDirectionPad?,
        side: StickSide,
        directsDpad: Bool,
        orientation: JoyConOrientation?
    ) {
        guard let pad else { return }
        dpads.append(pad)
        pad.valueChangedHandler = { [weak self] pad, x, y in
            guard let self else { return }
            let corrected = orientation?.horizontalStick(x: Double(x), y: Double(y))
            self.owner?.enqueueStick(InputBatch.Stick(
                sessionID: self.sessionID,
                category: self.category,
                side: side,
                x: corrected?.x ?? Double(x),
                y: corrected?.y ?? Double(y),
                time: CACurrentMediaTime(),
                directsDpad: directsDpad
            ))
        }
    }

    private func oriented(_ button: ControllerButton, _ orientation: JoyConOrientation?) -> ControllerButton {
        orientation?.remapDpad(button) ?? button
    }

    private var cachedBattery: String?
    private var cachedHasMotion = false

    private func schedulePropertyRefresh() {
        let controller = controller
        handlerQueue.async { [weak self] in
            guard let self else { return }
            let battery = Self.batteryText(controller.battery)
            let motion = controller.motion
            let hasMotion = motion?.hasRotationRate == true
            self.lock.lock()
            self.cachedBattery = battery
            self.cachedHasMotion = hasMotion
            self.lock.unlock()
        }
    }

    private static func batteryText(_ battery: GCDeviceBattery?) -> String? {
        guard let battery else { return nil }
        switch battery.batteryState {
        case .charging, .discharging, .full:
            let level = battery.batteryLevel
            // A lone Joy-Con often has a battery object whose level stays 0. That is
            // “not reported”, same as `.unknown` or a nil battery. Callers hide the row.
            guard level.isFinite, level > 0, level <= 1 else { return nil }
            let percent = Int((level * 100).rounded())
            return "\(percent)%"
        default:
            return nil
        }
    }

    private static func elementNames(_ element: GCControllerElement) -> [String] {
        var names = Array(element.aliases)
        if let name = element.localizedName { names.append(name) }
        if let name = element.unmappedLocalizedName { names.append(name) }
        if let name = element.sfSymbolsName { names.append(name) }
        return names
    }

    /// Prefers a trigger alias over a shoulder alias when one element carries both.
    private static func shoulderOrTrigger(in names: [String]) -> ControllerButton? {
        var shoulder: ControllerButton?
        for name in names {
            guard let match = ControllerButton.standardShoulderOrTrigger(matching: name) else { continue }
            if match.isAnalogTrigger { return match }
            if shoulder == nil { shoulder = match }
        }
        return shoulder
    }

    private static func bestButton(for names: [String], fallback: String) -> ControllerButton {
        var found: ControllerButton?
        for name in names {
            guard let match = knownButton(forName: name) else { continue }
            if match.isAnalogTrigger { return match }
            if found == nil { found = match }
        }
        return found ?? ControllerButton.namedGCElement(fallback)
    }

    private static func knownButton(forName name: String) -> ControllerButton? {
        switch name {
        case String(GCInputButtonA): return .a
        case String(GCInputButtonB): return .b
        case String(GCInputButtonX): return .x
        case String(GCInputButtonY): return .y
        case String(GCInputLeftShoulder): return .leftShoulder
        case String(GCInputRightShoulder): return .rightShoulder
        case String(GCInputLeftTrigger): return .leftTrigger
        case String(GCInputRightTrigger): return .rightTrigger
        case String(GCInputLeftThumbstickButton): return .leftStickClick
        case String(GCInputRightThumbstickButton): return .rightStickClick
        case String(GCInputButtonMenu): return .menu
        case String(GCInputButtonOptions): return .options
        case String(GCInputButtonHome): return .home
        case String(GCInputDualShockTouchpadButton): return .touchpad
        default:
            return directionPadButton(name) ?? ControllerButton.standardShoulderOrTrigger(matching: name)
        }
    }

    /// Joy-Con and some other pads name the hat buttons “Direction Pad Up” instead of a standard id.
    private static func directionPadButton(_ name: String) -> ControllerButton? {
        let normalized = name.lowercased()
        guard normalized.contains("direction pad") || normalized.contains("dpad") else { return nil }
        if normalized.contains("up") { return .dpadUp }
        if normalized.contains("down") { return .dpadDown }
        if normalized.contains("left") { return .dpadLeft }
        if normalized.contains("right") { return .dpadRight }
        return nil
    }
}
