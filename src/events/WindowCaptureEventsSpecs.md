# WindowCaptureEvents — Specs

## Summary

One-shot window screenshots for thumbnails and Preview. macOS 26+ captures through ScreenCaptureKit
(`WindowCaptureScreenshots`); older versions capture through the private `CGSHWCaptureWindowList`
(`WindowCaptureScreenshotsPrivateApi`), because SCK is unreliable there (macOS 14 crashes inside Apple's
code, macOS 15 leaks).

## SCK API selection (macOS 26+)

Two public one-shot APIs exist, each broken differently:

- `captureSampleBuffer` returns a zero-copy IOSurface, but Apple implements each call by creating and
  destroying a capture stream. On some machines that churn leaks WindowServer memory until macOS
  force-logs-out the session (#5786). Each call also emits WindowServer `Creating sharing context` events
  and `Screenshots via streams are inefficient` warnings.
- `captureScreenshot` (new in macOS 26) creates no per-call stream (zero of the above events), but:
  - it fails with `SCStreamError -3811` for a fullscreen window whose Space is not frontmost (it succeeds
    when that Space is frontmost, and for minimized, other-Space, partially-offscreen, and tabbed windows);
  - it returns a copied `CGImage` instead of an IOSurface, which measurably slows full-resolution captures
    of large windows (relevant to Preview; at thumbnail sizes it is slightly *faster* than
    `captureSampleBuffer`).

Routing: `captureScreenshot` for every non-fullscreen window, including full-resolution Preview frames.
Fullscreen windows use `captureSampleBuffer` because the screenshot API fails when their Space is inactive.

## Capture resolution below macOS 26 (fork-local)

`CGSHWCaptureWindowList` captures at one pixel per point (`nominalResolution`) or at the display's scale
(`bestResolution`); nothing in between. The capture is an IOSurface the WindowServer owns until the
thumbnail is replaced, so its size is the WindowServer's memory, not AltTab's.

Measured on macOS 15.8, ~50 windows, 4096x2304 display at 2x, one summon held open 7s, WindowServer
footprint from `top -l 1 -pid $(pgrep -x WindowServer) -stats mem`:

| Captures | Before summon | After summon | Growth |
|---|---|---|---|
| `bestResolution` for all | 3.42 GB | 5.50-5.56 GB | +2.07 GB (two runs) |
| `nominalResolution` for all | 3.42 GB | 3.94 GB | +0.5 GB |

Capture latency is the same either way: median 73ms at 1x against 65ms at 2x over 121 back-to-back pairs.

`CaptureResolution.nominalSuffices` picks per window:

- **1x** when either side of the window in points reaches that side of the largest thumbnail box in pixels
  (`TilesPanel.maxPossibleThumbnailSize`). The tile then only shrinks the capture.
- **2x** for a smaller window. The tile draws it up to 1:1 in points, which a 1x capture would upscale.
- **2x for every window** while any shortcut uses Preview, which draws the stored thumbnail at the
  window's full size.
- **2x** when the window's size or the box is not known yet.

## Work bounds

- Only one `SCShareableContent` refresh is in flight. Requests arriving while it runs are deduplicated by
  `(wid, resolution)`. A request missing from a snapshot started before it arrived remains queued for the
  next discovery. A request already present at discovery start is drained even if absent, so nonexistent
  windows cannot trigger an endless retry. A late request present in the returned snapshot captures at once.
  The cache and request generations are published under the discovery lock before another read can start.
  Failed discovery uses the same generation rule, with no available windows. After five seconds without
  a completion, the watchdog expires that generation by the same rule. It does not retry covered requests
  indefinitely; late requests get their own generation, and a future ordinary refresh can retry expired
  requests. A late callback cannot publish a stale cache or finish a newer generation. Successful callbacks
  cancel their watchdog. The bound is one non-expired request; timed-out OS calls cannot be cancelled.
- The pending discovery set and the asynchronous capture wait list each cap at 256 entries. A prioritized
  request can evict a non-prioritized pending discovery; excess work is logged and dropped, relying on the
  next ordinary refresh rather than allowing an exotic desktop to grow queues without limit.
- The capture gate permits at most 2 requests in flight. The OS serves screenshot requests one at a time, so
  on macOS 27 a summon over 43 windows finished in the same 1.7s with any cap from 2 to 16 (2.1s with 1),
  while a higher cap only made each capture wait longer inside the OS. A thumbnail-only request is checked
  again when it reaches that gate, so work queued for a switcher session that has since ended does not
  reach the OS.

## Edge cases

- **Lost discovery callback**: unit tests cover timeout recovery, late-callback rejection, late-watchdog
  rejection, and progress of requests arriving during a lost call. Live QA `CP-03` drops one real discovery
  callback through a debug-only hook, then checks that a new window gets its capture on a later summon
  without restarting AltTab.

- **Stale fullscreen state**: `isFullscreen` is snapshotted on the main thread when the burst is built, so
  a window mid-transition can be routed to `captureScreenshot` and fail with -3811. Deliberately no
  fallback/retry: the thumbnail keeps its previous contents and the next refresh re-routes. A fallback
  would silently reintroduce stream churn and hide new failure modes.
- **Thumbnail and Preview requests stay distinct**: pending discovery and throttling keys include the
  resolution, so a thumbnail request cannot coalesce away a full-resolution Preview request for the same
  window.
- **Privacy attribution cost is API-independent**: both APIs flip replayd's screen-capture attribution
  (~4 `updateScreenCaptureDidStart` events per capture) and cost systemstatusd the same CPU (measured
  within 2%). Switching APIs fixes the WindowServer leak, not the per-capture attribution overhead.

## Measurements (2026-07-11, macOS 26.5.1, M-series, 29-window payload, 10 switcher cycles per run)

| per run (~355 captures) | captureSampleBuffer | captureScreenshot |
|---|---|---|
| WindowServer sharing contexts / warnings | ~355 / ~355 | 0 / 0 |
| capture latency mean (thumbnail sizes) | 706 ms | 644 ms |
| capture latency mean (full-res, ≤5.2 MP) | 709 ms | 664 ms |
| replayd CPU | 2.0 s | 1.8 s |
| systemstatusd CPU | 4.8 s | 4.7 s |
| failures | 0 | only fullscreen-on-inactive-Space, always -3811 |

## Discovery regression tests

`CaptureDiscoveryTests.swift` exercises the production pending buffer without ScreenCaptureKit:

- A late window absent from the old snapshot gets a newer discovery.
- A window still absent from its own discovery stops retrying.
- Late requests already covered by the returned content capture without another discovery.
- Repeated requests for a covered missing window merge without extending its retry.
- Arrivals during the follow-up belong to the next generation.
- The 256-entry production cap applies across generations, preserving priority and separate resolutions.
