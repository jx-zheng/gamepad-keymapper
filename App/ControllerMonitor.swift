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
    let elementNames: [String]
    let controller: GCController
    private weak var owner: ControllerMonitor?
    private var buttons: [GCControllerButtonInput] = []
    private var dpads: [GCControllerDirectionPad] = []
    private var bound: Set<String> = []
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

        for (name, button) in profile.buttons {
            bind(button, to: Self.logicalButton(forGCName: name))
        }

        var left = profile.dpads[GCInputLeftThumbstick] ?? extended?.leftThumbstick
        let right = profile.dpads[GCInputRightThumbstick] ?? extended?.rightThumbstick
        var hat = profile.dpads[GCInputDirectionPad] ?? extended?.dpad

        // A lone Joy-Con often exposes its stick as the micro gamepad d-pad and nothing else.
        if left == nil, let microPad = micro?.dpad {
            left = microPad
            if hat === microPad {
                hat = nil
            }
        }
        if let hat, hat !== left, hat !== right {
            bind(hat.up, to: .dpadUp)
            bind(hat.down, to: .dpadDown)
            bind(hat.left, to: .dpadLeft)
            bind(hat.right, to: .dpadRight)
        }
        if bound.isEmpty, let micro {
            bind(micro.buttonA, to: .a)
            bind(micro.buttonX, to: .x)
        }

        watchStick(left, side: .left)
        watchStick(right, side: .right)
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
        self.buttons.removeAll()
        self.dpads.removeAll()
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

    private func bind(_ input: GCControllerButtonInput, to button: ControllerButton) {
        guard bound.insert(button.id).inserted else { return }
        buttons.append(input)
        if button.id == ControllerButton.home.id || button.id == ControllerButton.options.id {
            input.preferredSystemGestureState = .disabled
        }
        input.pressedChangedHandler = { [weak self] _, _, pressed in
            guard let self else { return }
            self.owner?.enqueueEdge(InputBatch.Edge(
                sessionID: self.sessionID,
                category: self.category,
                button: button,
                pressed: pressed,
                time: CACurrentMediaTime()
            ))
        }
    }

    private func watchStick(_ pad: GCControllerDirectionPad?, side: StickSide) {
        guard let pad else { return }
        dpads.append(pad)
        pad.valueChangedHandler = { [weak self] pad, x, y in
            guard let self else { return }
            self.owner?.enqueueStick(InputBatch.Stick(
                sessionID: self.sessionID,
                category: self.category,
                side: side,
                x: Double(x),
                y: Double(y),
                time: CACurrentMediaTime()
            ))
        }
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
            let percent = Int((battery.batteryLevel * 100).rounded())
            return "\(percent)%"
        default:
            return nil
        }
    }

    private static func logicalButton(forGCName name: String) -> ControllerButton {
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
            return ControllerButton.namedGCElement(name)
        }
    }
}
