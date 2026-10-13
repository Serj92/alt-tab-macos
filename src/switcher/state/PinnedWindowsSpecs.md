# PinnedWindows — Specs

> Fork-local (AltTabFix). Not in upstream. Upstream declined app pinning as too niche (#3425, #4945, #5237;
> #4684 still open), partly because pins in front push "the previous window" off the first Tab press. The
> default pick below is the answer to that.

## Summary

The user pins a window; pinned windows lead the switcher, in the order they were pinned, and every other
window keeps the user's order (recently focused first, by default). A pin belongs to one window and lives
as long as that window is open.

- `PinnedWindowsTestable`: the pure pin list (toggle, prune, restore).
- `PinnedWindows`: the shell. The list in memory and on disk, the toggle, the WindowServer liveness query.
- The order rule is `OrderWindow.pinRank` in `WindowOrderResolver`; the default pick reads the list without
  pins through `SelectionInputs.pickOrder` in `SelectionResolver`. Both are fork-local fields with defaults.
- `Window.isPinned` derives the state per tile.

## Pinning

| Control | Where | Effect |
|---|---|---|
| Lilac button | Top-right corner of the thumbnail, under the pointer, with the four colored buttons (which stay top-left) | Toggles the window's pin |
| `P` while the switcher is open | Rebindable: Settings → Controls → Shortcuts When Active → "Pin/Unpin window" | Toggles the selected window's pin; the selection follows the window to its new tile |
| Lilac badge | Same corner, always drawn on a pinned window's tile | Mark only, never clicked: the hover button covers it exactly |

Pinned: a filled lilac disk (`#A98BF5`) with a dark filled pin. Not pinned (shown under the pointer only): a
lilac ring on a dark scrim with an outline pin. Lilac, the "deeper" of three mockup tones, was the owner's
pick; it stays lilac under the graphite tint. The button and badge show where the colored buttons do:
thumbnails style, **Hide colored circles on mouse hover** off. In the other styles `P` still works but nothing is drawn.

On a thumbnail too narrow for both, the left row wraps one button earlier rather than run under the pin.

## Order

| Situation | Order |
|---|---|
| Pins present, no search, one tile per window | Pinned windows by pin order, then the rest by the shortcut's own order |
| A pinned window in a "show at the end" bucket (minimized, hidden, windowless) | Still leads: a pin outranks the buckets |
| Search active | Match and relevance only; pins ignored |
| **Show one window per app** | Pins ignored |
| A shortcut's filters exclude a pinned window (⌥⇥ = active app only) | Not shown; a pin never forces a window into a list |

## Default pick

One alt-tab still goes to the window the user was on before, wherever that window now sits. The selection
kernel picks over the list as it would be without pins (`pickOrder`, recomputed from the current list on
every refresh, so it cannot go stale), and the pick is mapped back to its drawn tile. If the previous window is
itself pinned, the pick lands on its pinned tile.

## Life of a pin

| Event | Pin |
|---|---|
| Window closed, app quit | Dropped at the next summon |
| Window closed while AltTab was not running | Dropped at the next summon |
| AltTab relaunched (each install relaunches it) | Kept: stored per boot in the `<bundle id>.pins` suite |
| Mac rebooted | Dropped: window numbers start over each boot, so a stored number could name another window |
| Window leaves AltTab's model without closing (admission re-run) | Kept; it shows again when the window does |

Liveness is the WindowServer's answer (`CGSCallScheduler.existingWindowIds`), asked once per summon, off
main, never the model: windows leave the model without closing (`Windows.removeWindows`). A failed query
drops nothing, and a pin added while the query was in flight was not asked about, so it stays.

Pins live in their own defaults suite, not the preferences domain: they are state, so a settings reset leaves
them alone.

## Known limits

- **Native tabs** (Finder, Terminal): the pin is on the tab's window number, so switching to another tab of
  the group shows an unpinned tile until you switch back.
- **A relaunched app's windows are new windows.** Restarting the browser drops its pins; pinning again is
  needed. Matching "the same window" by title was rejected: the title is the active tab and changes all the time.
- **Checked live** (Debug, `--qa-pin=<wid>`, 2026-10-10, 66 tiles): pin order and badges, the previous window
  still selected (moved from tile 2 to tile 4), unpin while open, survive a relaunch, a closed window dropped
  at the next summon. **Not checked live:** the hover button (it needs the real pointer) and ⌥⇥ (summoning
  from the CLI makes AltTab the active app, which has no windows).
