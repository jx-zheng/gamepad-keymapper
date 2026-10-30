import Foundation

/// How the two macOS checks combine.
///
/// Do not require both. `AXIsProcessTrusted` can be true while `CGPreflightPostEventAccess`
/// stays false for an ad-hoc debug build. ANDing them left the “Accessibility is off”
/// banner up after the user had already allowed the app and relaunched.
struct AccessibilityTrust: Equatable {
    var accessibilityGranted: Bool
    var canPostEvents: Bool

    /// Keys and clicks may be posted when either check has succeeded.
    var allowsInjection: Bool { accessibilityGranted || canPostEvents }

    /// The sticky “Accessibility is off” banner. It goes away as soon as Accessibility is granted.
    var accessibilityIsOff: Bool { !accessibilityGranted }

    /// Which check failed, when they disagree or both fail. Nil when injection is fully allowed.
    var failure: Failure? {
        switch (accessibilityGranted, canPostEvents) {
        case (true, true):
            return nil
        case (true, false):
            return .posting
        case (false, true):
            return .accessibility
        case (false, false):
            return .both
        }
    }

    enum Failure: Equatable {
        case accessibility
        case posting
        case both
    }
}
