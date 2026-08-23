import XCTest

/// Pins the two per-wid acquisition decisions. Both are cheap to get wrong in a way nothing else catches:
/// the route decides whether a wid pays a 250ms brute-force budget that cannot succeed, and the start id
/// decides whether a brute force that CAN succeed is aimed anywhere near its target. See the Specs.
final class WindowAcquisitionPolicyTests: XCTestCase {
    // MARK: - Route

    // the whole point of the change: a wid the WindowServer places on the current Space must never reach the
    // brute force, because `kAXWindows` has already given the app's own authoritative answer for that Space
    func testCurrentSpaceWidSkipsTheBruteForce() {
        XCTAssertEqual(WindowAcquisitionPolicy.route(isOnCurrentSpace: true), .currentSpaceViaApplicationWindows)
    }

    // ...and the case that still needs it keeps it: an other-Space window is absent from `kAXWindows`, so the
    // token sweep is the only way to an element for it
    func testOtherSpaceWidStillGetsTheBruteForce() {
        XCTAssertEqual(WindowAcquisitionPolicy.route(isOnCurrentSpace: false), .otherSpaceViaBruteForce)
    }

    // MARK: - Where the sweep starts

    func testNoTrackedWindowForThePidStartsAtZero() {
        XCTAssertEqual(WindowAcquisitionPolicy.bruteForceStart(lowestKnownId: nil), 0)
    }

    func testAnchorsAMarginBelowTheLowestKnownElementId() {
        let anchor = InactiveTabScanPolicy.scanMargin + 2500
        XCTAssertEqual(WindowAcquisitionPolicy.bruteForceStart(lowestKnownId: anchor), 2500)
    }

    // ids are UInt64: subtracting the margin from a low anchor would wrap to ~1.8e19 and the sweep would
    // start past every element the app owns (it would also trap on overflow in a debug build)
    func testAnchorBelowTheMarginClampsToZeroInsteadOfWrapping() {
        XCTAssertEqual(WindowAcquisitionPolicy.bruteForceStart(lowestKnownId: 10), 0)
        XCTAssertEqual(WindowAcquisitionPolicy.bruteForceStart(lowestKnownId: InactiveTabScanPolicy.scanMargin), 0)
    }
}
