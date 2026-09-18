# AltTabFix — personal fork notes

This repo (`Serj92/alt-tab-macos`, remote `origin`) is a **personal fork** of
[`lwouis/alt-tab-macos`](https://github.com/lwouis/alt-tab-macos) (remote `upstream`).

- **Never** push to `upstream` / never open upstream PRs — they won't be accepted.
- The fork is kept current by periodically merging `upstream/master` (see
  [Updating to a new upstream version](#updating-to-a-new-upstream-version)).
- The daily-driver app is built locally and installed as **`/Applications/AltTabFix.app`**.

---

## Toolchain

| | This fork | Upstream |
|---|---|---|
| Builds on | **Xcode 16 / Swift 6.0** (macOS 15 SDK) | Xcode 26 / Swift 6.2 (macOS 26 SDK, Liquid Glass) |

Because we build on the older SDK, any upstream code that touches **macOS-26-only
symbols** (`NSGlassEffectView`, `controlSize = .extraLarge`,
`canUsePrivateLiquidGlassLook`, trailing commas in calls, etc.) must be wrapped in
`#if compiler(>=6.2)` or it won't compile here. This is the main manual work when
merging a new upstream version.

---

## Local patches (carried on top of upstream)

Each is a `local: …` commit on `master`. Keep them across merges.

| Area | What | Where |
|---|---|---|
| **Pro unlock** | `LicenseManager.forceProUnlock = true` short-circuits `isProAvailable` / `isProLocked` / `computeState()`. Upstream's real bodies are kept behind the flag rather than deleted, so `LicenseManagerTests` can turn it off in `setUp` and still test them — which is why a full run is green (see [Running tests](#running-tests)) | `src/pro/license/LicenseManager.swift`, `src/pro/license/LicenseManagerTests.swift` |
| **Xcode 16 compat** | `#if compiler(>=6.2)` guards around macOS-26 / Liquid Glass APIs; one trailing comma dropped; the macOS-26-only `SCScreenshotManager.captureScreenshot` path falls back to `captureSampleBuffer` (runtime-equivalent on macOS 15) | `HelperExtensions` (`NSSearchField.applySearchStyle`, shared by the switcher and Settings search fields), `Appearance`, `TilesPanelBackgroundView`, `PermissionsWindow`, `WindowCaptureEvents` |
| **Perf micro-opts** | SCWindow indexing by id (avoid O(n²)); `Appearance.resolvedStyle` cache for the tile render hot path. ~~forward focus bookkeeping (rapid Cmd+Tab)~~ — dropped at v11.4.4: upstream's `ActivationFocusResolver` intent mechanism (#5596) covers the race, and the manual `frontmostPid` forward-set would break its `frontmostPid != pid` intent-recording guard | `WindowCaptureEvents.swift`, `Appearance.swift`, `TilesView.swift` |
| **No event-server read for the Esc tap** | `updateEscapeAbsorptionTap` asked `CGEvent.tapIsEnabled` every time just to compare against the state it wanted. Measured with marks around the two calls separately: the read costs **4–34ms**, the `tapEnable` write **1–7ms**, and once the read blocked the main thread for **246ms** between a dismissal and the next summon. Upstream's audit (`src/main-thread-ipc.md`) had the pair at "0–8ms", which hid it. Nothing but AltTab enables this tap, so the wanted state is now compared against a cached flag; macOS only ever *disables* a tap, and that arrives as `.tapDisabledByUserInput` / `.tapDisabledByTimeout`, so the recovery paths (also wake and unlock) pass `force: true`. `force` only ever re-ENABLES — answering the once-per-dismissal `byUserInput` with another `tapEnable(false)` could re-trigger it. Pattern copied from `TrackpadEvents.setAbsorbTapEnabled`, which already caches the same way | `src/events/KeyboardEvents.swift`, `src/main-thread-ipc.md` |
| **Local build version** | derive `CURRENT_PROJECT_VERSION` / `MARKETING_VERSION` from the latest `chore(release):` commit (CI injects it normally; local builds recover it from git) | `ai/build.sh` |
| **Debug-strip** | gate `DebugWindow` (the "Debug tools" window) + its menubar item + `BenchmarkRunner` behind `#if DEBUG` so a **Release** build carries no debug machinery (QAMenu + DebugMenu live-graph were already `#if DEBUG`) | `App.swift`, `Menubar.swift`, `DebugWindow.swift`, `Benchmark.swift` |
| **No auto-update** | Sparkle is removed entirely: the local SwiftPM package, the framework and its `Updater.app`/`Autoupdate` helpers, `SparkleDelegate`, the `UserDefaultsEvents` class (it existed only to mirror Sparkle's own checkbox back into `updatePolicy`), the menubar's "Check for updates…", the Settings updates-policy row, and the feedback window's pre-form update check. The `updatePolicy` preference itself is left defined but unused, to keep `MacroPreferences` / migrations untouched. Bundle 12MB → 9.5MB. The fork could never update itself anyway (nil feed), so nothing is lost — the feedback window shows its form directly instead of after a check that could only ever fail | `App.swift`, `Menubar.swift`, `GeneralTab.swift`, `PreferencesEvents.swift`, `FeedbackWindow.swift`, `Info.plist`, `project.pbxproj` |
| **No crash reporting** | AppCenter is removed entirely: the local SwiftPM package, the `AppCenter` / `AppCenterCrashes` products, `AppCenterCrash`, the `AppCenterApplication` NSApplication subclass (`NSPrincipalClass` is plain `NSApplication` now), `Secrets` (it held nothing else), the crash-reports queue, and the Settings "Crash reports policy" row. `APPCENTER_SECRET` was defined in no xcconfig, so the shipped `AppCenterSecret` was the empty string and reports could never reach anyone; the service itself is retired (upstream tracks a replacement in #4073). Dropping it also drops the dylibs it dragged in: CrashReporter.framework, CoreTelephony, SystemConfiguration, libsqlite3 and libz, and with the embedded framework gone the `@rpath/libswift*` back-deployment copies collapse onto the OS ones in `/usr/lib/swift` (66 load commands → 43). CoreData survives — it turns out to be an autolink artifact with no undefined symbols against it, so it was never AppCenter's to remove. The `crashPolicy` preference is left defined but unused, to keep `MacroPreferences` / migrations untouched. **Behaviour change:** `AppCenterCrash` registered `NSApplicationCrashOnExceptions`, so an exception raised inside `sendEvent:` killed the app *so it could be reported*; with no reporter that trade buys nothing, and stock AppKit handling (log and carry on) applies again | `App.swift`, `Info.plist`, `alt-tab-macos-Bridging-Header.h`, `GeneralTab.swift`, `BackgroundWork.swift`, `project.pbxproj` |
| **No "move to /Applications" prompt** | `MoveToApplicationsFolder.promptIfNeeded()` is no longer called. `ai/install.sh` always installs to /Applications, so the prompt can only fire on a build launched from somewhere else — a probe build for an A/B measurement — where accepting it relocates the very binary being measured. It also ran a modal alert at the earliest point of launch, which forced upstream to order it ahead of the WindowServer tap so a queued discovery could not drain re-entrantly into a half-built model; not calling it drops that constraint. The type is left in the tree, uncalled | `src/App.swift` |
| **Fork-safe XS/XL migration** | Upstream PR #5932 version-gates `migrateAppearanceSizeIndexes` at 11.4.4, but the fork's `App.version` is derived from the last `chore(release):` commit, so it never rises above the stored `preferencesVersion` and the gate can never fire (raising the threshold instead would re-run the shift on *every* launch). Called unconditionally, guarded by a one-shot `fork.migratedAppearanceSizeIndexes` flag so upstream's own gate can't shift the indexes a second time once the PR lands. **Drop together with the #5932 cherry-pick** | `src/preferences/PreferencesMigrations.swift` |

### Dropped at the v11.6.1 merge

Three launch-latency patches, all superseded by upstream's own window-tracking rework:

- **Throttler leading edge** — upstream made the same one-line change (`lastTimeInNanoseconds`
  is `UInt64?`, nil until the first run) with the same reasoning. Nothing fork-local left.
- **Launch inventory sooner** (1s → 0.25s) — upstream keeps the 1s defer, and instead has the
  very first summon fire the inventory itself and wait up to `launchInventoryGraceInMs` (400ms)
  for it. That removes the empty-switcher frame our 0.25s was aimed at, while keeping the reason
  the defer exists: on a login-item start the sweep's AX calls compete with every other login
  item, which our own measurements had shown stretching the sweep from ~850ms to ~1600ms.
- **Cold-start window discovery** — upstream reached the same cost from the other side:
  `Applications.scheduleSurfaceAcquisitions` groups an inventory pass by pid, so one app pays one
  250ms traversal for all its missing wids instead of one per wid, and `SurfaceAcquisitionPolicy`
  stops asking after three failures at the same app window set. The route-by-Space choice and the
  anchored sweep were not carried over: their batched traversal takes one route and one start id
  for a whole pid. `WindowAcquisitionPolicySpecs.md` + its 5 tests went with the patch.

**First measurement after the merge, and nothing needs re-applying.** From the `ai/run.sh` DEBUG
build's own log (80 windows, `Window.init` timestamps against `applicationDidFinishLaunching`):
first window at **+320ms**, 79 of 80 by **+725ms**, the last at **+900ms**. The three patches
together had bought ~1.2s to a complete list on a RELEASE build, so an unoptimized build now beats
them — the deferred inventory is no longer what discovery waits for, because upstream's tracking
rework reaches most windows through `Applications.initialDiscovery` and the WindowServer tap
before the 1s timer ever fires.

Not the same method as the older numbers (Release, launch → complete `--list`), so treat it as a
no-regression check rather than a comparable figure. Worth one Release `--list` run if launch ever
feels slow again.

> `vendor/Sparkle` and `vendor/AppCenter` are still checked in — they are simply not referenced by
> the target. Deleting them would be a large diff against upstream for no build-time or runtime
> gain. Same for `scripts/upload_symbols_to_appcenter.sh`, which only CI ever ran.

> Measured on the Release build after the arm64 switch and the AppCenter removal, against the
> 9.5 MB bundle that preceded both: **bundle 9.5 MB → 5.0 MB**, executable 6.7 MB fat → 2.7 MB
> arm64-only, `Contents/Frameworks` gone entirely, linked dylibs 66 → 43.

> The bridging header now states `@import Cocoa;` itself. It used to get it for free from
> `AppCenterApplication.h`, and the api-wrappers around SkyLight / HIServices carry no import of
> their own — removing AppCenter without this breaks the build with ~40 "cannot find type
> 'CGWindowID'" errors that point nowhere near the real cause.

---

## Measured: the dismissal's fat tail is `[NSWindow orderOut:]`

Chasing "the speed feels inconsistent — sometimes it sticks, sometimes it's fine" (2026-09-13), with
`MainThreadStall` at a 1ms threshold and marks around single statements.

`TilesPanel.orderOut` on the visible dismissal path: **median 2-3ms, p90 ~20ms, max 350ms**, over ~110
dismissals. One case timed end to end: the key was released at 00:43:06.668 and the panel was still up at
00:43:07.018 — 350ms with the target window's activation waiting behind it, because `beginHideUi` runs
before the focus request by design.

The spike is in `[NSWindow orderOut:]` itself. Marks on both sides isolate it: the
`allSecondaryWindowsCanBecomeKey` toggles around it never exceeded 1ms, and `Window.focus` opens its own
step, so the figure contains neither.

Four explanations tested and rejected:

| Hypothesis | Evidence against |
|---|---|
| It scales with the window count | 0.82ms per window, r=0.29, over 63-84 windows. Explains the ~25ms baseline, not a 350ms spike |
| It collides with background work (`syncSpacesState`, re-subscription, AX scans) | medians identical with that work within 0.75s and without: 24ms vs 22ms |
| It depends on the app receiving focus | same app is both: Terminal median 2ms / max 309ms, Brave median 3ms / max 304ms |
| It is the first dismissal after an idle period | 17 summons after gaps of 4-84 minutes are indistinguishable from back-to-back ones |

So it is WindowServer latency on a cross-process call, not something the code computes. The only lever
would be not making the panel key at all, so dismissing it needs no key-window handoff — a rewrite of the
focus model, not a safe change. **Left alone deliberately.**

Two attribution traps this cost a round trip each, recorded so the next reader skips them:

- `MainThreadStall` bills un-instrumented main-thread work to the previously opened step (see
  `src/main-thread-ipc.md`). A 356ms `endHideUi` was really the `.spacesSynced` reducer; a 304ms `orderOut`
  was really the same. **Add a closing mark before believing a number.**
- The shipped threshold is 16ms, so any distribution computed from a Release log is conditioned on
  exceeding 16ms. A "median" from one is the median of the tail. Lower the threshold to get real medians.

---

## Cherry-picked upstream PRs (not merged upstream yet)

PRs on `lwouis/alt-tab-macos` that are applied here ahead of upstream. Unlike the
local patches above, these are **temporary**: when upstream merges one, the next
`git merge upstream/master` brings the same change in again — **drop our copy then**
(`git rebase --onto` / revert), don't try to keep both.

| PR | What | Files | Notes |
|---|---|---|---|
| [#5932](https://github.com/lwouis/alt-tab-macos/pull/5932) | New **XS** and **XL** appearance sizes (all 3 styles), with a preferences migration for the shifted stored indexes | `MacroPreferences.swift`, `Appearance.swift`, `PreferencesMigrations.swift`, `AppearanceTab.swift`, `LabelAndControl.swift`, `TileView.swift`, +6 | One conflict in `TileView.swift`: the PR predates upstream's `Appearance.resolvedStyle` cache, so it still called `Preferences.effectiveAppearanceStyle(…)`. Resolved to our `resolvedStyle` + the PR's `resolvedSize.isLargeOrAbove`. Its migration also needed a fork-local fix to run at all (see **Fork-safe XS/XL migration** above). At v11.7.0 upstream deleted `LabelAndControl.applySystemSelectedSegmentStyle` (it only set the default `.automatic`), so the PR's `naturalSegmentWidth` probe no longer calls it. +5 tests, +2 fork tests |

#5967 arrived with the v11.6.1 merge as `a694953c` (amended, plus a test for the other
containment direction in `chordsCollide`); our copy was dropped there. #5932 is a cherry-pick, so
it keeps its original author; upstream's own merge of it will not be recognised as a duplicate by
git.

---

## Signing & identity — `config/local.xcconfig`

This file is **gitignored** and `#include?`-ed last by both `config/debug.xcconfig`
and `config/release.xcconfig` (so it overrides their defaults, e.g. debug's
`Local Self-Signed`). It is **not** in git, so recreate it on a fresh checkout:

```xcconfig
PRODUCT_BUNDLE_IDENTIFIER = com.lwouis.alt-tab-macos.fix
CODE_SIGN_STYLE = Manual
DEVELOPMENT_TEAM = T5V6W6793A
CODE_SIGN_IDENTITY = Apple Development: seregaijko@gmail.com (88FBB4GZ5S)
PROVISIONING_PROFILE_SPECIFIER =

ARCHS = arm64
```

`ARCHS` is here and not in `config/release.xcconfig` on purpose: it keeps the diff
against upstream at zero. Xcode's default `ARCHS_STANDARD` produced a fat binary whose
x86_64 slice was **3.59 MB of a 9.5 MB bundle** — never executable on this Apple Silicon
machine, and it made Release do all codegen twice. (Debug was already arm64-only via
`ONLY_ACTIVE_ARCH`.) Verify with `lipo -info` on the built binary, or:

```bash
xcodebuild -project alt-tab-macos.xcodeproj -scheme Release -configuration Release \
  -showBuildSettings | grep ' ARCHS '
```

The distinct bundle id + this signing identity match the already-installed app, so a
fresh build **inherits its TCC grants** (Accessibility + Screen Recording) — no need to
re-grant permissions after each rebuild. (If the bundle id or team ever change, macOS
treats it as a new app and you must re-grant permissions in System Settings.)

The app's entitlements (`alt_tab_macos.entitlements`) need no provisioning profile
(no sandbox / app-groups), so an Apple Development cert signs it for local use directly.

---

## Build & install

### Daily driver — production (Release)

```bash
bash ai/install.sh
```

Does a **clean Release build** (`-O`, no `#if DEBUG` code), signed as the `.fix` fork,
then quits / replaces / relaunches `/Applications/AltTabFix.app`. Clean tree is used to
avoid incremental codesign flakiness on the embedded Sparkle framework.

Release = optimized, no debug windows, no auto-update. This is what you run day-to-day.

### Iterative testing — Debug

```bash
bash ai/build.sh   # Debug build -> DerivedData/Build/Products/Debug/AltTab.app
bash ai/run.sh     # self-terminating `--benchmark showUi 3` smoke run; prints accessibility:granted
```

Debug keeps the `--benchmark` CLI and the debug windows for development. Don't ship it
as the daily driver (unoptimized + debug machinery loaded).

---

## Running tests

```bash
bash ai/test.sh
```

Upstream's script (added at v11.7.0): `xcodebuild test` on the Debug configuration. It ran
the full suite here on Xcode 16 (2026-09-18). A plain `xcodebuild test` used to fail on this
setup with the test host unable to load the bundle (`unit-tests.xctest` → "executable not
found"); why the script does not, nobody checked. If it ever regresses to that, build the
bundle and run it directly:

```bash
xcodebuild build-for-testing -project alt-tab-macos.xcodeproj -scheme Test \
  -derivedDataPath DerivedDataTest CURRENT_PROJECT_VERSION=0.0.0 MARKETING_VERSION=0.0.0
xcrun xctest DerivedDataTest/Build/Products/Debug/unit-tests.xctest
```

### Expected: **1264 tests, 0 failures**

Any failure is a real regression. Nothing here is "expected to be red".

This used to read *"932 tests, exactly 18 failures, all in `LicenseManagerTests`"*: the
Pro-unlock patch had deleted upstream's licensing bodies outright, so every test asserting
trial / expiry behaviour failed by construction. That baseline had to be remembered and
re-checked by eye after each upstream merge, and — worse — a genuine regression inside
`LicenseManagerTests` was invisible unless the failure count moved off 18. The patch now
keeps upstream's bodies behind `LicenseManager.forceProUnlock`, which the test class turns
off in `setUp` and restores in `tearDown`. The app never touches the flag, so the shipped
behaviour is unchanged: Pro is still unconditionally on.

---

## Updating to a new upstream version

```bash
git fetch upstream --tags
git merge upstream/master            # 3-way
```

Then:

1. **Drop any [cherry-picked upstream PR](#cherry-picked-upstream-prs-not-merged-upstream-yet)
   that has since been merged upstream** — otherwise the change is applied twice.
2. **Re-apply `#if compiler(>=6.2)` guards** on any *new* macOS-26 / Liquid Glass /
   Swift-6.2 code upstream introduced (the big risk area: settings UI, new files).
3. `bash ai/build.sh` until it compiles on Xcode 16 (fix any new compat issues).
4. `bash ai/install.sh` to rebuild the Release daily driver and install it.
5. Sanity-check: rapid Cmd+Tab + your usual flow.

Note: `ai/build.sh` signing fails with `No certificate matching 'Local Self-Signed'`
only when `config/local.xcconfig` is missing — recreate it (see above).

---

*Last synced to upstream: **v11.7.0** (2026-09-18).*
