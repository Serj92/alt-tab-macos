import Cocoa
import CoreAudio

/// fork-local: marks the windows that are playing audio. CoreAudio says which processes are outputting
/// (macOS 14.2+, no permission needed); a sounding Chromium browser's tab strips say which window holds the
/// audible tab. See `AudioEventsSpecs.md`.
class AudioEvents {
    /// CoreAudio delivers its listener blocks here and its property reads run here, off main.
    private static let queue = DispatchQueue(label: "audioEvents", qos: .utility)
    /// Chromium's strip sits 7 AXGroups under the window (Brave, Helium); headroom for other layouts.
    private static let maxStripDepth = 10
    /// queue-confined
    private static var listenedProcessObjects = Set<AudioObjectID>()
    /// main-confined
    private static var soundingApps = Set<pid_t>()

    static func observe() {
        guard #available(macOS 14.2, *) else { return }
        BackgroundWork.addPotentialThreadCount(1)
        queue.async {
            guard listen(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList) else { return }
            refresh(rescan: false)
        }
    }

    /// Which tab plays can change without CoreAudio noticing (another tab starts within the same output
    /// stream, a tab is dragged to another window), and an earlier read may have proved nothing, so each
    /// summon re-reads every sounding app. A strip-less app costs 10-20 AX calls.
    static func switcherShown() {
        guard #available(macOS 14.2, *) else { return }
        queue.async { refresh(rescan: true) }
    }

    @available(macOS 14.2, *)
    private static func refresh(rescan: Bool) {
        guard let objects = processObjects() else { return }
        listenedProcessObjects.formIntersection(objects)
        for object in objects where !listenedProcessObjects.contains(object) {
            if listen(object, kAudioProcessPropertyIsRunningOutput) { listenedProcessObjects.insert(object) }
        }
        let ancestries = objects.filter { scalar($0, kAudioProcessPropertyIsRunningOutput) == 1 }
            .compactMap { scalar($0, kAudioProcessPropertyPID).map { ancestry(pid_t(bitPattern: $0)) } }
        DispatchQueue.main.async { apply(ancestries, rescan: rescan) }
    }

    private static func apply(_ ancestries: [[pid_t]], rescan: Bool) {
        let appPids = Set(Applications.list.map { $0.pid })
        let sounding = Set(ancestries.compactMap { AudioEventsTestable.owningApp($0, appPids: appPids) })
        for pid in soundingApps.subtracting(sounding) { setAudio(pid, .silent) }
        let toScan = rescan ? sounding : sounding.subtracting(soundingApps)
        soundingApps = sounding
        toScan.forEach(scanTabStrips)
    }

    private static func setAudio(_ pid: pid_t, _ audio: AppAudio) {
        guard let app = Applications.list.first(where: { $0.pid == pid }), app.audio != audio else { return }
        Logger.info { "\(app.localizedName ?? "?") pid:\(pid) audio:\(audio)" }
        app.audio = audio
        App.refreshOpenUiAfterExternalEvent([])
    }

    /// ceiling: re-finds every strip on each read, ~1100 AX calls and 80-110ms for 44 Brave windows (measured);
    /// cache the strip element per wid if Brave ever stutters while the switcher opens during playback.
    private static func scanTabStrips(_ pid: pid_t) {
        let windows = Windows.list.compactMap { window -> (CGWindowID, AXUIElement?)? in
            guard window.application.pid == pid, let wid = window.cgWindowId else { return nil }
            return (wid, window.axUiElement)
        }
        AXCallScheduler.shared.schedule(key: "audioTabStrips-\(pid)", pid: pid, scan: true) {
            // a window AltTab holds no AX element for yet (right after launch) is unknown, not strip-less
            let strips = Dictionary(windows.map { ($0.0, $0.1.map { tabStrip($0, pid) } ?? .unreadable) }, uniquingKeysWith: { first, _ in first })
            DispatchQueue.main.async {
                guard soundingApps.contains(pid) else { return }
                guard let audio = AudioEventsTestable.audio(strips) else {
                    Logger.info { "pid:\(pid) tab strips unreadable, keeping the previous answer" }
                    return
                }
                setAudio(pid, audio)
            }
        }
    }

    private static func tabStrip(_ window: AXUIElement, _ pid: pid_t) -> AudioEventsTestable.TabStrip {
        do {
            guard let strip = try findTabStrip(window, pid, depth: 0) else { return .none }
            let tabs = try strip.attributes([kAXChildrenAttribute], pid: pid).children ?? []
            return .tabs(try tabs.compactMap { tab in
                let attributes = try tab.attributes([kAXSubroleAttribute, kAXTitleAttribute], pid: pid)
                return attributes.subrole == "AXTabButton" ? attributes.title ?? "" : nil
            })
        } catch {
            return .unreadable
        }
    }

    /// Descends through AXGroups only: Chromium's path to its strip is nothing but groups, and stopping at
    /// anything else keeps a non-browser's big tree (tables, web areas) out of the read. The strip is never
    /// a direct child of the window; that one is macOS's own tab bar (Finder, Terminal), which carries no
    /// audio state.
    private static func findTabStrip(_ element: AXUIElement, _ pid: pid_t, depth: Int) throws -> AXUIElement? {
        let attributes = try element.attributes([kAXRoleAttribute, kAXChildrenAttribute], pid: pid)
        if attributes.role == kAXTabGroupRole, depth > 1 { return element }
        guard depth == 0 || attributes.role == kAXGroupRole, depth < maxStripDepth else { return nil }
        for child in attributes.children ?? [] {
            if let strip = try findTabStrip(child, pid, depth: depth + 1) { return strip }
        }
        return nil
    }

    @available(macOS 14.2, *)
    private static func processObjects() -> [AudioObjectID]? {
        var address = propertyAddress(kAudioHardwarePropertyProcessObjectList)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects)
        guard status == noErr else {
            Logger.error { "process object list status:\(status)" }
            return nil
        }
        return Array(objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func scalar(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = propertyAddress(selector)
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func listen(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = propertyAddress(selector)
        let status = AudioObjectAddPropertyListenerBlock(object, &address, queue) { _, _ in
            guard #available(macOS 14.2, *) else { return }
            refresh(rescan: false)
        }
        if status != noErr { Logger.error { "object:\(object) selector:\(selector) status:\(status)" } }
        return status == noErr
    }

    private static func propertyAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    /// The sounding pid, then its parents up to (not including) launchd. Unbounded on purpose: `afplay` run by a
    /// tool inside Terminal sits 5 hops down (afplay → zsh → tool → zsh → login → Terminal, measured). The
    /// count only guards the loop.
    private static func ancestry(_ pid: pid_t) -> [pid_t] {
        var chain = [pid]
        while chain.count < 64, let parent = parentPid(chain.last!), parent > 1 { chain.append(parent) }
        return chain
    }

    /// `sysctl`, not `proc_pidinfo`: the latter fails with EPERM on root-owned processes, and Terminal's
    /// `login` is one, which cut every Terminal chain short (measured).
    private static func parentPid(_ pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
