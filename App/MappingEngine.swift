import Foundation
import os
import QuartzCore

/// Runs mapping off the main thread.
///
/// Controller callbacks are coalesced onto `queue`. A debounce timer exists only while a
/// release is waiting out the chatter window, and a pointer timer exists only while a button
/// is holding a mouse-move action. Nothing is scheduled while the app is idle.
final class MappingEngine {
    var onControllers: (([ControllerSnapshot]) -> Void)?
    var onCapture: ((ControllerButton) -> Void)?
    var onStatus: ((String) -> Void)?
    /// A controller button went down. This fires even when Accessibility blocks the injected event.
    var onInput: ((String) -> Void)?
    var onInjectionBlocked: (() -> Void)?

    private let queue = DispatchQueue(label: "app.gamepadkeymapper.mapper", qos: .userInteractive)
    private static let queueTokenKey = DispatchSpecificKey<UInt8>()
    private let signposter = OSSignposter(subsystem: "app.gamepadkeymapper", category: "mapping")
    private var interpreter = MappingInterpreter()
    private var profile: Profile?
    private var mappingEnabled = true
    private var monitor: ControllerMonitor!
    private var synthesizer: InputSynthesizer!
    private var debounceTimer: DispatchSourceTimer?
    /// Absolute time the debounce timer is armed for. Pointer pumping must not rebuild it every tick.
    private var debounceWake: TimeInterval?
    private var pointerTimer: DispatchSourceTimer?
    private var uiTimer: DispatchSourceTimer?
    private var devicesVisible = false
    private var trusted = false
    private var lastTrustCheck = 0.0
    private var lastStatus = ""
    private var lastStatusTime = 0.0
    private var lastMotionTime: [String: TimeInterval] = [:]
    private var motionHoldGeneration: UInt64 = 0
    private var motionProfileID: UUID?
    private var motionEnabled = false
    private let radial = RadialOverlay()

    init() {
        queue.setSpecific(key: Self.queueTokenKey, value: 1)
        synthesizer = InputSynthesizer(queue: queue)
        monitor = ControllerMonitor(queue: queue)
        monitor.onBatch = { [weak self] batch in
            self?.handle(batch)
        }
        monitor.onTopology = { [weak self] in
            self?.queue.async {
                self?.publishControllers()
            }
        }
        monitor.onDisconnected = { [weak self] sessionID in
            self?.queue.async {
                self?.handleDisconnect(sessionID)
            }
        }
    }

    func start() {
        trusted = AccessibilityPermission.isTrusted(prompt: false)
        lastTrustCheck = CACurrentMediaTime()
        monitor.start()
    }

    func shutdown() {
        let finish = {
            self.debounceTimer?.cancel()
            self.debounceTimer = nil
            self.debounceWake = nil
            self.pointerTimer?.cancel()
            self.pointerTimer = nil
            self.uiTimer?.cancel()
            self.uiTimer = nil
            let effects = self.interpreter.resetInteractions()
            for effect in effects {
                if case .actionEnded(let action) = effect {
                    self.synthesizer.end(action)
                }
            }
            self.synthesizer.releaseAll()
            // stop() only queues controller cleanup. It must not sync back to main,
            // or quit deadlocks while this block is running inside queue.sync.
            self.monitor.stop()
        }
        if DispatchQueue.getSpecific(key: Self.queueTokenKey) != nil {
            finish()
        } else {
            queue.sync(execute: finish)
        }
        DispatchQueue.main.async { [radial] in
            radial.hide()
        }
    }

    func setProfile(_ profile: Profile?) {
        queue.async {
            self.lastMotionTime.removeAll()
            let previous = self.profile
            self.profile = profile
            if let profile {
                if previous?.id != profile.id {
                    self.perform(self.interpreter.endSustainedActions())
                }
            } else if previous != nil {
                // Edges are ignored while nothing is selected. Leaving the debouncer pressed
                // made the next real press do nothing until an extra release.
                self.perform(self.interpreter.resetInteractions())
            }
            self.refreshMotion()
        }
    }

    func setTuning(debounce: TimeInterval, deadzone: Double, release: Double, enabled: Bool) {
        queue.async {
            self.interpreter.debounce = debounce
            self.interpreter.stickDeadzone = deadzone
            self.interpreter.stickReleaseZone = min(release, deadzone)
            if self.mappingEnabled && !enabled {
                self.mappingEnabled = false
                self.perform(self.interpreter.resetInteractions())
            } else {
                self.mappingEnabled = enabled
            }
            self.refreshMotion()
        }
    }

