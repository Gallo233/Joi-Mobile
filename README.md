# Joi Mobile

Joi Mobile is an iPhone companion product vision with two primary surfaces:

- **Chat** — a full native character stage for text, push-to-talk, speech, and local layered memory.
- **Map** — a cultural walking companion for arrive-and-tell, see-and-ask, narrative routes, trusted sources, and downloaded tours.

The current repository slice is a buildable shell, contract foundation and three asset-free PoCs; Chat, push-to-talk, Map/navigation and the profile panel remain placeholders. Current editable product copy is Simplified Chinese. Additional languages and full accessibility validation are deferred. The repository is intentionally independent from the legacy Joi Map and desktop Joi worktrees and shares versioned character/event semantics through contracts, not source-tree coupling.

## Repository map

- `JoiMobile/` — SwiftUI app shell and composition root.
- `Packages/` — modular Swift features and runtime adapters.
- `Backend/` — local mock and future official proxy boundary; no production credentials.
- `Contracts/` — cross-platform JSON Schema and OpenAPI artifacts.
- `Tests/` — repository-level contract and integration checks.
- `docs/PRD.md` / `docs/TDD.md` — product and technical source of truth.
- `docs/STATUS.md` / `docs/DECISIONS.md` — evidence, gates, and durable decisions.

## Bootstrap

The Xcode project is generated from `project.yml` with a pinned XcodeGen version. Do not hand-edit or commit generated `project.pbxproj` state.

```bash
xcodegen generate --spec project.yml
xcodebuild -project JoiMobile.xcodeproj -scheme JoiMobile -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/JoiMobileDerived build
```

See `AGENTS.md` for Studio routing and required checks.
