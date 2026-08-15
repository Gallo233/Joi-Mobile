# Joi Mobile Status

Last updated: 2026-08-12

## Current phase

G1 deterministic foundation and the bounded `G2-J1A` preview slice are published to the private GitHub repository `Gallo233/Joi-Mobile`. The local `G2-J1B` import/install/activation/removal implementation has closed its first Closeout rework and is a Director re-review candidate on branch `codex/j1b-character-installer`. No deployment, cloud resource, vendor contact, license application, App Store submission or J1B remote push has been made.

`G2-J2A`, the first Journey 2 slice, is now implemented locally on the same branch: one Chat text turn runs end to end with an accepted transcript, incremental draft rendering, explicit stop and named failure states. It runs against either the deterministic contract mock or `Backend/proxy_server.py`, a local development proxy that answers from a real provider while holding the credential in its own process environment only. It is not Director-reviewed. Push-to-talk, memory proposals, source rendering and journey attachment remain unimplemented, and no cloud proxy has been deployed.

On 2026-08-13 the first Android-facing slice landed on the same branch, ahead of any Android UI work. `Contracts/conformance/` turns the semantics a second client must reproduce exactly — strict manifest scanning, envelope discrimination, stable refusal codes, content identity and SSE framing — into 100 executable vectors that the shipping iOS implementation and a new portable Kotlin core both run. `android/` holds that core: three plain-JVM modules mirroring the Swift packages, with no Android SDK required and no UI, renderer or networking yet. Running the vectors against iOS for the first time found three disagreements; two are fixed (DEC-026, DEC-028) and one is an open identity defect recorded in DEC-026. The Kotlin core compiles and passes on first build — 11 tests, 0 failures — and its content-identity case makes that open defect a measured divergence between two runners rather than an inference from reading Swift. No Android application module exists, and no vendor renderer has been evaluated.

On 2026-08-12 the J1B candidate was independently re-verified on this workstation before hand-off acceptance. One recorded evidence row did not reproduce: the CharacterRuntime suite failed on activation-lease revocation. The defect is fixed, the previously uncovered pre-CAS path now has a test, and every lane was re-run and re-recorded below. Superseded rows are kept rather than deleted so the evidence history stays auditable.

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

### G2-J1B Studio brief

