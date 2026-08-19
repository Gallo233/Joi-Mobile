# Joi Mobile Repository Instructions

Use `$joi-mobile-studio` from `/Users/liujialuo/.codex/skills/joi-mobile-studio` for all product, architecture, implementation, review, testing, and release work in this repository.

## Source of truth

1. Current user instruction.
2. This repository's executable contracts, code, tests, `docs/PRD.md`, and `docs/TDD.md`.
3. `/Users/liujialuo/Documents/New project 2/Joi` as read-only desktop contract reference.
4. `/Users/liujialuo/Documents/design/aiguide-ios` as read-only legacy product/behavior reference.

Never modify or copy uncommitted changes from either reference repository.

## Collaboration

- Produce a Studio Brief before cross-domain edits.
- Assign exactly one writer per file and one owner for shared contracts, `project.yml`, and localization catalogs.
- Freeze public contracts before parallel consumer work.
- Require affected Director scheme and closeout decisions. Trust & Safety and Quality & Release retain veto authority.
- Keep derived data outside the repository and preserve unrelated worktree changes.

## Product boundaries

- Keep Chat and Map as the only primary surfaces.
- Keep `CompanionSessionStore`, `JourneyContextStore`, and `SpeechCoordinator` as unique state owners.
- Keep character packages separate from user memory/runtime state.
- Use native character runtimes only; no Unity, WKWebView, or Three.js fallback.
- Never add client-side provider secrets. Backend calls go through the official proxy boundary.
- Keep offline routing claims limited to cached-route progress and return-to-route guidance.
- Keep current visible copy in an editable `zh-Hans` String Catalog. Additional languages and full VoiceOver, Dynamic Type, and Reduce Motion validation are deferred gates; do not claim them complete.
- Do not claim device-only location, audio, camera, frame-rate, energy, or thermal evidence from a simulator.

## Required checks

Run the smallest relevant subset, then the full lane for cross-module changes:

```bash
python3 /Users/liujialuo/.codex/skills/joi-mobile-studio/scripts/check_prd_tdd.py docs/PRD.md docs/TDD.md
xcodegen generate --spec project.yml
xcodebuild -project JoiMobile.xcodeproj -scheme JoiMobile -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/JoiMobileDerived build
swift test --package-path Packages/CompanionCore
swift test --package-path Packages/CharacterRuntime
swift test --package-path Packages/OfflinePack
Tools/run_native.sh
```

The last line is not optional, and it is not a convenience. `project.yml` is the
bottom rung of the spec ladder and admits no vendor runtime, so the generate
above replaces a native `JoiMobile.xcodeproj` with one that cannot draw a Live2D
or VRM character, and the build that follows installs that app over the native
one on the simulator. The character stage then shows its static silhouette,
which is correct behaviour and looks exactly like a broken model — a trap that
has cost three debugging cycles. `Tools/run_native.sh` puts the native build
back. Skip it only when `Vendor/Live2D` and `Vendor/VRMMetalKit` are absent,
which is the one case where there is nothing to restore.

Record actual evidence and remaining device/legal gates in `docs/STATUS.md`. Record durable product/architecture choices in `docs/DECISIONS.md`; do not create separate PoC status documents.
