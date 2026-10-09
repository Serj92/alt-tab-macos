import XCTest

/// fork-local: see `AudioEventsSpecs.md`. Pids, titles and labels are the ones measured on Brave and Terminal.
final class AudioEventsTests: XCTestCase {
    // MARK: owningApp

    /// Chromium outputs from a helper (`Brave Browser Helper`, 3348) whose parent is the browser (3187).
    func testHelperIsAttributedToItsBrowser() {
        XCTAssertEqual(AudioEventsTestable.owningApp([3348, 3187], appPids: [3187, 2071]), 3187)
    }

    /// An app launched by another app (Brave started from Terminal) is its own owner, not its parent's.
    func testSoundingAppIsItsOwnOwnerEvenUnderAnotherApp() {
        XCTAssertEqual(AudioEventsTestable.owningApp([3187, 11505], appPids: [3187, 11505]), 3187)
    }

    /// `afplay` run by a tool inside Terminal, as measured: afplay → zsh → claude → -zsh → login → Terminal.
    func testCommandDeepUnderTerminalIsAttributedToTerminal() {
        XCTAssertEqual(AudioEventsTestable.owningApp([4900, 4899, 12640, 11509, 11507, 11505], appPids: [11505, 3187]), 11505)
    }

    /// An XPC service's parent is launchd, so its chain holds only itself (Safari's WebKit GPU process).
    func testServiceWithNoAppAncestorIsNotAttributed() {
        XCTAssertNil(AudioEventsTestable.owningApp([771], appPids: [846, 3187]))
    }

    // MARK: audio(_:)

    func testOnlyTheWindowHoldingTheAudibleTabIsMarked() {
        let audio = AudioEventsTestable.audio([
            1: .tabs(["Settings - About Brave - Memory usage - 99.9 MB",
                      "Dlaczego w polskich filmach NIC nie słychać? - YouTube - Audio playing - Memory usage - 394 MB"]),
            2: .tabs(["Marstek 5kWt - Поиск в Google - Memory usage - 159 MB"]),
        ])
        XCTAssertEqual(audio, .windows([1]))
    }

    /// A page title that merely mentions audio is not Chromium's alert state.
    func testAudioInThePageTitleIsNotAudible() {
        let audio = AudioEventsTestable.audio([
            1: .tabs(["FluidInference/FluidAudio: Frontier CoreML audio models in your apps"]),
            2: .tabs(["Поиск • Threads - Memory usage - 302 MB"]),
        ])
        XCTAssertEqual(audio, .windows([]))
    }

    func testMutedTabIsNotAudible() {
        XCTAssertEqual(AudioEventsTestable.audio([1: .tabs(["Song - YouTube - Audio muted"])]), .windows([]))
    }

    /// A browser's popup or app window has no strip; its other windows still decide.
    func testOneStripIsEnoughToNarrowToTabs() {
        XCTAssertEqual(AudioEventsTestable.audio([1: .none, 2: .tabs(["Inbox"])]), .windows([]))
    }

    func testAppWithoutTabStripsMarksAllWindows() {
        XCTAssertEqual(AudioEventsTestable.audio([1: .none, 2: .none]), .allWindows)
    }

    /// At launch AltTab knows an app before its windows. Marking "all of them" then lit every Brave tile at
    /// once (measured: 43), so no known window is no answer. The cost: a windowless app shows no icon.
    func testAppWithNoKnownWindowIsNoAnswer() {
        XCTAssertNil(AudioEventsTestable.audio([:]))
    }

    /// A window that failed to read might hold the audible tab, so "none audible" is not proven.
    func testUnreadableWindowWithoutAnAudibleTabElsewhereIsNoAnswer() {
        XCTAssertNil(AudioEventsTestable.audio([1: .unreadable, 2: .tabs(["Inbox"])]))
        XCTAssertNil(AudioEventsTestable.audio([1: .unreadable, 2: .none]))
    }

    func testAudibleTabIsAnAnswerEvenIfAnotherWindowWasUnreadable() {
        XCTAssertEqual(AudioEventsTestable.audio([1: .unreadable, 2: .tabs(["Song - Audio playing"])]), .windows([2]))
    }

    // MARK: AppAudio.includes

    func testAllWindowsIncludesEveryWindowButNotTheWindowlessTile() {
        XCTAssertTrue(AppAudio.allWindows.includes(7))
        XCTAssertFalse(AppAudio.allWindows.includes(nil))
    }

    func testWindowsIncludesOnlyItsMembers() {
        XCTAssertTrue(AppAudio.windows([7]).includes(7))
        XCTAssertFalse(AppAudio.windows([7]).includes(8))
        XCTAssertFalse(AppAudio.windows([7]).includes(nil))
    }

    func testSilentIncludesNothing() {
        XCTAssertFalse(AppAudio.silent.includes(7))
        XCTAssertFalse(AppAudio.silent.includes(nil))
    }
}