- Outcome: local `.joi-character`, raw VRM and Live2D ZIP preview → explicit install → optional activation → verified removal, while rights-unknown content remains quarantined.
- Crew: Studio Director; Product, Technical, AI & Companion, Art & Character, Content & Trust, Trust & Safety and Quality Directors; Character Runtime and iOS Platform implementers; independent Closeout reviewer.
- Ownership: Character Runtime alone owns staging, ZIP policy, adapters, immutable storage, activation leases and deletion recovery; App owns UI orchestration; `CompanionSessionStore` remains the sole active-selection writer.
- Frozen boundaries: exact ZIPFoundation pin only; no Cubism/VRM native runtime admission; private fixtures are process-only inputs; no asset path/payload in Git, product logs or bundle.
- Deferred by design: native animation/fidelity/performance are G4; retained redistribution/license receipts are G5; sync/export/update/signatures, extra languages and full accessibility remain later work.

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
| 2026-08-11 | J1B CharacterRuntime public suite | **Superseded — did not reproduce.** Recorded as 59 tests with 55 passes and 4 skips; independent re-verification measured 54 passes, 4 skips and 1 failure | See the 2026-08-12 rows: `testPostInstallMutationMakesCatalogUnavailableAndInvalidatesHandle` failed because detected mutation did not revoke outstanding activation leases |
| 2026-08-11 | J1B full private CharacterRuntime lane | **Superseded — not re-confirmed at the recorded count** | Fingerprints and admission paths reproduce; the installer lease defect above was present in the same tree |
| 2026-08-11 | J1B installer lane under Address Sanitizer | Pass, 32 tests with 2 expected private skips | Deterministic parser/import/removal corpus; this is not coverage-guided fuzzing or device evidence |
| 2026-08-11 | J1B exact dependency and notice policy | Pass | ZIPFoundation `0.9.20`, revision `22787ffb59de99e5dc1fbfe80b19c97a904ad48d`, MIT notice, no high-level `unzipItem` |
| 2026-08-11 | Current Desktop Joi normalized-shape synthetic fixture | Pass | Explicit legacy discriminator and `zh→zh-Hans`; receipt retains bounded attribution/update fields while dropping capabilities, weights, memory namespace and local filename |
| 2026-08-11 | J1B iPhone 17 Pro, iOS 26.5 simulator test | Pass, 9 tests, 0 skips | Preview/install/static activation, lease veto/release, fresh-store removal decision, cancellation cleanup, Chat/Map/session/journey continuity |
| 2026-08-11 | J1B generic iOS Simulator build | Pass | App, exact ZIP dependency and all local packages compile with Xcode 26.6 / Swift 6 |
| 2026-08-11 | Two consecutive J1B XcodeGen generations | Pass, identical SHA-256 `c575ab6e6c2e73a177fbb50043582ba19397c4c18344598070baa88f0a1e36e2` | Generated project includes the current Desktop compatibility fixture and final J1B sources |
| 2026-08-11 | J1B six-package regression | **Superseded — did not reproduce**; recorded as 83 tests passing | The CharacterRuntime 59 component contained the failing lease test; see the 2026-08-12 84-test row |
| 2026-08-11 | Backend and repository Python suites | Pass, 19 tests | Mock backend, Draft 2020-12 contracts, HTTPS-only provenance, dependency/private-payload policy and editable Chinese catalog |
| 2026-08-11 | J1B limits and recovery evidence | Pass | Real sparse archive 128 MiB exact/+1; production policy helper exact/+1 for 128 MiB file, 512 MiB expanded, 2,000 files and 20:1; pre/post-commit cancellation, four deletion fault phases and startup recovery |
| 2026-08-12 | Independent re-verification of the J1B candidate before hand-off acceptance | **Fail on first run, 1 failure in 59 tests** | `prepareActivation` marked a mutated installation unavailable but left every previously issued activation lease registered, so a detected-mutated handle stayed registered and `remove` would answer `inUse` forever. Fixed by revoking all leases for the installation on any failed tree revalidation, in both `prepareActivation` and pre-CAS `validateActivation` |
| 2026-08-12 | J1B CharacterRuntime public suite after the lease-revocation fix | Pass, 60 tests: 56 pass and 4 expected opt-in skips | Adds `testMutationDetectedAtPreCASValidationRevokesEveryLeaseAndAllowsRemoval`, which had no coverage before and asserts revocation plus recovered deletability |
| 2026-08-12 | J1B full private CharacterRuntime lane after the fix | Pass, 60 tests, 0 failures, 0 skips | Explicitly supplied 桃瀬ひより tree `6cba59…175c8` / 17 files and `AvatarSample_A` `2a0ccd…827f5`; payloads remain outside the repository |
| 2026-08-12 | J1B installer lane under Address Sanitizer after the fix | Pass, 33 tests with 2 expected private skips | Same deterministic corpus; still not coverage-guided fuzzing or device evidence |
| 2026-08-12 | J1B six-package regression after the fix | Pass, 84 tests in the private 0-skip lane | CompanionCore 12, CharacterRuntime 60, ChatFeature 3, MapFeature 1, OfflinePack 7, SyncClient 1 |
| 2026-08-12 | J1B generic iOS Simulator build and iPhone 17 Pro, iOS 26.5 test after the fix | Pass; build succeeded and 9 tests, 0 skips | Preview/install/static activation, lease veto/release, fresh-store removal decision, cancellation cleanup and Chat/Map/session/journey continuity |
| 2026-08-12 | Two consecutive XcodeGen generations after the fix | Pass, identical SHA-256 `c575ab6e6c2e73a177fbb50043582ba19397c4c18344598070baa88f0a1e36e2` | Matches the recorded J1B hash; the fix touches sources already in the generated targets |
| 2026-08-12 | Backend and repository Python suites and PRD/TDD traceability after the fix | Pass, 19 tests and 24 traced P0 requirements | `unittest` lanes, not `pytest`: the pinned `Backend/.venv` has `jsonschema` only |
| 2026-08-12 | `G2-J2A` live SSE defect found by running the App against the real mock | **Fail before fix** | The gateway read the stream with `AsyncSequence.lines`, which does not emit empty lines. Because a blank line is the SSE frame delimiter, both events concatenated into one invalid JSON payload and every turn failed with `malformedStream`. Unit tests over hand-written single frames passed; only the live lane caught it |
| 2026-08-12 | `G2-J2A` second defect: collapsed conversation area hid turn status | **Fail before fix** | Pending, stop and failure status were rendered inside a container collapsed to zero height while the transcript was empty, so the first turn's failure was invisible. Visibility now keys on transcript-or-turn-state, not transcript alone |
| 2026-08-12 | `G2-J2A` six-package regression | Pass, 103 tests, 0 failures, 0 skips in the private lane | CompanionCore 12, CharacterRuntime 60, ChatFeature 22, MapFeature 1, OfflinePack 7, SyncClient 1 |
| 2026-08-12 | `G2-J2A` mock-backend integration lane | Pass, 2 tests | Opt-in via `JOI_MOBILE_MOCK_BACKEND_URL`; proves real `/v1/chat/streams` framing, `acceptedInput` then `acceptedFinal`, and identity echo. Skipped in the hermetic public suite |
| 2026-08-12 | `G2-J2A` iPhone 17 Pro, iOS 26.5 simulator manual turn | Pass | Typed message sent, user line and companion reply each appended once, stage shrank to make room, composer cleared and reverted to the disabled voice control |
| 2026-08-12 | `G2-J2A` unavailable-backend behaviour on simulator | Pass | With the mock stopped, the turn showed 「无法连接到 Joi 的服务；对话没有变化。」 plus a retry hint; the prior transcript was preserved and the failed message was never appended |
| 2026-08-12 | `G2-J2A` app test target and Python suites | Pass, 9 app tests and 20 Python tests | Adds a catalog-drift guard proving no visible Chat literal bypasses the editable `zh-Hans` catalog |
| 2026-08-12 | `G2-J2A` build and two consecutive XcodeGen generations | Pass, identical SHA-256 `ae8be7eb0b394a4ea57e246e885e0b64233cb2c88bb2280ec2c9a003f9542e2b` | Hash changed from the J1B value because `project.yml` gained the loopback-only ATS entry and the ChatFeature test dependency |
| 2026-08-12 | Real provider behind the local proxy boundary | Pass | `Backend/proxy_server.py` streamed 20 frames for one turn — one `acceptedInput`, 18 cumulative `streamingDraft`, one `acceptedFinal` — and the App rendered a genuine Chinese answer on iPhone 17 Pro. The provider key was supplied only as a transient process environment variable |
| 2026-08-12 | Provider-opacity and key-leak tests | Pass, 11 proxy tests | No client-visible field contains the provider name, host, model or an `Authorization` fragment; stable codes only; the proxy exits without a key instead of faking success; a repository scan rejects any committed `sk-` key literal |
| 2026-08-12 | Catalog-drift guard was itself defective and was fixed | **Fail before fix** | The first version excluded backslashes from its literal regex, so it silently skipped every interpolated string — exactly the case it existed to normalise. After the fix it immediately caught a genuinely missing key (`%@ 正在输入：%@`), which was then added |
| 2026-08-12 | Full lane after the provider integration | Pass | 103 package tests in the private 0-skip lane, 9 app tests on iPhone 17 Pro / iOS 26.5, 15 repository and 16 backend Python tests, 24 traced P0 requirements |
| 2026-08-13 | DEC-024 motion contract: CharacterRuntime public suite | Pass, 67 tests with 4 expected opt-in skips | Six new cases: a VRM package with declared `.vrma` motions installs and its table reaches `contentAccess`; an undeclared `.vrma` in the tree is still refused; a motion naming an undeclared asset is refused; format is read from the file so a model renamed `.vrma` and a clip renamed `.vrm` are both refused; duplicate/malformed names and unknown motion keys are refused; a `static` package may not declare motions |
| 2026-08-13 | DEC-024 private 0-skip lane, including a real motion package | Pass, 68 tests, 0 failures, 0 skips | Adds `JOI_MOBILE_VRM_MOTION_PACKAGE_URL`: the real 20.9 MiB package built by the tool installs un-quarantined, activates, and every declared clip is readable and verified as genuine VRMA by parsing its glTF extensions |
| 2026-08-13 | DEC-024 contract schema and app suites | Pass, 21 Python tests and 13 app tests | Schema gains a bounded `motions` array with a `.vrma`-only path pattern; new fixture `character-package-vrm-motions.valid.json`; new Python case rejects a model path, an escaping path, an absolute path, a shouty name and a `duration_ms` key. App cases prove a repeated cue is still two events and that activation cues a greeting a motion-less package simply ignores |
| 2026-08-13 | DEC-024 default zero-vendor spec | Pass, build plus 13 app tests | `project.yml` still references no vendor runtime; the motion contract lives in CharacterRuntime and CompanionCore, and the stage wiring is confined to the `project.native.yml` `VRM/` source group |
| 2026-08-13 | VRM stage: activation greeting was dropped | **Fail before fix** | The log showed `vrm motion ignored: greet is not declared` one second before `vrm model loaded`. The cue is issued at activation but a 25 MiB model is not ready yet, so every greeting was lost. The coordinator now defers a cue that arrives before the model and plays it once loading completes |
| 2026-08-13 | VRM stage: hands are visibly deformed | **Open defect in the vendored renderer** | Every finger on both hands collapses into one tapering cone. Reproduced with no Joi code in the process: VRMMetalKit's own `VRMRender` static CLI on the plain bind pose, and its own `VRMVideoRenderer` on its own bundled `AvatarSample_A_1.0.vrm.glb` with its own `VRMA_01.vrma`. Not animation-related and not introduced by this slice; the 91-joint skin is far below the 256-matrix shader clamp, so the cause is unidentified |
| 2026-08-13 | VRM stage: hair silhouette after disabling synthetic colliders | Partial, measured | Turning off `augmentSpringBoneColliders` and declining to inject the CLI's default spring gravity narrows the hair span from ~332 px to ~325 px, about 2%. Real but small; it removes stray flying strands and is the authored-rig-faithful setting, but it does not by itself account for the difference from desktop Joi's idle |
| 2026-08-13 | VRM stage swallowed every tap meant for the chrome | **Fail before fix** | Tap-to-play-motion was a `UITapGestureRecognizer` on the Metal view. A UIKit recognizer there does not lose to SwiftUI chrome drawn above it, so taps on the composer and the mic button fired `vrm motion playing: happy` / `finger_gun` instead — typing was impossible with a VRM character active. Tap-to-play is now a SwiftUI `.onTapGesture` on the stage layer, routed through `AppModel.tapStage()`, so z-order decides. Re-verified: a composer tap now focuses the field and logs no motion |
| 2026-08-13 | DEC-025 VRM lip sync, real audio end to end | Pass, simulator | One turn on `iPhone 17 Pro`: real DeepSeek reply through the local proxy → `speech playing: 4.140000s of audio` from GPT-SoVITS in the character's Japanese voice → `vrm lip sync: mouth driven by played audio`. Across the 60-frame capture the mouth region swings from 938 to 1561 dark pixels; a mouth that never opened would be flat. The same turn also proves the chat-driven cue path, logging `vrm motion playing: happy` on the accepted reply |
| 2026-08-13 | DEC-025 default zero-vendor spec after the lip-sync and tap changes | Pass, build plus 14 app tests | 14th case: a tap on a character that declares no motions issues no cue at all, rather than a cue for a motion that does not exist |
| 2026-08-14 | Native build failed from Xcode while every command-line build passed | **Fail before fix** | `error: Sandbox: mkdir deny(1) file-write-create …/JoiMobile.build/DerivedSources` in the `Compile Cubism Metal libraries` phase. It wrote its `.air` intermediates to `$DERIVED_FILE_DIR`, which a *pre-build* phase runs before anything creates, so `mkdir -p` had to create that directory and script sandboxing denied it. Fixed by compiling `.metal` straight to `.metallib` — one translation unit per library, so the scratch directory bought nothing — leaving the declared output directory as the only one the phase creates |
| 2026-08-14 | Lip sync reported dead on both runtimes | **Two causes, one environmental and one real** | The immediate cause was environmental: GPT-SoVITS was not running, so `/v1/speech` had nothing to return, the turn stayed correctly silent and both mouths correctly stayed shut. The real defect behind it is that the app never configured `AVAudioSession`, so it ran on the default `soloAmbient` category — silenced by the ring/silent switch, which on a device is a mute character and a still mouth with no diagnosis. Now claims `.playback`/`.spokenAudio` lazily before the first line |
| 2026-08-14 | Lip sync verified on both runtimes after the fix | Pass, real audio | Live2D 桃瀬ひより: `speech playing: 4.140000s` → `speech finished: peak mouth amplitude 0.732172`, and the mouth-open region swings from 2 to 1756 pixels across the line. VRM `AvatarSample_A`: `speech playing: 7.900000s` → `vrm lip sync: mouth driven by played audio` → peak `0.711734`, mouth region 937 to 1279 pixels. Both driven by one real DeepSeek turn and the character's own Japanese voice |
| 2026-08-14 | Why that defect survived every earlier check | **Gap in the harness, now closed** | `Tools/run_native.sh` built into `/tmp/JoiMobileNative`, and script sandboxing permits writes anywhere under `/tmp`. Every build in this repository therefore exercised weaker rules than the IDE. Its default derived-data path is now under Xcode's own `DerivedData` root, still outside the repository, so the script sees the rules Xcode applies. Verified failing before the fix and passing after, from that root, with all three metallibs present in the bundle |
| 2026-08-13 | DEC-026 conformance corpus published and run by the shipping iOS implementation | Pass, 100 vectors across 4 files | `content-id.json` 11, `strict-json.json` 37, `manifest-validation.json` 35, `sse-framing.json` 17. Four new CharacterRuntime cases and two new ChatFeature cases execute them. `content-id.json` is generated from the written rule by `Tools/make_conformance_corpus.py`, not recorded from the implementation, so agreement is evidence rather than tautology |
| 2026-08-13 | DEC-026 finding 1: a raw `NSError` escaped the stable-code boundary | **Fail before fix** | `StrictJSON.object` accepted a well-formed top-level scalar, which `JSONSerialization` then refused as a fragment; that Foundation error propagated out of a boundary whose every caller expects a `CharacterPackageImportFailure`. A manifest that is a bare JSON string now answers `invalidManifest` like any other malformed document. Found by the `top-level-scalar` vector on its first run |
| 2026-08-13 | DEC-026 finding 2: content identity is computed over filesystem bytes, not package bytes | **Open defect, not fixed** | Darwin returns `café.txt` decomposed for a file written composed, so iOS hashes NFD where a port on ext4 hashes NFC and the same package installs under two identities. No existing test could see it: Swift's `String` equality is canonical, so the installer's `normalized == path` guard compares NFC against NFD and returns true. The `decomposable-path` vector is carried as non-normative until a decision settles the migration. Every ASCII package, which is every fixture here, is unaffected |
| 2026-08-13 | Six-package Swift regression after the `StrictJSON` and DEC-028 fixes | Pass, 120 tests with 7 expected opt-in skips and 0 failures | CompanionCore 12, CharacterRuntime 75, ChatFeature 24, MapFeature 1, OfflinePack 7, SyncClient 1. The five CharacterRuntime skips are the private Live2D/VRM fixture and motion-package gates; the two ChatFeature skips are the mock-backend integration lane |
| 2026-08-13 | Repository Python lane with the corpus guards | Pass, 32 tests | Eleven new cases: corpus shape, generator freshness, unique case ids, a guard that reads the stable code set out of the Swift declaration and refuses any vector naming a code that does not exist, and the DEC-028 cross-artifact guard below. `jsonschema` is not installed on this workstation, so the lane was run from a throwaway venv: without it `test_contracts.py` does not import at all and only 23 of the 32 cases run, which is worth knowing before anyone reads a green local run as a full one |
| 2026-08-13 | DEC-026 finding 3: the declared asset list was capped at 300, not the contract's 2000 | **Fail before fix** | The forbidden-content walk's generic array guard also governed `assets`, so a package declaring 301 assets was schema-valid, inside every stated limit and refused as `invalidManifest`. Probed directly before the fix: 300 admitted, 301 refused. An ordinary Live2D character with a few hundred motion, expression and texture files was silently unimportable |
| 2026-08-13 | DEC-028 fix in both twins, with the byte bound that would otherwise have bitten first | Pass on iOS, 7 CharacterRuntime conformance cases; **Kotlin twin written but not compiled** | The declared asset list alone is bounded by `maximumFileCount`; the exemption is keyed on canonical envelope, `depth == 1` and the exact path `["assets"]`, and a test asserts every other array — including one nested inside an asset entry, and JSON carried as package content — still stops at 300. `maximumManifestBytes` is raised to 1 MiB and named, because 2000 assets do not fit in 256 KiB and the byte bound would have capped the count at a number the contract never states while reporting `unsafeArchive`. Re-measured through `decodeAndAdapt` after the fix: 301 admitted where it was refused, 2000 admitted at a 28-character Live2D path length, 2001 refused as `invalidManifest`, 2000 at the schema's 512-character path maximum still refused as `unsafeArchive` for size — the residual corner, recorded in DEC-028 and asserted in the test rather than left open. A cross-artifact Python case reads the schema, the Swift limits and the Kotlin limits together, so the three-artifact drift that caused this cannot recur silently |
| 2026-08-14 | Android portable Kotlin core, first compile | Pass, 11 tests, 0 failures, no compile errors | `./gradlew test` on Gradle 8.14 / Kotlin 2.1.21 / JDK 22. CrossPlatformConformanceTest 9, SseFramingConformanceTest 2, over the same 100 vectors the Swift suite runs. 13m 29s cold, dominated by dependency download; 1–4s warm |
| 2026-08-14 | DEC-026 finding 2 is now measured on both sides, not predicted | **Divergence demonstrated** | The Kotlin twin's `content identity of a materialised tree matches every vector` passes on **every** case including `decomposable-path`, because it normalizes the path to NFC before hashing. The Swift twin must skip that case. Two implementations sharing no code, run against one file, disagreeing exactly where the rule said they would — the iOS side is the one that does not conform |
| 2026-08-14 | Gradle distribution pinned by official checksum after a silently truncated mirror fetch | **Caught before use** | A mirror served 67,182,511 of 137,391,539 bytes and `curl` exited 0. The official SHA-256 rejected it immediately; the resumed download then matched `61ad310d…de3caa` exactly. The generated wrapper carries that `distributionSha256Sum`, so the check survives any later mirror swap |
| 2026-08-14 | The `zh-Hans` catalog had lost 147 of its 159 keys in the worktree | **Fail before repair** | Four Python cases failed: the shell-copy completeness check, the Character Library copy check and the drift guard that reads every Chinese literal out of the Chat surface. `HEAD` carried 159 keys and the worktree carried 14, of which 2 were new. Repaired as a lossless union — `HEAD` as the base, worktree entries layered on top, so edits to the 12 surviving entries stand and the 147 dropped ones return — giving 161. The truncated file is kept at `scratchpad/Localizable.truncated.backup.json`. This was not part of the conformance or Android work and the catalog has another writer; if the prune was intentional it needs redoing together with the view changes that still reference the dropped keys |
| 2026-08-14 | Full three-language lane | Pass, 152 tests and 0 failures | Kotlin 11 (`./gradlew test --rerun-tasks`, ~1s), Swift 120 across six packages with 7 expected opt-in skips, Python 32, plus 24 traced P0 requirements. The 100 conformance vectors are executed by two of the three |
| 2026-08-14 | Android `:app` module, Compose two-surface shell, on the emulator | Pass | Gradle 9.5.0 / AGP 9.3.1 / Kotlin 2.4.10 / compileSdk 37. Hand-written AVD (`avdmanager` is not installed): Pixel 8, API 37, arm64-v8a, Google APIs. Cold boot 30 s, install and launch with an empty crash buffer. Chat draws the stage and composer placeholders, Map draws the cached-walk card, and both read one `CompanionSessionStore` snapshot |
| 2026-08-14 | Surface switching is non-destructive, verified on the running app | Pass, 0 differing pixels | Chat → Map → Chat: the two Chat captures share SHA-256 `71d7867f…`, and 2,473,200 pixels below the status bar differ in none. The rule `CompanionSessionStoreTest` asserts is therefore also observable at runtime rather than only in a unit test |
| 2026-08-14 | DEC-026 closed: content identity is now over NFC bytes on both platforms | Pass, `decomposable-path` promoted to normative | `contentID` hashes and orders paths by NFC UTF-8 bytes and keeps the on-disk form only to open the file. Zero non-normative vectors remain. Migration surface was limited to packages with decomposable non-ASCII filenames, of which this repository has none and no release has any |
| 2026-08-15 | DEC-026 layer 3a: the restricted ZIP profile is now 43 executable vectors | Pass, 40 normative and 3 recorded findings | `Contracts/conformance/zip-profile.json`, generated by `Tools/make_zip_corpus.py` as complete archives built field by field rather than by a ZIP library. 37 of 40 agreed with the written policy on the first run; two disagreements were defects in the vectors and one was a defect in the implementation |
| 2026-08-15 | DEC-029: every archive containing a folder was refused | **Fail before fix** | `validateAttributes` refused any Unix entry with an execute bit, including directories, where that bit is the search bit every archiver writes as `0o755`. A Live2D package is a folder of textures and motions, so this refused essentially every real Live2D ZIP. Execute bits are still refused on files |
| 2026-08-15 | DEC-029: no mainstream archiver produces an importable archive | **Open, recorded as three non-normative vectors** | Measured over one folder archived four ways: `zip -r` writes extra field `0x7875`, `ditto` writes `0x5855`, both outside the allowlist; Python `zipfile` writes an external attribute with no file-type nibble. The allowlist question is a Trust & Safety call, not an implementation one. Invisible until now because the J1B corpus was built by the test code, which chose fields that satisfied the parser |

