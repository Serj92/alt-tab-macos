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
| **Xcode 16 compat** | `#if compiler(>=6.2)` guards around macOS-26 / Liquid Glass APIs; one trailing comma dropped; the macOS-26-only `SCScreenshotManager.captureScreenshot` path falls back to `captureSampleBuffer` (runtime-equivalent on macOS 15) | `SettingsWindow`, `TilesView`, `Appearance`, `TilesPanelBackgroundView`, `PermissionsWindow`, `WindowCaptureEvents` |
| **Perf micro-opts** | SCWindow indexing by id (avoid O(n²)); `Appearance.resolvedStyle` cache for the tile render hot path. ~~forward focus bookkeeping (rapid Cmd+Tab)~~ — dropped at v11.4.4: upstream's `ActivationFocusResolver` intent mechanism (#5596) covers the race, and the manual `frontmostPid` forward-set would break its `frontmostPid != pid` intent-recording guard | `WindowCaptureEvents.swift`, `Appearance.swift`, `TilesView.swift` |
| **Throttler leading edge** | `Throttler` seeded `lastTimeInNanoseconds` with `now` in its constructor, so the FIRST call ever was read as a repeat and pushed a full window. At launch that added ~1.0s to `Applications.manuallyRefreshAllWindows` (already deferred 1s by `applicationDidFinishLaunching`), so the switcher listed no windows for ~3s after start — Cmd+Tab in that window opened it empty. Now `nil` until the first run, which is the leading edge `SchedulingPolicySpecs.md` documents (`testThrottleFirstCallRunsNow`) and `ThrottlerWithKey` already gets from having no map entry. Measured launch → non-empty `--list`: **3.02s → 1.89s** (3 runs each). No unit seam: compiling `Throttler` into the test bundle drags `BackgroundWork` + the AX/CGS/Process schedulers with it | `src/util/Throttler.swift` |
| **Launch inventory sooner** | The one initial window inventory was deferred 1s after launch; the rest of launch is done ~145ms in, so most of that was idle waiting. Now 0.25s, which still clears the launch tail with margin. Measured to a complete window list, 5 launches each: 1s → 1918ms, 0.25s → 1208ms (0.1s → 911ms, rejected: no margin over the 145ms tail, and a login-item start competes with the whole system) | `src/App.swift` |
| **Local build version** | derive `CURRENT_PROJECT_VERSION` / `MARKETING_VERSION` from the latest `chore(release):` commit (CI injects it normally; local builds recover it from git) | `ai/build.sh` |
| **Debug-strip** | gate `DebugWindow` (the "Debug tools" window) + its menubar item + `BenchmarkRunner` behind `#if DEBUG` so a **Release** build carries no debug machinery (QAMenu + DebugMenu live-graph were already `#if DEBUG`) | `App.swift`, `Menubar.swift`, `DebugWindow.swift`, `Benchmark.swift` |
| **No auto-update** | Sparkle is removed entirely: the local SwiftPM package, the framework and its `Updater.app`/`Autoupdate` helpers, `SparkleDelegate`, the `UserDefaultsEvents` class (it existed only to mirror Sparkle's own checkbox back into `updatePolicy`), the menubar's "Check for updates…", the Settings updates-policy row, and the feedback window's pre-form update check. The `updatePolicy` preference itself is left defined but unused, to keep `MacroPreferences` / migrations untouched. Bundle 12MB → 9.5MB. The fork could never update itself anyway (nil feed), so nothing is lost — the feedback window shows its form directly instead of after a check that could only ever fail | `App.swift`, `Menubar.swift`, `GeneralTab.swift`, `PreferencesEvents.swift`, `FeedbackWindow.swift`, `Info.plist`, `project.pbxproj` |
| **No crash reporting** | AppCenter is removed entirely: the local SwiftPM package, the `AppCenter` / `AppCenterCrashes` products, `AppCenterCrash`, the `AppCenterApplication` NSApplication subclass (`NSPrincipalClass` is plain `NSApplication` now), `Secrets` (it held nothing else), the crash-reports queue, and the Settings "Crash reports policy" row. `APPCENTER_SECRET` was defined in no xcconfig, so the shipped `AppCenterSecret` was the empty string and reports could never reach anyone; the service itself is retired (upstream tracks a replacement in #4073). Dropping it also drops the dylibs it dragged in: CrashReporter.framework, CoreTelephony, SystemConfiguration, libsqlite3 and libz, and with the embedded framework gone the `@rpath/libswift*` back-deployment copies collapse onto the OS ones in `/usr/lib/swift` (66 load commands → 43). CoreData survives — it turns out to be an autolink artifact with no undefined symbols against it, so it was never AppCenter's to remove. The `crashPolicy` preference is left defined but unused, to keep `MacroPreferences` / migrations untouched. **Behaviour change:** `AppCenterCrash` registered `NSApplicationCrashOnExceptions`, so an exception raised inside `sendEvent:` killed the app *so it could be reported*; with no reporter that trade buys nothing, and stock AppKit handling (log and carry on) applies again | `App.swift`, `Info.plist`, `alt-tab-macos-Bridging-Header.h`, `GeneralTab.swift`, `BackgroundWork.swift`, `project.pbxproj` |
| **No "move to /Applications" prompt** | `MoveToApplicationsFolder.promptIfNeeded()` is no longer called. `ai/install.sh` always installs to /Applications, so the prompt can only fire on a build launched from somewhere else — a probe build for an A/B measurement — where accepting it relocates the very binary being measured. It also ran a modal alert at the earliest point of launch, which forced upstream to order it ahead of the WindowServer tap so a queued discovery could not drain re-entrantly into a half-built model; not calling it drops that constraint. The type is left in the tree, uncalled | `src/App.swift` |
| **Cold-start window discovery** | The discovery sweep passed `.otherSpaceViaBruteForce` for *every* newly-seen wid, so the `WindowAcquisitionPolicy.Route` enum existed while nothing chose between its cases. A brute force that finds nothing costs the full 250ms `bruteForceBudgetMs` before the wid can be rejected, and the AX scan pool is 6 wide — measured at launch: 17 unresolvable wids, three waves of rejections 250ms apart, and no window published until the last one finished. Those wids are not other-Space windows; they are per-window helper surfaces a browser parks at application level (`511`/`512` beside the accepted `510`) that have no AX element and never will. Now the route is chosen from the WindowServer's own Space membership, and the brute force that remains is anchored near the app's known element ids instead of starting at 0 — the lesson `InactiveTabScanPolicy.scanStart` already recorded. **Measured A/B, same 71 windows: first window 1444ms → 618ms, full list 1818ms → 982ms.** Design in `src/windowserver/WindowAcquisitionPolicySpecs.md`; +5 tests | `WindowAcquisitionPolicy.swift`, `Applications.swift`, `WindowElementAcquisition.swift`, `WindowDiscriminator.swift`, `AXUIElement.swift` |
| **Fork-safe XS/XL migration** | Upstream PR #5932 version-gates `migrateAppearanceSizeIndexes` at 11.4.4, but the fork's `App.version` is derived from the last `chore(release):` commit, so it never rises above the stored `preferencesVersion` and the gate can never fire (raising the threshold instead would re-run the shift on *every* launch). Called unconditionally, guarded by a one-shot `fork.migratedAppearanceSizeIndexes` flag so upstream's own gate can't shift the indexes a second time once the PR lands. **Drop together with the #5932 cherry-pick** | `src/preferences/PreferencesMigrations.swift` |

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

## Cherry-picked upstream PRs (not merged upstream yet)

Open PRs on `lwouis/alt-tab-macos` that are applied here ahead of upstream. Unlike the
local patches above, these are **temporary**: when upstream merges one, the next
`git merge upstream/master` brings the same change in again — **drop our copy then**
(`git rebase --onto` / revert), don't try to keep both.

| PR | What | Files | Notes |
|---|---|---|---|
| [#5967](https://github.com/lwouis/alt-tab-macos/pull/5967) | A shortcut could not be assigned because an *unrelated* pre-existing conflict between two other shortcuts was counted against it | `CustomRecorderControlTestable.swift` | Applied clean. +1 test |
| [#5932](https://github.com/lwouis/alt-tab-macos/pull/5932) | New **XS** and **XL** appearance sizes (all 3 styles), with a preferences migration for the shifted stored indexes | `MacroPreferences.swift`, `Appearance.swift`, `PreferencesMigrations.swift`, `AppearanceTab.swift`, `LabelAndControl.swift`, `TileView.swift`, +6 | One conflict in `TileView.swift`: the PR predates upstream's `Appearance.resolvedStyle` cache, so it still called `Preferences.effectiveAppearanceStyle(…)`. Resolved to our `resolvedStyle` + the PR's `resolvedSize.isLargeOrAbove`. Its migration also needed a fork-local fix to run at all (see **Fork-safe XS/XL migration** above). +5 tests, +2 fork tests |

Both are cherry-picks, so they keep their original authors; upstream's own merge of them
will not be recognised as a duplicate by git.

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

`xcodebuild test` **fails to run the suite** here — its test host can't load the built
bundle (`unit-tests.xctest` → "executable not found"), a CLI hosting quirk on this
Xcode-16 setup (the bundle itself is fine; it's the runner). Build the bundle and run it
directly instead:

```bash
xcodebuild build-for-testing -project alt-tab-macos.xcodeproj -scheme Test \
  -derivedDataPath DerivedDataTest CURRENT_PROJECT_VERSION=0.0.0 MARKETING_VERSION=0.0.0
xcrun xctest DerivedDataTest/Build/Products/Debug/unit-tests.xctest
```

### Expected: **945 tests, 0 failures**

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
git merge upstream/master            # 3-way; has been conflict-free so far
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

*Last synced to upstream: **v11.5.0** (2026-08-19).*
