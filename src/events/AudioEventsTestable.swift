import CoreGraphics

/// fork-local: which of an app's windows are playing audio. Stored on `Application`, read per tile.
enum AppAudio: Equatable {
    case silent
    /// the app sounds and has no tab strip to narrow it down, so every window of it shows the icon
    case allWindows
    /// the app has Chromium tab strips, and these windows hold a tab labelled as playing (possibly none)
    case windows(Set<CGWindowID>)

    /// `wid` is nil for a windowless app's tile, which never shows the icon: see `audio(_:)`.
    func includes(_ wid: CGWindowID?) -> Bool {
        switch self {
            case .silent: return false
            case .allWindows: return wid != nil
            case .windows(let wids): return wid.map { wids.contains($0) } ?? false
        }
    }
}

/// fork-local: the pure decisions behind `AudioEvents`. See `AudioEventsSpecs.md`.
enum AudioEventsTestable {
    /// What one window's AX tree said about a Chromium tab strip.
    enum TabStrip: Equatable {
        case none
        case tabs([String])
        /// the read failed part-way (busy app, a tab closed mid-read): neither a strip nor its absence
        case unreadable
    }

    /// Chromium appends the tab's alert state to each tab button's AX title: "<page title> - Audio playing",
    /// and Brave adds " - Memory usage - …" after it. The text follows the browser's UI language; only the
    /// English one is matched.
    static let audibleTabMarker = " - Audio playing"

    /// The app a sounding process belongs to: the process itself, else its nearest ancestor that is an app.
    /// Chromium plays from a helper whose parent is the browser; `afplay` in Terminal sits under zsh and login.
    /// `ancestry` starts at the sounding process and stops before launchd, so an XPC service owned by an app
    /// (Safari's WebKit GPU process) is not attributed.
    static func owningApp(_ ancestry: [pid_t], appPids: Set<pid_t>) -> pid_t? {
        ancestry.first { appPids.contains($0) }
    }

    /// The windows of one sounding app to mark, or nil when the read proves nothing: a window failed to read,
    /// or AltTab knows no window of the app (yet: apps are discovered before their windows at launch).
    static func audio(_ strips: [CGWindowID: TabStrip]) -> AppAudio? {
        guard !strips.isEmpty else { return nil }
        let audible = Set(strips.compactMap { wid, strip in isAudible(strip) ? wid : nil })
        guard audible.isEmpty else { return .windows(audible) }
        guard !strips.values.contains(.unreadable) else { return nil }
        return strips.values.contains(where: hasTabs) ? .windows([]) : .allWindows
    }

    private static func isAudible(_ strip: TabStrip) -> Bool {
        guard case .tabs(let titles) = strip else { return false }
        return titles.contains { $0.contains(audibleTabMarker) }
    }

    private static func hasTabs(_ strip: TabStrip) -> Bool {
        guard case .tabs = strip else { return false }
        return true
    }
}