The visible Chat composer, push-to-talk button, character runtime surface, Map card, navigation, source button and profile control are **placeholders**. The first slice proves composition/state/contracts and PoC seams; it does not provide complete Chat, Map, account, sync or production-backend journeys.

## PoC evidence

### Native Live2D

Asset-free scaffold complete. `JMLive2DModel3Inspector` checks model metadata and declared multi-texture, Motion, Expression, Physics, Pose, EyeBlink and LipSync references. `JMLive2DNativeAdapter` isolates a future Cubism Native/Metal implementation behind an actor boundary and tests generation invalidation, stale-load suppression, fallback and exactly-once release. Six Live2D tests pass, including 50 load/release cycles.

`G2-J1A` additionally admitted the private 桃瀬ひより fixture by its 17-file tree fingerprint and confirmed two textures, ten motions, Physics, Pose, EyeBlink and LipSync; Expression is correctly reported as undeclared. The asset was not copied, bundled, logged, uploaded or committed.

This does **not** prove Cubism SDK integration, actual Metal rendering, licensed model compatibility, frame rate, GPU release, heat or the Live2D release license. Those remain G4/G5 conditions.

### Native VRM

Asset-free scaffold complete. `VRMNativeMetadataInspector` distinguishes JSON/GLB glTF, VRM 0.x, VRM 1.0 and VRMA metadata and reports Humanoid, MToon, Expressions, LookAt, Constraints, Spring Bone, animation and lip-sync expectations. `VRMNativeAdapter` keeps RealityKit/Metal and any future VRMKit usage behind an owned internal bridge, with generation, cancellation, required-core fallback and exactly-once release tests. Eight VRM tests pass using self-authored metadata fixtures.

