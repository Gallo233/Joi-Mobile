# Joi Mobile Status

Last updated: 2026-08-11

## Current phase

G1 deterministic foundation is published to the private GitHub repository `Gallo233/Joi-Mobile`. The bounded `G2-J1A` Chinese private-fixture preflight and compatibility-preview slice is complete with conditions. No deployment, cloud resource, vendor contact, license application or App Store submission has been made.

## Studio brief

- Outcome: create a buildable iOS 26+ Chat/Map shell, stable shared contracts, backend mock boundary, and three isolated feasibility PoCs.
- Scope: new `joi-mobile` repository and personal `joi-mobile-studio` Skill only.
- Read-only references: desktop Joi and legacy `aiguide-ios`.
- Shared-contract writer: Technical Director / Studio integrator.
- PoC writers: Character Runtime Engineer for Live2D/VRM module; Map, Navigation & Offline Engineer for offline route module.
- Independent verifier: Field QA / Release Integrator.
- External gates: Live2D expandable-application licensing, VRM fixture breadth, map/tile/data rights, real-device performance and field behavior.

### G2-J1A Studio brief

- Outcome: explicit local selection → security admission → Chinese compatibility/rights preview → honest static fallback, without installation or activation.
- Crew: Studio Director, Product Design, Technical, Art & Character, Content & Trust, Trust & Safety, Character Runtime Engineer, iOS Platform Engineer and independent Field QA.
- Ownership: Character Runtime owned admission and package tests; iOS Platform/Product owned App preview and String Catalog; Technical alone owned the handle SPI; Studio integrator owned TDD/STATUS and repository policy.
- Frozen boundary: existing renderer and state-owner contracts remain; `ValidatedCharacterPackageHandle` construction is restricted to the installer SPI. No external runtime dependency or vendor asset is admitted.
- Deferred by design: full ZIP/raw wrapping, immutable install/activation/removal and malicious archive corpus are J1B; native rendering/device work is G4; rights and licenses are G5.

## Scheme gates

| Director | Decision | Conditions / owner |
|---|---|---|
| Product Design | Approved with conditions | G0 rework closed: Map→Chat consent, transition matrix and 32 failure fixtures. Current G2 is `zh-Hans`; additional languages and accessibility are explicitly deferred. |
| Technical | Approved with conditions | G0 rework closed: validated handle, renderer generation lifecycle, planning/following split, unique progress reducer and errors. G1 contract tests remain. |
| AI & Companion | Approved with conditions | G0 rework closed: memory/proposals, precise-location classification/separate sync authorization, transcript and speech priority. G1/G3 tests remain. |
| Art & Character | Approved with conditions | G0 rework closed: capability/fixture/rights/result/fallback/lifecycle matrices. G1 local, G4 device and G5 rights evidence remain. |
| Content & Trust | Approved with conditions | Strict source projection and editable `zh-Hans` copy are current; additional languages are deferred. Chinese fixture and rights evidence remains G2/G5/G6. |
| Trust & Safety | Approved with conditions | G0 rework closed: consent/upload/export/delete/package-sync, foreground-only location, Keychain/analytics/no-resurrection and archive rules. G3 evidence remains; veto retained. |
| Quality & Release | Approved with conditions | G0 rework closed: exact pins, dependency/right policy, device protocol and clean/fuzz/release gates. G1/G4/G5/G6 evidence remains; veto retained. |

G0 is closed with no `Rework` or `Blocked` decision. Public contract implementation may start in dependency order; later gate conditions remain mandatory and cannot be treated as release approval.

### G2-J1A Scheme decisions

| Director | Decision | Conditions / owner |
|---|---|---|
| Product Design | Approved with conditions | Character Library stays secondary and preview-only; Product owns J1B installation/activation journey. |
| Technical | Approved with conditions | One admission seam, installer-only handle SPI and no dependency change; Character Runtime owns immutable installation and mutation revalidation in J1B. |
| Art & Character | Approved with conditions | Private real fixtures may establish metadata baselines only; native stage/device claims remain G4 and rights remain G5. |
| Content & Trust | Approved with conditions | Current visible preview copy is editable `zh-Hans`; source and rights stay explicitly pending. |
| Trust & Safety | Approved with conditions | Explicit local selection, no asset distribution/path logging/upload and non-destructive failure are mandatory; veto retained. |
| Quality & Release | Approved with conditions | Public and private lanes remain separate; private tests must actually run on this workstation and cannot close G4/G5. |

## Verification evidence

