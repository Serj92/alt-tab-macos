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
| **Pro unlock** | `isProAvailable=true`, `isProLocked=false`, `computeState()=.pro` (→ 18 expected `LicenseManagerTests` failures, see [Running tests](#running-tests)) | `src/pro/license/LicenseManager.swift` |
| **Xcode 16 compat** | `#if compiler(>=6.2)` guards around macOS-26 / Liquid Glass APIs; one trailing comma dropped; the macOS-26-only `SCScreenshotManager.captureScreenshot` path falls back to `captureSampleBuffer` (runtime-equivalent on macOS 15) | `SettingsWindow`, `TilesView`, `Appearance`, `TilesPanelBackgroundView`, `PermissionsWindow`, `WindowCaptureEvents` |
| **Perf micro-opts** | SCWindow indexing by id (avoid O(n²)); `Appearance.resolvedStyle` cache for the tile render hot path. ~~forward focus bookkeeping (rapid Cmd+Tab)~~ — dropped at v11.4.4: upstream's `ActivationFocusResolver` intent mechanism (#5596) covers the race, and the manual `frontmostPid` forward-set would break its `frontmostPid != pid` intent-recording guard | `WindowCaptureEvents.swift`, `Appearance.swift`, `TilesView.swift` |
| **Throttler leading edge** | `Throttler` seeded `lastTimeInNanoseconds` with `now` in its constructor, so the FIRST call ever was read as a repeat and pushed a full window. At launch that added ~1.0s to `Applications.manuallyRefreshAllWindows` (already deferred 1s by `applicationDidFinishLaunching`), so the switcher listed no windows for ~3s after start — Cmd+Tab in that window opened it empty. Now `nil` until the first run, which is the leading edge `SchedulingPolicySpecs.md` documents (`testThrottleFirstCallRunsNow`) and `ThrottlerWithKey` already gets from having no map entry. Measured launch → non-empty `--list`: **3.02s → 1.89s** (3 runs each). No unit seam: compiling `Throttler` into the test bundle drags `BackgroundWork` + the AX/CGS/Process schedulers with it | `src/util/Throttler.swift` |
| **Launch inventory sooner** | The one initial window inventory was deferred 1s after launch; the rest of launch is done ~145ms in, so most of that was idle waiting. Now 0.25s, which still clears the launch tail with margin. Measured to a complete window list, 5 launches each: 1s → 1918ms, 0.25s → 1208ms (0.1s → 911ms, rejected: no margin over the 145ms tail, and a login-item start competes with the whole system) | `src/App.swift` |
| **Local build version** | derive `CURRENT_PROJECT_VERSION` / `MARKETING_VERSION` from the latest `chore(release):` commit (CI injects it normally; local builds recover it from git) | `ai/build.sh` |
| **Debug-strip** | gate `DebugWindow` (the "Debug tools" window) + its menubar item + `BenchmarkRunner` behind `#if DEBUG` so a **Release** build carries no debug machinery (QAMenu + DebugMenu live-graph were already `#if DEBUG`) | `App.swift`, `Menubar.swift`, `DebugWindow.swift`, `Benchmark.swift` |
| **No auto-update** | Sparkle is removed entirely: the local SwiftPM package, the framework and its `Updater.app`/`Autoupdate` helpers, `SparkleDelegate`, the `UserDefaultsEvents` class (it existed only to mirror Sparkle's own checkbox back into `updatePolicy`), the menubar's "Check for updates…", the Settings updates-policy row, and the feedback window's pre-form update check. The `updatePolicy` preference itself is left defined but unused, to keep `MacroPreferences` / migrations untouched. Bundle 12MB → 9.5MB. The fork could never update itself anyway (nil feed), so nothing is lost — the feedback window shows its form directly instead of after a check that could only ever fail | `App.swift`, `Menubar.swift`, `GeneralTab.swift`, `PreferencesEvents.swift`, `FeedbackWindow.swift`, `Info.plist`, `project.pbxproj` |
| **Fork-safe XS/XL migration** | Upstream PR #5932 version-gates `migrateAppearanceSizeIndexes` at 11.4.4, but the fork's `App.version` is derived from the last `chore(release):` commit, so it never rises above the stored `preferencesVersion` and the gate can never fire (raising the threshold instead would re-run the shift on *every* launch). Called unconditionally, guarded by a one-shot `fork.migratedAppearanceSizeIndexes` flag so upstream's own gate can't shift the indexes a second time once the PR lands. **Drop together with the #5932 cherry-pick** | `src/preferences/PreferencesMigrations.swift` |

> `vendor/Sparkle` is still checked in — it is simply not referenced by the target. Deleting it
> would be a large diff against upstream for no build-time or runtime gain.

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

### Expected: **940 tests, exactly 18 failures**

All 18 failures are in `LicenseManagerTests` and are **expected** — those tests assert
upstream's trial / trial-expired behavior, but the **Pro-unlock** local patch forces
`state = .pro` (see [Local patches](#local-patches-carried-on-top-of-upstream)). So a
healthy fork run = **zero failures outside `LicenseManagerTests`**. A failure anywhere
else — or a count other than 18 inside `LicenseManagerTests` — is a real regression worth
investigating (e.g. after an upstream merge).

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