`G2-J1A` additionally admitted the private `AvatarSample_A` fixture by exact SHA-256, confirmed VRM 0.x plus its declared Humanoid/MToon/expression/look-at/spring-bone/lip-sync metadata, and did not claim VRM 1.0 or VRMA coverage. The asset was not copied, bundled, logged, uploaded or committed.

This does **not** prove real RealityKit/Metal loading, MToon fidelity, model breadth, frame rate, GPU release, heat or device compatibility. Rights-cleared fixture and G4/G5 evidence remain required.

#### VRM idle and triggered motion (2026-08-13, simulator)

A `.vrm` file carries no animation, so DEC-024 added a `motions` table to the package contract. Evidence, all on `iPhone 17 Pro` simulator with the `project.native.yml` variant:

- `Tools/make_character_package.py --motion idle=…:loop --motion greet=… …` built a 20.9 MiB package holding `AvatarSample_A` plus five real `.vrma` clips. It previewed, installed un-quarantined, activated, and the stage drew it.
- The stage log reports all five clips bound to their declared names with the durations the clip files actually carry — `idle 6.000s / greet 7.267s / happy 11.684s / finger_gun 9.600s / dance 9.317s` — matching desktop Joi's `duration_ms` values to within 4 ms, which is why DEC-024 does not copy that field.
- Idle plays looping and the character holds a natural arms-down stance rather than a bind pose. 36 consecutive simulator screenshots (~169 ms apart, ~6 s wall clock) show 1.3–2.5 % of the character-region pixels changing between adjacent frames and 2.5 % between first and last; a frozen frame would read ~0.
- A tap triggers a declared non-idle motion: the log records `vrm motion playing: greet` and the frame series shows 2.0–2.5 % inter-frame change through the clip, after which playback returns to idle.
- Activation issues a `greet` cue ~1 s before a 25 MiB model finishes loading. The first wiring dropped it; the stage now defers such a cue and plays it once the model is ready (`vrm motion deferred` → `vrm motion playing` in the log).