| Date | Command / check | Result | Scope |
|---|---|---|---|
| 2026-08-11 | `quick_validate.py` on `joi-mobile-studio` | Pass | Skill structure/frontmatter |
| 2026-08-11 | `test_check_prd_tdd.py` | Pass, 3 tests | PRD/TDD checker self-test |
| 2026-08-11 | Read-only Chat/memory forward task using `$joi-mobile-studio` | Pass | Selected minimal non-art crew, separated one-turn location use from memory authorization, froze five contracts, assigned single writers and required Scheme/Closeout gates |
| 2026-08-11 | Read-only offline Map/character forward task using `$joi-mobile-studio` | Pass | Selected bounded crew, froze six contracts, separated security rejection from static fallback, assigned single writers and kept arbitrary offline rerouting out of scope |
| 2026-08-11 | PRD P0 ID count (`rg`/`uniq`) | Pass, 24 unique IDs | `JM-P0-001` through `JM-P0-024`, each defined once |
| 2026-08-11 | XcodeGen install and pin | Pass, 2.46.0 | Homebrew formula installed and pinned; repository version requirement matches |
| 2026-08-11 | Two consecutive normalized `xcodegen generate --spec project.yml` runs | Pass, two-run SHA-256 equality; current hash `ac27f6fe56a04476b0d87b060ed127c100621f641839f37bf9c740977dc5bbeb` | Generated project reproducibility after final first-slice sources and Chinese catalog were present |
| 2026-08-11 | Six `swift test --package-path Packages/<name>` runs | Pass, 37 tests | CompanionCore 9, CharacterRuntime 16, ChatFeature 3, MapFeature 1, OfflinePack 7, SyncClient 1 |
| 2026-08-11 | Backend and repository Python suites | Pass, 11 tests | Mock SSE/one-turn receipt boundary, real Draft 2020-12 fixture validation, invalid-source rejection and Chinese copy catalog |
| 2026-08-11 | `check_prd_tdd.py docs/PRD.md docs/TDD.md` | Pass | All 24 P0 requirements map to module, interface, test and release gate |
| 2026-08-11 | Generic iOS Simulator `xcodebuild` | Pass | Xcode 26.6 / Swift 6.3.3, all local packages and PoC sources compile |
| 2026-08-11 | iPhone 17 Pro, iOS 26.5 simulator `xcodebuild test` | Pass, 1 test | Chat/Map switch preserves character/session identity |
| 2026-08-11 | Repository secret-pattern scan | Pass | No provider key, access token or private-key signature found outside ignored build output |
| 2026-08-11 | Independent Closeout rework closure and re-review | Pass; no first-slice `Rework` or `Blocked` | Required VRM core failure now falls back; speech returns explicit reject/preempt; Chat rejects foreign events and owns cancellation; journey attachments require digest/identity/expiry/revocation/one-use receipts; source projections are strict schema objects |
| 2026-08-11 | `G2-J1A` public Swift package regression | Pass, 48 defined tests: 46 pass and 2 expected private-fixture skips | CompanionCore 9, CharacterRuntime 27, ChatFeature 3, MapFeature 1, OfflinePack 7, SyncClient 1; private cases run separately below |
| 2026-08-11 | Private CharacterRuntime lane with explicitly supplied fingerprints | Pass, 9 tests, 0 failures, 0 skips | 桃瀬ひより tree `6cba59…175c8`, 17 files; `AvatarSample_A` VRM `2a0ccd…827f5`; both payloads remain outside the repository |
| 2026-08-11 | Repository and Backend Python suites | Pass, 16 tests | 11 contract/copy/asset-policy tests and 5 mock-backend tests using pinned `jsonschema` environment |
| 2026-08-11 | Two consecutive XcodeGen generations | Pass, identical SHA-256 `10c47decc9da057add9bb2ddeb10a9b846d6ec935441fe3539d683ece5cd4d1d` | Generated project reproducibility with Character Library source and Chinese catalog |
| 2026-08-11 | Generic iOS Simulator build | Pass | G2-J1A App and all local packages compile with Xcode 26.6 / Swift 6 |
| 2026-08-11 | iPhone 17e, iOS 26.5 simulator test | Pass, 3 tests, 0 skips | Chat/Map continuity plus successful/failed character preview preserve character, thread, session and journey state |
| 2026-08-11 | Private-asset policy, history/secret scan and generated App bundle audit | Pass | No tracked/history/App-bundled `.vrm`, `.vrma`, `.moc3` payload, local absolute production path, Cubism runtime, VRMKit runtime or provider credential |

The visible Chat composer, push-to-talk button, character runtime surface, Map card, navigation, source button and profile control are **placeholders**. The first slice proves composition/state/contracts and PoC seams; it does not provide complete Chat, Map, account, sync or production-backend journeys.

## PoC evidence

### Native Live2D

Asset-free scaffold complete. `JMLive2DModel3Inspector` checks model metadata and declared multi-texture, Motion, Expression, Physics, Pose, EyeBlink and LipSync references. `JMLive2DNativeAdapter` isolates a future Cubism Native/Metal implementation behind an actor boundary and tests generation invalidation, stale-load suppression, fallback and exactly-once release. Six Live2D tests pass, including 50 load/release cycles.

