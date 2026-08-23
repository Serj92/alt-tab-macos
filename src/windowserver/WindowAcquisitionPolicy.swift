import Cocoa

/// How to obtain an `AXUIElement` for a WindowServer-discovered wid. SLS discovery yields wids cheaply, but
/// subrole/title/tabs and the raise/minimize/close/fullscreen actions still need an AX element, and there is
/// NO wid→element API (RE-confirmed: the AX↔wid bridge is one-directional), so elements are acquired by
/// enumerate-and-match (then cached). This enum names the two acquisition routes and decides, per wid, which
/// one to take and where the brute-force sweep should begin; `WindowElementAcquisition` executes it.
/// Design in `WindowAcquisitionPolicySpecs.md`.
enum WindowAcquisitionPolicy {
    /// How to get the AX element for a newly-discovered wid.
    enum Route: Equatable {
        case currentSpaceViaApplicationWindows  // cheap: AXUIElementCreateApplication(pid).kAXWindows, match by wid
        case otherSpaceViaBruteForce            // _AXUIElementCreateWithRemoteToken enumeration, targeted + cached
    }

    /// `kAXWindows` is the app's own answer for the Space it is on, so for a wid the WindowServer places on the
    /// CURRENT Space it is authoritative: absent from it means no live element, not "look harder". Only a wid
    /// the WindowServer places elsewhere has anything to gain from the brute force.
    static func route(isOnCurrentSpace: Bool) -> Route {
        isOnCurrentSpace ? .currentSpaceViaApplicationWindows : .otherSpaceViaBruteForce
    }

    /// Where the other-Space sweep starts, which is what decides whether it finds anything at all. Shares
    /// `InactiveTabScanPolicy.scanStart` (and its measured margin) rather than restating the number: the
    /// lesson is the same one, and the two must not drift apart.
    ///
    /// `UInt64` rather than `AXUIElementID`: that alias lives in the AX api-wrapper, which is app-target only,
    /// while this triad is compiled into `unit-tests` too. `InactiveTabScanPolicy` spells it the same way for
    /// the same reason.
    static func bruteForceStart(lowestKnownId: UInt64?) -> UInt64 {
        InactiveTabScanPolicy.scanStart(cursor: nil, lowestKnownId: lowestKnownId)
    }
}
