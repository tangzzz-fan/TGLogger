import Foundation

/// When ``FileDestination`` pushes written lines all the way to storage.
///
/// `FileHandle.write` already lands in the kernel page cache, so lines survive
/// process death — including jetsam kills — without any flush. `synchronize()`
/// only protects against device-level power loss or kernel panic, and it costs a
/// storage round trip **on the calling thread**. That is why it is never the
/// default: logging happens on the main thread, and one `fsync` per line there
/// turns into multi-second UI stalls on real hardware.
public enum FileFlushPolicy: Sendable, Equatable {
    /// Flush on rotation and on ``FileDestination/close()``.
    ///
    /// Call ``FileDestination/flush()`` when an explicit durability point is
    /// needed (before sharing files, before a manual reboot test, …).
    case never

    /// Flush from a background timer every `interval` seconds.
    ///
    /// The flush happens off the calling thread, so the durability/power-loss
    /// trade-off costs nothing at the call site. Values below 50 ms are clamped.
    case interval(TimeInterval)

    /// Flush after every line.
    ///
    /// Matches the 0.3.0 / 0.4.0 behavior. Blocks the calling thread on storage
    /// I/O; only sensible for very low-volume logging or tests that must not
    /// call ``FileDestination/flush()``.
    case everyWrite

    /// Timer period for ``interval(_:)``, `nil` for the other policies.
    var timerInterval: TimeInterval? {
        guard case let .interval(value) = self else { return nil }
        return max(0.05, value)
    }
}