`G2-J1A` additionally admitted the private 桃瀬ひより fixture by its 17-file tree fingerprint and confirmed two textures, ten motions, Physics, Pose, EyeBlink and LipSync; Expression is correctly reported as undeclared. The asset was not copied, bundled, logged, uploaded or committed.

This does **not** prove Cubism SDK integration, actual Metal rendering, licensed model compatibility, frame rate, GPU release, heat or the Live2D release license. Those remain G4/G5 conditions.

### Native VRM

Asset-free scaffold complete. `VRMNativeMetadataInspector` distinguishes JSON/GLB glTF, VRM 0.x, VRM 1.0 and VRMA metadata and reports Humanoid, MToon, Expressions, LookAt, Constraints, Spring Bone, animation and lip-sync expectations. `VRMNativeAdapter` keeps RealityKit/Metal and any future VRMKit usage behind an owned internal bridge, with generation, cancellation, required-core fallback and exactly-once release tests. Eight VRM tests pass using self-authored metadata fixtures.

`G2-J1A` additionally admitted the private `AvatarSample_A` fixture by exact SHA-256, confirmed VRM 0.x plus its declared Humanoid/MToon/expression/look-at/spring-bone/lip-sync metadata, and did not claim VRM 1.0 or VRMA coverage. The asset was not copied, bundled, logged, uploaded or committed.

This does **not** prove real RealityKit/Metal loading, MToon fidelity, VRMA playback, Spring Bone behavior, model breadth, frame rate, GPU release, heat or device compatibility. Rights-cleared fixture and G4/G5 evidence remain required.

### Offline cultural walking route

The dependency-free route PoC projects locations onto an immutable cached walking route, derives candidate progress and arrival, detects departure and returns distance/bearing to the accepted route. Adapter seams reserve MapLibre offline-corridor rendering and Ferrostar cached navigation; cached-only planning explicitly returns `newRouteUnavailableOffline`. Six route tests plus the existing pack-rights test pass, including stale/stopped session rejection and proof that only `JourneyContextStore` can commit progress.

This does **not** prove MapLibre/Ferrostar runtime integration, downloaded tile rights, flight-mode field behavior, production-grade map matching, maneuvers or ETA. Arbitrary offline rerouting remains intentionally out of scope.

## Closeout gates

| Director | Closeout decision | Remaining condition |
|---|---|---|
| Product Design | Approved with conditions | Shell/PoC scope only; complete Chat/Map journeys and G2 Chinese human review remain |
| Technical | Approved with conditions | G1 foundation passed; production adapters/services remain later implementation |
| AI & Companion | Approved with conditions | Real model/STT/TTS, durable memory and device interruption evidence remain G3/G4 |
| Art & Character | Approved with conditions | Asset-free seams only; real Cubism/RealityKit/Metal, legal fixtures, device performance and licenses remain G4/G5 |
| Content & Trust | Approved with conditions | Strict schema and Chinese catalog passed; cultural/source/rights review remains G2/G5/G6 |
| Trust & Safety | Approved with conditions | Local receipt gate passed; production replay storage, account binding, deletion and abuse evidence remain G3 |
| Map / Offline | Approved with conditions | Geometry/seams passed; real MapLibre/Ferrostar, flight-mode field work and map rights remain G4/G5 |
| Quality & Release | Approved with conditions | G1 commands passed; device, rights and release gates remain G4/G5/G6 |

G1 first-slice Closeout is approved with conditions and has no remaining `Rework` or `Blocked` decision. G2 Chinese content review, G3 production privacy/abuse evidence, G4 real-device/field/performance, G5 rights/licenses and G6 release evidence remain open. Additional languages and full accessibility validation are explicitly deferred. Simulator results do not close real-device, field, thermal, energy, background audio/location, microphone/camera, or vendor-license gates.

### G2-J1A Closeout

| Director | Closeout decision | Remaining condition |
|---|---|---|
| Product Design | Approved with conditions | Preview-only slice closed; full installation, activation and removal remain J1B. |
| Technical | Approved with conditions | Admission, VRM magic, Live2D graph and installer SPI passed; full archive member validation, immutable installation and mutation revalidation remain J1B. |
| Art & Character | Approved with conditions | Both real private metadata lanes passed; native rendering/fidelity/performance remain G4 and rights remain G5. |
| Content & Trust | Approved with conditions | Chinese compatibility/source/rights copy passed; retained authorization receipts remain G5. |
| Trust & Safety | Approved with conditions | Preview is non-destructive and assets/paths stay out of production; isolated installer and malicious archive corpus remain J1B. |
| Quality & Release | Approved with conditions | Public/private tests, simulator build and bundle audit passed; device and rights gates remain open. |

Independent Closeout found no `Rework` or `Blocked` decision for this bounded slice. `G2-J1A` is closed with conditions. This does not close complete G2, `JM-P0-015`, `JM-P0-017`, G4 or G5.