    func setDevicesVisible(_ visible: Bool) {
        queue.async {
            self.devicesVisible = visible
            if visible {
                self.startUITimer()
                self.publishControllers()
            } else {
                self.uiTimer?.cancel()
                self.uiTimer = nil
            }
        }
    }

    func armCapture() {
        onMapperQueue {
            self.interpreter.captureNextPress = true
        }
    }

    func disarmCapture() {
        onMapperQueue {
            self.interpreter.captureNextPress = false
        }
    }

    /// Sets the listen flag before returning so the next controller event cannot pass through first.
    private func onMapperQueue(_ body: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: Self.queueTokenKey) != nil {
            body()
        } else {
            queue.sync(execute: body)
        }
    }

    func releaseHeldInputs() {
        queue.async {
            self.perform(self.interpreter.endSustainedActions())
            self.synthesizer.releaseAll()
        }
    }

    func invalidateTrust() {
        queue.async {
            self.lastTrustCheck = 0
            _ = self.ensureTrusted()
        }
    }

    func test(_ action: MapperAction) {
        queue.async { [weak self] in
            guard let self else { return }
            self.perform([.actionBegan(action)])
            guard action.sustainsWhileHeld else { return }
            self.queue.asyncAfter(deadline: .now() + 0.05) {
                self.perform([.actionEnded(action)])
            }
        }
    }

    private func handle(_ batch: InputBatch) {
        let state = signposter.beginInterval("Handle Input")
        defer { signposter.endInterval("Handle Input", state) }
        guard let profile else { return }
        var effects: [EngineEffect] = []
        for edge in batch.edges {
            if edge.pressed {
                noteInput(edge.button.displayName)
            }
            effects += interpreter.ingestButton(
                controller: edge.sessionID,
                category: edge.category,
                button: edge.button,
                rawPressed: edge.pressed,
                time: edge.time,
                profile: profile
            )
        }
        for stick in batch.sticks {
            effects += interpreter.ingestStick(
                controller: stick.sessionID,
                category: stick.category,
                side: stick.side,
                x: stick.x,
                y: stick.y,
                time: stick.time,
                profile: profile,
                directsDpad: stick.directsDpad
            )
        }
        if mappingEnabled, profile.gyro.enabled {
            for sample in batch.motion {
                let held = interpreter.heldButtonIDs(controller: sample.sessionID)
                guard profile.gyro.activation.isActive(held: held) else {
                    self.lastMotionTime[sample.sessionID] = nil
                    continue
                }
                let previous = lastMotionTime[sample.sessionID] ?? sample.time
                lastMotionTime[sample.sessionID] = sample.time
                let dt = min(0.05, max(0, sample.time - previous))
                guard dt > 0 else { continue }
                guard let delta = GyroPointer.delta(
                    rotationX: sample.rotationX,
                    rotationY: sample.rotationY,
                    deadzone: profile.gyro.deadzone,
                    sensitivity: profile.gyro.sensitivity,
                    invertX: profile.gyro.invertX,
                    invertY: profile.gyro.invertY,
                    dt: dt
                ) else { continue }
                effects.append(.pointerDelta(dx: delta.dx, dy: delta.dy))
            }
        } else {
            lastMotionTime.removeAll()
        }
        perform(effects)
    }

    private func handleDisconnect(_ sessionID: String) {
        lastMotionTime[sessionID] = nil
        perform(interpreter.clearController(sessionID))
        publishControllers()
    }

    private func perform(_ effects: [EngineEffect]) {
        for effect in effects {
            switch effect {
            case .actionBegan(let action):
                guard mappingEnabled else { continue }
                dispatch(action)
            case .actionEnded(let action):
                synthesizer.end(action)
            case .pointerDelta(let dx, let dy):
                guard mappingEnabled, ensureTrusted() else { continue }
                synthesizer.move(dx: dx, dy: dy)
            case .scrollDelta(let dx, let dy):
                guard mappingEnabled, ensureTrusted() else { continue }
                synthesizer.scroll(dx: dx, dy: dy)
            case .showRadial(let menu, let selection):
                guard mappingEnabled else { continue }
                DispatchQueue.main.async { [radial] in
                    radial.show(menu: menu, selection: selection)
                }
            case .updateRadial(let selection):
                DispatchQueue.main.async { [radial] in
                    radial.update(selection: selection)
                }
            case .hideRadial:
                DispatchQueue.main.async { [radial] in
                    radial.hide()
                }
            case .layersChanged:
                break
            case .captured(let button):
                DispatchQueue.main.async { [weak self] in
                    self?.onCapture?(button)
                }
            }
        }
        armTimers()
        refreshMotionIfNeeded()
    }

    private func dispatch(_ action: MapperAction) {
        switch action {
        case .shortcut(let name):
            ShortcutRunner.shared.run(name: name) { [weak self] message in
                self?.report(message)
            }
        case .launchApp(let launch):
            AppLauncher.open(launch) { [weak self] message in
                self?.report(message)
            }
        default:
            guard ensureTrusted() else {
                report("Turn on Accessibility to send keys and pointer actions.")
                DispatchQueue.main.async { [weak self] in
                    self?.onInjectionBlocked?()
                }
                return
            }
            synthesizer.begin(action)
        }
    }

    private func ensureTrusted() -> Bool {
        let now = CACurrentMediaTime()
        if now - lastTrustCheck > 0.5 {
            lastTrustCheck = now
            trusted = AccessibilityPermission.isTrusted(prompt: false)
        }
        return trusted
    }

    private func noteInput(_ name: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onInput?(name)
        }
    }

    private func report(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let now = CACurrentMediaTime()
            if message == self.lastStatus, now - self.lastStatusTime < 2 { return }
            self.lastStatus = message
            self.lastStatusTime = now
            self.onStatus?(message)
        }
    }

    private func armTimers() {
        if let wake = interpreter.nextWakeTime() {
            scheduleDebounce(at: wake)
        } else if debounceTimer != nil {
            debounceTimer?.cancel()
            debounceTimer = nil
            debounceWake = nil
        }
        if mappingEnabled && interpreter.needsPointerPump {
            startPointerPumpIfNeeded()
        } else {
            pointerTimer?.cancel()
            pointerTimer = nil
        }
    }

    private func scheduleDebounce(at wake: TimeInterval) {
        if debounceTimer != nil, let debounceWake, abs(debounceWake - wake) < 0.0005 {
            return
        }
        debounceTimer?.cancel()
        debounceWake = wake
        let delay = max(0, wake - CACurrentMediaTime())
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + delay, leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.debounceTimer = nil
            self.debounceWake = nil
            guard let profile = self.profile else { return }
            let effects = self.interpreter.poll(time: CACurrentMediaTime(), profile: profile)
            self.perform(effects)
        }
        debounceTimer = timer
        timer.resume()
    }

    private func startPointerPumpIfNeeded() {
        guard pointerTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(16), repeating: .milliseconds(16), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            guard let self, let profile = self.profile else { return }
            let effects = self.interpreter.poll(time: CACurrentMediaTime(), profile: profile)
            self.perform(effects)
        }
        pointerTimer = timer
        timer.resume()
    }

    private func startUITimer() {
        guard uiTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250), leeway: .milliseconds(30))
        timer.setEventHandler { [weak self] in
            self?.publishControllers()
        }
        uiTimer = timer
        timer.resume()
    }

    private func refreshMotionIfNeeded() {
        let enabled = mappingEnabled && (profile?.gyro.enabled ?? false)
        guard interpreter.holdGeneration != motionHoldGeneration
            || profile?.id != motionProfileID
            || enabled != motionEnabled
        else { return }
        refreshMotion()
    }

    private func refreshMotion() {
        let gyro = profile?.gyro
        let enabled = mappingEnabled && (gyro?.enabled ?? false)
        motionHoldGeneration = interpreter.holdGeneration
        motionProfileID = profile?.id
        motionEnabled = enabled
        monitor.setMotionEnabled { [interpreter] sessionID in
            guard enabled, let gyro else { return false }
            return gyro.activation.isActive(held: interpreter.heldButtonIDs(controller: sessionID))
        }
    }

    private func publishControllers() {
        let snapshots = monitor.snapshots { [interpreter] sessionID in
            interpreter.heldButtonIDs(controller: sessionID).sorted()
        }
        DispatchQueue.main.async { [weak self] in
            self?.onControllers?(snapshots)
        }
    }
}
