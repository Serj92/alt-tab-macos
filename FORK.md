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
| **Xcode 16 compat** | `#if compiler(>=6.2)` guards around macOS-26 / Liquid Glass APIs; one trailing comma dropped | `SettingsWindow`, `TilesView`, `Appearance`, `TilesPanelBackgroundView`, `PermissionsWindow` |
| **Perf micro-opts** | forward focus bookkeeping (rapid Cmd+Tab); SCWindow indexing by id (avoid O(n²)); `Appearance.resolvedStyle` cache for the tile render hot path | `App.swift`, `WindowCaptureEvents.swift`, `Appearance.swift`, `TilesView.swift` |
| **Local build version** | derive `CURRENT_PROJECT_VERSION` / `MARKETING_VERSION` from the latest `chore(release):` commit (CI injects it normally; local builds recover it from git) | `ai/build.sh` |
| **Debug-strip** | gate `DebugWindow` (the "Debug tools" window) + its menubar item + `BenchmarkRunner` behind `#if DEBUG` so a **Release** build carries no debug machinery (QAMenu + DebugMenu live-graph were already `#if DEBUG`) | `App.swift`, `Menubar.swift`, `DebugWindow.swift`, `Benchmark.swift` |
| **No auto-update** | `SparkleDelegate.feedURLString` returns `nil` (the only feed source — Info.plist has no `SUFeedURL`) and the 30s post-launch `startUpdater()` is removed, so the fork can never replace itself with an official build | `src/vendors/SparkleDelegate.swift`, `App.swift` |

> The "Check for updates…" menubar item and the Settings button still exist but are
> defanged by the nil feed — they can't download anything. Remove them too if you want
> them gone from the UI (a couple more small edits).

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

### Expected: **538 tests, exactly 18 failures**

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

1. **Re-apply `#if compiler(>=6.2)` guards** on any *new* macOS-26 / Liquid Glass /
   Swift-6.2 code upstream introduced (the big risk area: settings UI, new files).
2. `bash ai/build.sh` until it compiles on Xcode 16 (fix any new compat issues).
3. `bash ai/install.sh` to rebuild the Release daily driver and install it.
4. Sanity-check: rapid Cmd+Tab + your usual flow.

Note: `ai/build.sh` signing fails with `No certificate matching 'Local Self-Signed'`
only when `config/local.xcconfig` is missing — recreate it (see above).

---

*Last synced to upstream: **v11.3.1** (2026-06-23).*
