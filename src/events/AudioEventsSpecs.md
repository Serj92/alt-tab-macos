# AudioEvents — Specs

> Fork-local (AltTabFix). Not in upstream. Upstream closed the request (#2638) believing no public API exists.

## Summary

A status icon (`speaker.wave.2.circle.fill`: a white speaker on a green disk, the only colored status icon;
tooltip "Playing audio") on the tiles of windows that are playing
audio, next to the minimized / fullscreen / hidden / Space icons, and hidden with them by
**Hide status icons**.

- `AudioEventsTestable`: the pure decisions (which app owns a sounding process; which windows to mark).
- `AudioEvents`: the shell. CoreAudio listeners, the AX read of tab strips, the hop to main.
- `Application.audio` (`AppAudio`) holds the answer; `Window.isPlayingAudio` derives it per tile.

## Which app is sounding

CoreAudio lists one process object per audio client (`kAudioHardwarePropertyProcessObjectList`, macOS 14.2+),
each with `kAudioProcessPropertyIsRunningOutput` and `kAudioProcessPropertyPID`. Reading them needs no
permission (it captures nothing, unlike a process tap). Listeners on the list and on each object's output flag
drive everything: nothing polls.

The sounding process is often not the app:

| Case | Sounding process | Owner |
|---|---|---|
| Brave, Helium, Chrome | `… Helper`, parent is the browser | parent |
| `afplay` in Terminal | afplay → zsh → login → Terminal | 3rd ancestor |
| App playing itself (Music, Telegram) | the app | itself |
| Safari | `com.apple.WebKit.GPU`, parent launchd | nobody |

Rule: the sounding pid, else its nearest ancestor that AltTab knows as an app, however deep (a command run
by a tool inside Terminal is 5 hops down), never launchd. A detached process (`(cmd &)`) is reparented to
launchd and belongs to nobody. A process whose app is not in `Applications.list` yet is picked up by the next CoreAudio change
or the next summon.

## Which window

Audio belongs to a process, not a window. The window is only knowable where the app says it:

- **Chromium tab strips.** Each tab button's AX title carries the tab's alert state:
  `<page title> - Audio playing - Memory usage - 394 MB` (Brave; Chrome has no memory part). The strip
  sits 7 `AXGroup`s below the window, its tabs are `AXRadioButton` / `AXTabButton`. A window is marked
  when one of its tabs contains ` - Audio playing`.
- **Everything else** marks all of the app's windows (`.allWindows`). Exact for a single-window app; for
  several windows it says "this app", which is all that is known.

Decision table (`AudioEventsTestable.audio`), per sounding app, over its windows' reads:

| Reads | Result |
|---|---|
| some tab labelled playing | `.windows(those)`, even if another window failed to read |
| no labelled tab, some window unreadable | no answer: keep the previous one |
| no window known | no answer (see below) |
| no labelled tab, some window has a strip | `.windows([])`: no icon (muted tab, sound just stopped) |
| no strip anywhere | `.allWindows` |

At launch AltTab knows an app before its windows, and a window before its AX element. A read in that gap
once answered `.allWindows` for Brave and lit all 43 of its tiles, so a window without an AX element counts
as unreadable and an app with no known window gets no answer. The cost: a windowless app's tile (Music with
its window closed) never shows the icon.

A strip that is a DIRECT child of the window is macOS's own tab bar (Finder, Terminal), never Chromium's,
and carries no audio state, so it is not read as one.

## When it is read

- Output starts for an app → read its strips once.
- Output stops → `.silent` at once, no read.
- Every summon (`App.buildUiAndShowPanel`, after the visible work) → re-read CoreAudio, then every sounding
  app: a `.windows` answer can go stale, and an earlier read may have proved nothing. A strip-less app costs
  10-20 AX calls. The audible tab can change without CoreAudio noticing:
  another tab starts within the same output, or a tab is dragged to another window. The tile shows the
  previous answer immediately and repaints if the read changes it.

## Cost (measured 2026-10-09, 44 Brave windows, 378 tabs)

- Silent: nothing.
- One strip read of all Brave windows: ~1100 AX calls, 80-110ms on the AX scan lane. AltTab's main thread
  is untouched; Brave's UI thread answers the calls. Helium, 19 windows: 27-45ms. Finder, Terminal: under 20
  calls, the `AXGroup`-only descent stops at once.

## Known limits

- Only the English UI string is matched. A Brave switched to another language never shows the icon (no
  false icon either).
- Safari is not attributed (see the table). Firefox was not checked.
- A tab inside a collapsed Chromium tab group is not exposed, so its window is not marked.
- Not verified yet: a playing tab that is not the selected tab of its window.
