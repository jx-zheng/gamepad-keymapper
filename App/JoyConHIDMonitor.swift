import Foundation
import IOKit
import IOKit.hid
import os

/// Listens to Joy-Con HID reports for the shoulder and trigger GameController does not map.
///
/// A lone Joy-Con is a micro gamepad: `extendedGamepad` is nil, and the profile’s
/// shoulders are the rail buttons. Report `0x3F` still carries physical R/ZR or L/ZL.
/// The device is opened without seizing it, so GameController keeps the other buttons.
final class JoyConHIDMonitor {
    private let log = Logger(subsystem: "app.gamepadkeymapper", category: "hid")
    private let onChange: (JoyConOrientation, ControllerButton, Bool) -> Void
    private var manager: IOHIDManager?
    private var pads: [ObjectIdentifier: HIDPad] = []
    private var started = false

    init(onChange: @escaping (JoyConOrientation, ControllerButton, Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        let start = { self.open() }
        if Thread.isMainThread {
            start()
        } else {
            DispatchQueue.main.async(execute: start)
        }
    }

    func stop() {
        let stop = { self.close() }
        if Thread.isMainThread {
            stop()
        } else {
            DispatchQueue.main.async(execute: stop)
        }
    }

    private func open() {
        guard !started else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Any]] = [
            [kIOHIDVendorIDKey as String: JoyConHIDReport.vendorID, kIOHIDProductIDKey as String: JoyConHIDReport.leftProductID],
            [kIOHIDVendorIDKey as String: JoyConHIDReport.vendorID, kIOHIDProductIDKey as String: JoyConHIDReport.rightProductID]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceAdded, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceRemoved, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let opened = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        started = true
        if opened != kIOReturnSuccess {
            log.error("Joy-Con HID manager open failed: \(opened, privacy: .public)")
        }
        if let raw = IOHIDManagerCopyDevices(manager) {
            for case let device as IOHIDDevice in raw as NSSet {
                add(device)
            }
        }
    }

    private func close() {
        guard started, let manager else { return }
        for pad in pads.values {
            pad.unregister()
        }
        pads.removeAll()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        started = false
    }

    fileprivate func add(_ device: IOHIDDevice) {
        let id = ObjectIdentifier(device)
        guard pads[id] == nil, let side = Self.side(of: device) else { return }
        let pad = HIDPad(side: side, device: device)
        pad.owner = self
        pads[id] = pad
        IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        pad.register()
        log.info("Joy-Con HID \(side == .left ? "L" : "R", privacy: .public) attached")
    }

    fileprivate func remove(_ device: IOHIDDevice) {
        let id = ObjectIdentifier(device)
        guard let pad = pads.removeValue(forKey: id) else { return }
        pad.releaseAll()
        pad.unregister()
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    fileprivate func handle(_ pad: HIDPad, reportID: UInt32, report: UnsafePointer<UInt8>, length: Int) {
        guard length > 0 else { return }
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        let packet: [UInt8]
        if reportID != 0 {
            if bytes.first == UInt8(truncatingIfNeeded: reportID) {
                packet = bytes
            } else {
                packet = [UInt8(truncatingIfNeeded: reportID)] + bytes
            }
        } else {
            packet = bytes
        }
        guard let down = JoyConHIDReport.supplementalButtons(packet: packet, side: pad.side) else { return }
        let pressed = Set(down.map(\.id))
        for id in pressed.subtracting(pad.down) {
            onChange(pad.side, ControllerButton(id: id), true)
        }
        for id in pad.down.subtracting(pressed) {
            onChange(pad.side, ControllerButton(id: id), false)
        }
        pad.down = pressed
    }

    private static func side(of device: IOHIDDevice) -> JoyConOrientation? {
        let vendor = number(device, kIOHIDVendorIDKey as CFString)
        let product = number(device, kIOHIDProductIDKey as CFString)
        guard vendor == JoyConHIDReport.vendorID, let product else { return nil }
        return JoyConHIDReport.side(productID: product)
    }

    private static func number(_ device: IOHIDDevice, _ key: CFString) -> Int? {
        let value = IOHIDDeviceGetProperty(device, key)
        if let number = value as? NSNumber { return number.intValue }
        if let number = value as? Int { return number }
        return nil
    }

    private static let deviceAdded: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        Unmanaged<JoyConHIDMonitor>.fromOpaque(context).takeUnretainedValue().add(device)
    }

    private static let deviceRemoved: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        Unmanaged<JoyConHIDMonitor>.fromOpaque(context).takeUnretainedValue().remove(device)
    }
}

private final class HIDPad {
    weak var owner: JoyConHIDMonitor?
    let side: JoyConOrientation
    let device: IOHIDDevice
    var down: Set<String> = []
    private let capacity = 401
    private let buffer: UnsafeMutablePointer<UInt8>
    private var registered = false

    init(side: JoyConOrientation, device: IOHIDDevice) {
        self.side = side
        self.device = device
        buffer = .allocate(capacity: capacity)
        buffer.initialize(repeating: 0, count: capacity)
    }

    deinit {
        buffer.deallocate()
    }

    func register() {
        guard !registered else { return }
        registered = true
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            capacity,
            Self.report,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    func unregister() {
        guard registered else { return }
        registered = false
        IOHIDDeviceRegisterInputReportCallback(device, buffer, capacity, nil, nil)
    }

    func releaseAll() {
        guard let owner else {
            down.removeAll()
            return
        }
        for id in down {
            owner.handleRelease(side: side, id: id)
        }
        down.removeAll()
    }

    private static let report: IOHIDReportCallback = { context, _, _, _, reportID, report, length in
        guard let context, let report, length > 0 else { return }
        let pad = Unmanaged<HIDPad>.fromOpaque(context).takeUnretainedValue()
        pad.owner?.handle(pad, reportID: reportID, report: report, length: length)
    }
}

private extension JoyConHIDMonitor {
    func handleRelease(side: JoyConOrientation, id: String) {
        onChange(side, ControllerButton(id: id), false)
    }
}