Lip sync (DEC-025) rides the same per-frame tick: after the clip's own morph weights, the stage writes the `aa` viseme from `SpeechPlayer.currentAmplitude`, the loudness of the audio actually playing. One real turn drove a DeepSeek reply into a Japanese GPT-SoVITS line and the log recorded `speech playing: 4.140000s of audio` followed by `vrm lip sync: mouth driven by played audio`; the mouth region varies by two thirds of its dark-pixel count across the capture. Only one viseme is driven, deliberately — amplitude carries no phoneme information, and DEC-021's rule is that this product stays still rather than mimes.

**Open defect, not caused by this work:** every finger on both hands collapses into a single tapering cone. It reproduces in VRMMetalKit's own `VRMRender` static CLI on the plain bind pose — no animation, no spring bones, no Joi code in the process — and equally on the SDK's own bundled model and clip. The skin has 91 joints against a 256-matrix shader clamp, so the obvious explanation is ruled out and the cause is unidentified. See the DEC-023 correction. Spring-bone behaviour on a real device, VRMA breadth beyond these five clips, frame rate and thermals remain G4 work.

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

### G2-J1B Scheme decisions

| Director | Decision | Conditions / owner |
|---|---|---|
| Product Design | Approved with conditions | Chinese choose/preview/install/activate/remove flow; quarantine has no activation action. Additional languages and full accessibility remain deferred. |
| Technical | Approved with conditions | Exact manifest discriminator, streaming ZIP policy, installer lease and session CAS frozen; native renderer contracts remain G4. |
| AI & Companion | Approved with conditions | Package work cannot write memory/journey/permissions; successful CAS preserves thread/session/events. Production speech cancellation remains later integration. |
| Art & Character | Approved with conditions | Private fixtures are import/metadata evidence only; no native claim. Rights-cleared device fixtures remain G4/G5. |
| Content & Trust | Approved with conditions | Editable `zh-Hans` recovery/rights copy and HTTPS-only authored source; rights confirmation workflow remains G5. |
| Trust & Safety | Approved with conditions | No-follow staging, strict graph/content policy, quarantine, activation lease and journaled removal are mandatory; veto retained. |
| Quality & Release | Approved with conditions | Exact dependency/notice, deterministic corpus, fault recovery, private 0-skip lane, simulator and bundle evidence required; G4/G5/G6 remain open. |

