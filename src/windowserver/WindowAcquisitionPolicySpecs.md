# WindowAcquisitionPolicy — design

Two decisions, both taken per newly-discovered wid by `Applications.refreshWindowsViaWindowServer` and
executed by `WindowElementAcquisition`.

## 1. Which route

`route(isOnCurrentSpace:)`.

The discovery sweep used to pass `.otherSpaceViaBruteForce` for **every** new wid, so the route enum
existed while nothing chose between its cases. That is expensive in a specific way: a brute force that
finds nothing costs the whole `AXUIElement.bruteForceBudgetMs` (250ms) before the wid is rejected, and the
AX scan pool is 6 wide, so unresolvable wids are rejected in waves of six, one wave per 250ms.

Measured at launch, 2026-08-23, 63 windows, one Space: 17 wids failed acquisition, in three waves at
t+875ms / t+1130ms / t+1396ms, and no window at all was published until the last of them finished — the
whole accepted set landed in one 34ms burst at t+1398ms. That is ~750ms of a 1270ms cold start spent
proving that windows with no AX element have no AX element.

Those wids are not other-Space windows. They are per-window helper surfaces the browser parks at
application window level — `511`/`512` beside the accepted `510`, `1665`/`1666` beside `1664`,
`3313`/`3314` beside `3312`. They have no AX element and never will, and they are re-probed on every
sweep, because a rejected wid never becomes a tracked window.

The fix is to use the enum as intended. `kAXWindows` is the app's own window list for the Space it is on,
so for a wid the WindowServer places on the current Space it is the authority: absent from it means no
live element. Only a wid placed on another Space can gain from the token brute force, and those keep
exactly today's behaviour.

What this gives up: a current-Space window that the app has not yet published into `kAXWindows` no longer
gets the brute force as a second chance. It is not much of a chance — the element the sweep would look for
is the one the app has not created yet — and the wid is re-acquired on the next sweep either way.

## 2. Where the sweep starts

`bruteForceStart(lowestKnownId:)`.

`AXUIElement.windowByBruteForce` walked AXUIElementIDs from 0 under a wall-clock budget, and dropped the
cursor `bruteForceElements` returns. So it covered a *window* of the id space anchored at 0, and every
retry re-walked the same dead prefix.

`InactiveTabScanPolicy.scanStart` already records what that costs, measured live 2026-07-30: three
attempts covered ids 0..<30000 and adopted nothing, while Finder's window elements sat at ~31000 —
stopping just short, every time, forever. Window discovery was making the same bet.

An app's window elements are minted together and cluster in a narrow band, and any window we already track
names that band, so the sweep starts a margin below the lowest known element id for that pid. With no
tracked window for the pid there is no anchor and the sweep starts at 0, as before.

This matters most *because* of decision 1: the brute forces that remain are the ones aimed at real
other-Space windows, and they should be the ones that succeed.
