import Cocoa

/// fork-local: the windows the user pinned to the front of the switcher, by wid, in pin order. The order rule
/// is `OrderWindow.pinRank`; the default pick ignores pins through `SelectionInputs.pickOrder`. See
/// `PinnedWindowsSpecs.md`.
enum PinnedWindows {
    /// A suite of its own: pins are state, not a preference, so a settings reset or import leaves them alone.
    private static let defaults = UserDefaults(suiteName: "\(App.bundleIdentifier).pins")
    private static let key = "pinnedWindows"
    private(set) static var wids: [CGWindowID] = load()

    static func rank(_ wid: CGWindowID?) -> Int? {
        wid.flatMap { wids.firstIndex(of: $0) }
    }

    static func toggle(_ window: Window) {
        guard let wid = window.cgWindowId else { return }
        save(PinnedWindowsTestable.toggled(wids, wid))
        Logger.info { "\(window.debugId) pinned:\(rank(wid) != nil)" }
        App.refreshOpenUiAfterExternalEvent([], immediately: true)
    }

    /// Asks the WindowServer rather than the model: a window leaves the model without closing (admission is
    /// re-run, see `Windows.removeWindows`), and a pin lives as long as its window does. Run on every summon,
    /// so a window closed while AltTab was not running is caught too.
    static func forgetClosedWindows() {
        let queried = wids
        guard !queried.isEmpty else { return }
        CGSCallScheduler.existingWindowIds(among: queried) { alive in
            let kept = PinnedWindowsTestable.pruned(wids, queried: queried, alive: alive)
            guard kept != wids else { return }
            Logger.info { "closed windows unpinned:\(wids.filter { !kept.contains($0) })" }
            save(kept)
        }
    }

    private static func save(_ new: [CGWindowID]) {
        wids = new
        defaults?.set(["boot": bootTime() ?? 0, "wids": new.map { Int($0) }], forKey: key)
    }

    private static func load() -> [CGWindowID] {
        let stored = defaults?.dictionary(forKey: key)
        let storedWids: [CGWindowID] = ((stored?["wids"] as? [Int]) ?? []).map { CGWindowID($0) }
        return PinnedWindowsTestable.restored(storedWids, storedBoot: stored?["boot"] as? Int, currentBoot: bootTime())
    }

    private static func bootTime() -> Int? {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return nil }
        return boot.tv_sec
    }
}