Independent Closeout found no `Rework` or `Blocked` decision for this bounded slice. `G2-J1A` is closed with conditions. This does not close complete G2, `JM-P0-015`, `JM-P0-017`, G4 or G5.

### G2-J1B Closeout rework closure candidate

The first independent J1B Closeout returned Technical, Trust & Safety and Quality `Rework`: App-authorized active removal was bypassable, the handle tuple was not enforced, removal could overstate physical deletion, Desktop compatibility used an invented reduced shape, ZIP preflight/material hashes loaded large files, canonical JSON could carry forbidden state, and required fault/boundary/deflate/fuzz evidence was missing.

The candidate now closes those findings with installer-owned activation leases; pre-CAS revalidation and exact release; fresh `CompanionSessionStore` decisions; journaled, retryable, verified deletion; current Desktop normalized-shape adaptation; bounded `pread` ZIP metadata; incremental file hashing; renderer-graph content closure; HTTPS-only authored provenance; recursive JSON state/secret rejection; valid deflate, deterministic mutation, exact/+1 policy, crash/retry and App cancellation tests. The independent Director re-review is still required before this section may state that `G2-J1B` is closed.

The 2026-08-12 hand-off re-verification found the lease part of that closure incomplete. Revalidation correctly detected a mutated asset tree and marked the catalog entry unavailable, but it revoked no activation lease, so a handle whose content was already proven mutated stayed installer-registered and `remove` would answer `inUse` with no reachable release path — a permanently undeletable compromised installation, against DEC-013 and DEC-014. Any failed tree revalidation now revokes every lease for that installation, in `prepareActivation` and in pre-CAS `validateActivation`; a handle that is merely stale, rather than backed by a mutated tree, still revokes only itself. Because the App-side pre-CAS path had no test, one was added. This is a correctness repair inside an already-declared contract, not a new capability, so it does not narrow the remaining re-review: Technical still owns confirming lease and CAS behavior end to end.

Open conditions are unchanged: native Cubism/RealityKit/Metal rendering and device performance remain G4; private model/Live2D redistribution and dependency/data rights remain G5; release/privacy/signing remain G6. Additional languages and full accessibility validation remain explicitly deferred.
