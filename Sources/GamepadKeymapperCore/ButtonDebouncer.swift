import Foundation

struct ButtonDebouncer: Equatable {
    var interval: TimeInterval
    private(set) var committed = false
    private var raw = false
    private var hasSample = false
    /// Chatter before this time cannot change the committed state.
    private var lockedUntil = 0.0

    init(interval: TimeInterval) {
        self.interval = max(0, interval)
    }

    /// Feeds a raw edge or a repeated sample. Returns the newly committed pressed state when it changes.
    ///
    /// The first edge commits immediately. Further changes inside the debounce window are held
    /// until the window ends, so a bounce does not add a delay to the next real press.
    mutating func ingest(rawPressed: Bool, time: TimeInterval) -> Bool? {
        if !hasSample {
            hasSample = true
            raw = rawPressed
            committed = rawPressed
            lockedUntil = time + interval
            return committed
        }
        raw = rawPressed
        return commitIfUnlocked(time: time)
    }

    /// Treats `rawPressed` as already committed so a listen press is not emitted again when the lockout ends.
    mutating func noteCommitted(rawPressed: Bool, time: TimeInterval) {
        hasSample = true
        raw = rawPressed
        committed = rawPressed
        lockedUntil = time + interval
    }

    /// Commits a raw state that changed during the lockout, once the window has elapsed.
    /// The app schedules a single timer for `wakeTime()` instead of polling.
    mutating func poll(time: TimeInterval) -> Bool? {
        guard hasSample else { return nil }
        return commitIfUnlocked(time: time)
    }

    /// When a change arrived during the lockout and is still pending, the time it may commit.
    func wakeTime() -> TimeInterval? {
        guard hasSample, raw != committed, interval > 0 else { return nil }
        return lockedUntil
    }

    private mutating func commitIfUnlocked(time: TimeInterval) -> Bool? {
        guard raw != committed else { return nil }
        guard interval <= 0 || time >= lockedUntil else { return nil }
        committed = raw
        lockedUntil = time + interval
        return committed
    }
}
