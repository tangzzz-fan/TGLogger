/// A destination that can push buffered data to its backing store on demand.
///
/// ``LogDestination`` deliberately says nothing about durability: cheap sinks
/// like ``MemoryDestination`` have nothing to flush. Destinations that own
/// expensive I/O (``FileDestination``, future upload sinks) conform here so
/// callers — and wrappers such as ``QueuedDestination`` — can reach a known
/// durability point without downcasting.
public protocol FlushableDestination: LogDestination {
    /// Pushes whatever the destination has buffered to its backing store.
    /// Executes on the calling thread and may block.
    func flush()

    /// Flushes and releases the backing store. The destination stays usable:
    /// the next ``LogDestination/write(_:)`` reopens it.
    func close()
}
