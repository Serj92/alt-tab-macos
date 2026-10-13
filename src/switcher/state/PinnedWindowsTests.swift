import XCTest

/// fork-local: pinned windows (`PinnedWindowsSpecs.md`). The pin list's life cycle, the order rule in
/// `WindowOrderResolver`, and the default pick reading the list without pins (`SelectionInputs.pickOrder`).
final class PinnedWindowsTests: XCTestCase {

    // MARK: - Pin list

    func testANewPinGoesRightOfTheOlderOnes() {
        XCTAssertEqual(PinnedWindowsTestable.toggled([70, 90], 40), [70, 90, 40])
    }

    func testPinningAPinnedWindowUnpinsItAndKeepsTheOthersInOrder() {
        XCTAssertEqual(PinnedWindowsTestable.toggled([70, 90, 40], 90), [70, 40])
    }

    func testAClosedWindowLosesItsPin() {
        XCTAssertEqual(PinnedWindowsTestable.pruned([70, 90, 40], queried: [70, 90, 40], alive: [70, 40]), [70, 40])
    }

    func testAPinAddedWhileTheQueryWasInFlightStays() {
        XCTAssertEqual(PinnedWindowsTestable.pruned([70, 90], queried: [70], alive: []), [90])
    }

    func testAFailedQueryUnpinsNothing() {
        XCTAssertEqual(PinnedWindowsTestable.pruned([70, 90], queried: [70, 90], alive: nil), [70, 90])
    }

    func testPinsSurviveARelaunchInTheSameBoot() {
        XCTAssertEqual(PinnedWindowsTestable.restored([70, 90], storedBoot: 1_760_000_000, currentBoot: 1_760_000_000), [70, 90])
    }

    func testPinsFromAnotherBootAreDropped() {
        XCTAssertEqual(PinnedWindowsTestable.restored([70, 90], storedBoot: 1_760_000_000, currentBoot: 1_760_086_400), [])
    }

    func testAnUnknownBootDropsPins() {
        XCTAssertEqual(PinnedWindowsTestable.restored([70, 90], storedBoot: nil, currentBoot: 1_760_000_000), [])
        XCTAssertEqual(PinnedWindowsTestable.restored([70, 90], storedBoot: 1_760_000_000, currentBoot: nil), [])
    }

    // MARK: - Order

    private func w(_ title: String, focus: Int, pin: Int? = nil, isMinimized: Bool = false,
                   searchMatches: Bool = false, searchRelevance: Double = 0) -> OrderWindow {
        let state = WindowState(id: title, isPhantom: false, isWindowlessApp: false, isFullscreen: false,
                                isMinimized: isMinimized, isTabbed: false, isOnAllSpaces: false, spaceIds: [],
                                spaceIndexes: [], lastFocusOrder: focus, creationOrder: 0, title: title)
        let app = ApplicationState(pid: 0, bundleIdentifier: nil, localizedName: "App", isHidden: false)
        return OrderWindow(state: state, app: app, searchMatches: searchMatches, searchRelevance: searchRelevance, pinRank: pin)
    }

    private func titles(_ windows: [OrderWindow], searchActive: Bool = false, minimizedAtEnd: Bool = false) -> [String] {
        windows.sorted { WindowOrderResolver.isOrderedBefore($0, $1, searchActive: searchActive, minimizedAtEnd: minimizedAtEnd) }
            .map { $0.state.title }
    }

    func testPinnedWindowsLeadInPinOrderAndTheRestKeepRecentFirst() {
        let windows = [w("current", focus: 0), w("previous", focus: 1, pin: 1), w("older", focus: 2),
                       w("oldest", focus: 3, pin: 0), w("ancient", focus: 4)]
        XCTAssertEqual(titles(windows), ["oldest", "previous", "current", "older", "ancient"])
    }

    func testAPinnedMinimizedWindowStillLeadsWhenMinimizedGoLast() {
        let windows = [w("current", focus: 0), w("minimized", focus: 1, pin: 0, isMinimized: true), w("older", focus: 2)]
        XCTAssertEqual(titles(windows, minimizedAtEnd: true), ["minimized", "current", "older"])
    }

    func testSearchRanksByMatchAndIgnoresPins() {
        let windows = [w("pinned miss", focus: 0, pin: 0), w("best", focus: 1, searchMatches: true, searchRelevance: 2),
                       w("good", focus: 2, searchMatches: true, searchRelevance: 1)]
        XCTAssertEqual(titles(windows, searchActive: true), ["best", "good", "pinned miss"])
    }

    // MARK: - Default pick

    private func s(_ id: String, focus: Int) -> SelectionWindow {
        SelectionWindow(id: id, visible: true, lastFocusOrder: focus, isMinimized: false, isWindowlessApp: false)
    }

    private func initialPick(_ list: [SelectionWindow], pickOrder: [Int]?) -> Int? {
        SelectionResolver.initialPickIndex(SelectionInputs(list: list, selectedIndex: 0, selectedTarget: nil,
            useLastFocusedRule: false, visibleCountAtSummon: list.count, userPickedSelection: false,
            restoreDefaultOnSearchClear: false, bestMatchOnSearchChange: false, pickOrder: pickOrder))
    }

    /// Drawn: [pinned, current, previous, older]. Without pins the list reads [current, previous, older,
    /// pinned], so one alt-tab still goes to "previous", now on tile 2.
    func testOneTabStillGoesToThePreviousWindowWhenPinsLead() {
        let drawn = [s("pinned", focus: 3), s("current", focus: 0), s("previous", focus: 1), s("older", focus: 2)]
        XCTAssertEqual(initialPick(drawn, pickOrder: [1, 2, 3, 0]), 2)
    }

    /// Drawn: [previous (pinned), current, older]. The previous window is found on its pinned tile.
    func testThePreviousWindowIsPickedOnItsPinnedTile() {
        let drawn = [s("previous", focus: 1), s("current", focus: 0), s("older", focus: 2)]
        XCTAssertEqual(initialPick(drawn, pickOrder: [1, 0, 2]), 0)
    }

    /// Drawn: [current (pinned), previous, older] is also the order without pins, so nothing is remapped.
    func testWithoutAPickOrderThePickReadsTheDrawnList() {
        let drawn = [s("current", focus: 0), s("previous", focus: 1), s("older", focus: 2)]
        XCTAssertEqual(initialPick(drawn, pickOrder: nil), 1)
    }
}
