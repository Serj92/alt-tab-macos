import CoreGraphics

/// fork-local: the pure half of `PinnedWindows`. See `PinnedWindowsSpecs.md`.
enum PinnedWindowsTestable {
    /// A new pin goes right of the older ones; pinning a pinned window unpins it.
    static func toggled(_ pins: [CGWindowID], _ wid: CGWindowID) -> [CGWindowID] {
        pins.contains(wid) ? pins.filter { $0 != wid } : pins + [wid]
    }

    /// Drops the pins the WindowServer said no longer exist. A failed query (`alive == nil`) proves nothing,
    /// and a pin added while the query was in flight was not asked about, so both stay.
    static func pruned(_ pins: [CGWindowID], queried: [CGWindowID], alive: Set<CGWindowID>?) -> [CGWindowID] {
        guard let alive else { return pins }
        let queried = Set(queried)
        return pins.filter { !queried.contains($0) || alive.contains($0) }
    }

    /// Window numbers start over at every boot, so pins saved in another boot could name a stranger's window.
    /// An unknown boot on either side counts as another boot.
    static func restored(_ stored: [CGWindowID], storedBoot: Int?, currentBoot: Int?) -> [CGWindowID] {
        guard let storedBoot, let currentBoot, storedBoot == currentBoot else { return [] }
        return stored
    }
}
