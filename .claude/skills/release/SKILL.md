---
name: release
description: Cut a TokenScope release end to end — version bump, CHANGELOG, DMG build, tag, GitHub Release. Use when asked to release, ship, or publish a new TokenScope version.
---

# Release TokenScope

Follow the generic `swift-release-flow` skill if installed; these are the TokenScope-specific facts it needs.

## Project specifics

- **Version lives in one place**: `VERSION="X.Y.Z"` in `scripts/package_unsigned_dmg.sh` (~line 6). No Info.plist file exists in-repo (the script generates it).
- **Changelog**: `CHANGELOG.md`, Keep-a-Changelog style. Move `## Unreleased` items under `## X.Y.Z - YYYY-MM-DD`; rewrite entries as user benefits.
- **Artifact**: `bash scripts/package_unsigned_dmg.sh` → `dist/TokenScope-X.Y.Z-unsigned-<timestamp>/TokenScope-X.Y.Z-unsigned.dmg`. Verify with `hdiutil verify <dmg>`.
- **CI must be green** on `main` before tagging: `gh run list --limit 1`.
- **Repo**: `w05191998/TokenScope`; git identity is repo-local (`w05191998`) — do not change global config.

## Release notes template

Include this note verbatim (builds are unsigned):

> ⚠️ This build is unsigned. macOS Gatekeeper will warn on first launch — right-click the app → Open to bypass. See `docs/SIGNING_NOTARIZATION.md` for details.

Mark releases `--prerelease` while the app is 0.x and unsigned.

## Command sequence

```sh
swift test                                  # must be green
# bump VERSION in scripts/package_unsigned_dmg.sh, update CHANGELOG.md, commit
bash scripts/package_unsigned_dmg.sh
DMG=$(ls -t dist/TokenScope-*/TokenScope-*-unsigned.dmg | head -1)
hdiutil verify "$DMG"
git tag -a vX.Y.Z -m "TokenScope X.Y.Z" && git push origin vX.Y.Z
gh release create vX.Y.Z "$DMG" --title "TokenScope X.Y.Z" --notes-file <notes> --prerelease
```

## After release

- Check the release page renders and the DMG downloads.
- Start the next `## Unreleased` section in `CHANGELOG.md`.
