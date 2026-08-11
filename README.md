# Joi Mobile

Joi Mobile is an iPhone companion product vision with two primary surfaces:

- **Chat** — a full native character stage for text, push-to-talk, speech, and local layered memory.
- **Map** — a cultural walking companion for arrive-and-tell, see-and-ask, narrative routes, trusted sources, and downloaded tours.

The current repository slice is a buildable shell, contract foundation and three repository-asset-free PoCs. `G2-J1A` adds a secondary Character Library with local Live2D/VRM preflight and an honest static-fallback preview; it does not install, activate or natively render the selected model. Chat, push-to-talk, Map/navigation and the profile panel remain placeholders. Current editable product copy is Simplified Chinese. Additional languages and full accessibility validation are deferred. The repository is intentionally independent from the legacy Joi Map and desktop Joi worktrees and shares versioned character/event semantics through contracts, not source-tree coupling.

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

## Private character compatibility lane

`G2-J1A` can inspect a locally selected Live2D `.model3.json` tree or VRM file without copying the asset into this repository. The committed values below are fingerprints only; the model payloads remain private and must not be bundled, logged, uploaded or pushed.

```bash
export JOI_MOBILE_LIVE2D_FIXTURE_ENTRY_URL='/absolute/path/to/model.model3.json'
export JOI_MOBILE_LIVE2D_FIXTURE_TREE_SHA256='6cba59fe0631a94a2c40d535f2312f3b31ddabd9c7ad45418082a7bf8e3175c8'
export JOI_MOBILE_LIVE2D_FIXTURE_FILE_COUNT='17'
export JOI_MOBILE_VRM_FIXTURE_FILE_URL='/absolute/path/to/avatar.vrm'
export JOI_MOBILE_VRM_FIXTURE_SHA256='2a0ccd84880b03d7b65503d8b6287f7a97f3bb4fab70a5fd0a47b433c97827f5'

swift test --package-path Packages/CharacterRuntime \
  --filter PrivateFixtureAdmissionTests
```

This lane proves file admission and metadata compatibility only. It does not prove native Cubism/RealityKit rendering, VRM 1.0, VRMA, real-device performance or distribution rights.
