import Foundation

struct ButtonDebouncer: Equatable {
    var interval: TimeInterval
    private(set) var committed = false
    private var raw = false
    private var lastChange = 0.0
    private var hasSample = false

    init(interval: TimeInterval) {
        self.interval = max(0, interval)
    }

    /// Feeds a raw edge or a repeated sample. Returns the newly committed pressed state when it changes.
    mutating func ingest(rawPressed: Bool, time: TimeInterval) -> Bool? {
        if !hasSample {
            hasSample = true
            raw = rawPressed
            lastChange = time
            return commitIfStable(time: time)
        }
        if rawPressed != raw {
            raw = rawPressed
            lastChange = time
        }
        return commitIfStable(time: time)
    }

    /// Commits a raw state that has been stable long enough.
    /// The app schedules a single timer for `wakeTime()` instead of polling.
    mutating func poll(time: TimeInterval) -> Bool? {
        guard hasSample else { return nil }
        return commitIfStable(time: time)
    }

    /// When the raw state has not been committed yet, the time at which it should be committed.
    func wakeTime() -> TimeInterval? {
        guard hasSample, raw != committed, interval > 0 else { return nil }
        return lastChange + interval
    }

    private mutating func commitIfStable(time: TimeInterval) -> Bool? {
        guard raw != committed else { return nil }
        guard interval <= 0 || time - lastChange >= interval else { return nil }
        committed = raw
        return committed
    }
}
