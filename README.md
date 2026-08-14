# Joi Mobile

Joi Mobile is an iPhone companion product vision with two primary surfaces:

- **Chat** — a full native character stage for text, push-to-talk, speech, and local layered memory.
- **Map** — a cultural walking companion for arrive-and-tell, see-and-ask, narrative routes, trusted sources, and downloaded tours.

The current repository slice is a buildable shell, contract foundation and three repository-asset-free PoCs. `G2-J1B` adds a secondary Character Library with local preview, content-addressed installation, rights quarantine, installer-issued activation leases, honest static fallback and verified removal for `.joi-character`, raw VRM and Live2D ZIP inputs. It still does not claim native model rendering. Chat, push-to-talk, Map/navigation and the profile panel remain placeholders. Current editable product copy is Simplified Chinese. Additional languages and full accessibility validation are deferred. The repository is intentionally independent from the legacy Joi Map and desktop Joi worktrees and shares versioned character/event semantics through contracts, not source-tree coupling.

## Repository map

- `JoiMobile/` — SwiftUI app shell and composition root.
- `Packages/` — modular Swift features and runtime adapters.
- `android/` — the second native client. Portable Kotlin core today; no UI or renderer yet.
- `Backend/` — local mock and future official proxy boundary; no production credentials.
- `Contracts/` — cross-platform JSON Schema and OpenAPI artifacts.
- `Contracts/conformance/` — executable vectors every client must pass.
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

## Running a conversation locally

Chat needs a backend on `http://127.0.0.1:8787`. Two are provided, and the app talks to both through the same `/v1/chat/streams` contract.

Deterministic contract mock, no network and no credential — this is what the test lanes use:

```bash
Backend/.venv/bin/python Backend/mock_server.py
```

Real provider, for actually talking to your character. The credential is read from the process environment only; never place it in a file inside this repository, a build setting or an Xcode scheme:

```bash
export DEEPSEEK_API_KEY=...
Backend/.venv/bin/python Backend/proxy_server.py
```

The proxy exits rather than starting without a key, so a missing credential cannot degrade into a silently faked answer. The provider and model are server-side facts: client frames carry only `joi.companion-event.v1` fields and the stable codes `upstream_unavailable`, `upstream_rejected` and `upstream_malformed`. Plain HTTP is accepted only on loopback; every other host must be HTTPS.

## Private character compatibility lane

The private compatibility lane can inspect and locally import a selected Live2D `.model3.json` tree or VRM file without copying the asset into this repository. The committed values below are fingerprints only; the model payloads remain private and must not be bundled, logged, uploaded or pushed.

```bash
export JOI_MOBILE_LIVE2D_FIXTURE_ENTRY_URL='/absolute/path/to/model.model3.json'
export JOI_MOBILE_LIVE2D_FIXTURE_TREE_SHA256='6cba59fe0631a94a2c40d535f2312f3b31ddabd9c7ad45418082a7bf8e3175c8'
export JOI_MOBILE_LIVE2D_FIXTURE_FILE_COUNT='17'
export JOI_MOBILE_VRM_FIXTURE_FILE_URL='/absolute/path/to/avatar.vrm'
export JOI_MOBILE_VRM_FIXTURE_SHA256='2a0ccd84880b03d7b65503d8b6287f7a97f3bb4fab70a5fd0a47b433c97827f5'
# Optional: a package built by Tools/make_character_package.py with --motion, to
# prove the DEC-024 motion table survives a real install with real .vrma clips.
export JOI_MOBILE_VRM_MOTION_PACKAGE_URL='/absolute/path/to/avatar.joi-character'

swift test --package-path Packages/CharacterRuntime
```

This lane proves admission, safe local wrapping and metadata compatibility only. Unknown-rights inputs remain quarantined and cannot activate. It does not prove native Cubism/RealityKit rendering, VRM 1.0, VRMA, real-device performance or distribution rights.

## Cross-platform conformance

A JSON Schema pins a document's shape. It cannot pin that a duplicate key makes a manifest inadmissible, which of two envelopes sharing the `joi.character.v1` label a document belongs to, which stable code each refusal produces, how a package's content identity is computed byte for byte, or how the event stream is framed. All of that was Swift source with English around it, which is not something a second client can be tested against.

`Contracts/conformance/` holds those semantics as executable vectors — 100 of them today — and every client runs the same files:

```bash
swift test --package-path Packages/CharacterRuntime --filter Conformance
swift test --package-path Packages/ChatFeature --filter Conformance
cd android && ./gradlew test
python3 Tools/make_conformance_corpus.py --check
```

See `Contracts/conformance/README.md` for the rules, and `docs/DECISIONS.md` DEC-026 for what running them against the shipping iOS implementation found.

## Android

`android/` is the second native client: Kotlin, plain-JVM modules mirroring the Swift packages, no Android SDK required to build or test them. It has no UI, no renderer and no networking yet. See `android/README.md` for what exists, what is deliberately deferred and why the portable core came before the shell.
