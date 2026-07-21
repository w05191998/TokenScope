---
name: run-app
description: Build, package, and (re)launch the TokenScope menu bar app locally to verify a change in the real app. Use when asked to run the app, test a UI change visually, or produce a fresh local build.
---

# Run TokenScope locally

## Quick run (debug, no bundle)

```sh
swift run TokenScope
```

Menu bar item appears immediately; Ctrl-C to stop. Fine for logic checks, but no app icon and no `LSUIElement` behavior.

## Full run (release bundle — what users get)

```sh
pkill -x TokenScope || true
bash scripts/package_unsigned_dmg.sh
open "$(ls -td dist/TokenScope-*-unsigned-*/TokenScope.app | head -1)"
```

Then confirm: `pgrep -x TokenScope` prints a PID.

## Verify checklist after UI changes

- Menu bar shows the ⌖ scope icon + cost text.
- Popover opens on click; check **both light and dark mode** (palette is semantic colors — dark regressions were a real bug class here).
- Overview shows either data or, on a machine with no logs, the onboarding copy mentioning `~/.claude` / `~/.codex`.
- System tab shows storage diagnostics without errors.

## Notes

- `dist/` and `.build/` are gitignored; packaging output accumulates — old `dist/TokenScope-*` folders are safe to delete.
- The app reads real logs from `~/.claude` and `~/.codex`; there is no sandbox/test mode. To simulate a fresh-install empty state, use the popover's System tab → Clear Data (deletes only TokenScope's own SQLite DB, not the logs).
- Screenshots cannot be taken by the agent (screen-recording permission); ask the user to capture them.
