# Joi Mobile Decisions

## DEC-001 — Two primary surfaces

- **Status:** Accepted
- **Date:** 2026-08-11
- **Decision:** Joi Mobile has exactly two primary surfaces, Chat and Map. Character library, account, downloads, memory, and settings are secondary destinations.
- **Reason:** Preserve a clear companion identity while retaining a focused travel mode instead of reproducing the legacy five-tab structure.

## DEC-002 — Shared companion core, separate travel context

- **Status:** Accepted
- **Date:** 2026-08-11
- **Decision:** Chat and Map share the current character and conversation thread through `CompanionSessionStore`. Exact location, route progress, and visual observations belong to `JourneyContextStore` and enter Chat or long-term memory only through explicit, inspectable attachment/consent.
- **Reason:** Avoid split identity while preventing location from silently contaminating persistent memory.

## DEC-003 — Native character runtimes behind one protocol

- **Status:** Accepted with release gates
- **Date:** 2026-08-11
- **Decision:** Live2D and VRM/VRMA render natively behind `CharacterRenderer`; Unity, WKWebView, and Three.js are excluded. Unsupported packages fall back to a static presentation.
- **Conditions:** Live2D Expandable Application license/approval, asset rights, and real-device compatibility/performance evidence remain required before public release.

## DEC-004 — Offline navigation boundary

- **Status:** Accepted
- **Date:** 2026-08-11
- **Decision:** A downloaded travel pack may show its map corridor, advance on a cached cultural walking route, play cached narration, detect departure, and guide the user back. Arbitrary offline route recomputation is not a product promise.
- **Reason:** This boundary is useful and testable without disguising an online routing service as an offline engine.

## DEC-005 — Contract-compatible, source-independent repository

- **Status:** Accepted
- **Date:** 2026-08-11
- **Decision:** Joi Mobile is a new repository. Desktop Joi's `.joi-character` and companion event semantics are ported as versioned contracts/adapters; legacy source trees remain read-only.
- **Reason:** Preserve interoperability without inheriting current dirty worktrees, desktop transport assumptions, or legacy Map state ownership.

## DEC-006 — Deterministic generated Xcode project

- **Status:** Accepted
- **Date:** 2026-08-11
- **Decision:** Commit `project.yml` and a pinned XcodeGen requirement; ignore the generated `.xcodeproj`.
- **Reason:** Keep project structure reviewable and reproducible while avoiding hand-edited project file drift.

## DEC-007 — Chinese-first copy; languages and accessibility staged later

- **Status:** Accepted
- **Date:** 2026-08-11
- **Decision:** The current implementation accepts editable `zh-Hans` product copy only. `zh-Hant`, English, Japanese and Korean content, plus full VoiceOver, Dynamic Type, Reduce Motion and long-text validation, are deferred milestones. Separate display/content/voice locale contracts, semantic labels, system text styles and motion hooks remain so later work does not require an architecture rewrite.
- **Reason:** User explicitly narrowed the current delivery to core architecture and PoCs; language breadth and accessibility quality require focused content and device review instead of placeholder claims.

## DEC-008 — Private character fixtures enter through a non-distribution gate

- **Status:** Accepted with G4/G5 gates
- **Date:** 2026-08-11
- **Decision:** 桃瀬ひより and `AvatarSample_A` may be used as explicitly selected, read-only local compatibility fixtures for `G2-J1A`. Only non-sensitive receipt metadata and expected hashes may be committed; model payloads, absolute local paths and vendor runtimes may not enter Git, the App bundle, logs or uploads.
- **Reason:** Real model metadata strengthens preflight evidence while preserving the desktop Joi worktree and avoiding an unsupported redistribution or native-runtime claim.
- **Conditions:** This slice proves preflight, Chinese preview and static fallback only. Live2D SDK/character terms, durable rights receipts, native bridges, VRM 1.0/VRMA breadth and real-device behavior remain G4/G5 work.

## DEC-009 — Validated character handles are installer-issued

- **Status:** Accepted
- **Date:** 2026-08-11
- **Decision:** The `ValidatedCharacterPackageHandle` initializer is exposed only through the `CharacterPackageInstaller` SPI. App and renderer consumers receive handles from the admission/installer boundary instead of constructing them from arbitrary string root identifiers.
- **Reason:** Prevent ordinary consumers from accidentally bypassing path, size and hash checks. The SPI is an API-discipline boundary, not a substitute for isolated staging, immutable storage and activation-time revalidation.

## DEC-010 — Same schema label, explicit desktop/mobile manifest discriminator

- **Status:** Accepted
- **Date:** 2026-08-11
- **Decision:** Desktop Joi and Joi Mobile currently use the same `joi.character.v1` label for incompatible envelopes. Import first classifies exact, non-overlapping top-level shapes; a mobile canonical manifest requires its canonical field family, while a desktop legacy manifest requires `id`, `identity.name` and `appearance`. A document matching both or neither is rejected before decoding. Legacy data is converted through a versioned adapter and never by same-key heuristics.
- **Identity rule:** The adapter computes a domain-separated digest over canonical, allowlisted legacy bytes, derives `packageID = legacy.<digest>`, then independently computes installed `contentID` over the final sealed tree. This avoids a manifest/content hash cycle and makes identical reimports deterministic.
- **Compatibility receipt:** Only a strict, size-bounded `LegacyManifestReceiptV1` may retain explicitly allowlisted legacy provenance/export fields. It is catalog-only, never runtime content, memory, analytics, logs or sync. User state, secrets, model weights, capability grants and unknown extensions are rejected or dropped by rule. Legacy `zh` maps explicitly to `zh-Hans` with a warning; this is not a general locale fallback.
- **Reason:** Preserve desktop import compatibility without silently interpreting two incompatible wire formats as one or importing desktop state into mobile runtime state.

## DEC-011 — Restricted ZIP profile with pinned ZIPFoundation decompression

- **Status:** Accepted with J1B closeout conditions
- **Date:** 2026-08-11
- **Decision:** CharacterRuntime pins ZIPFoundation `0.9.20` at revision `22787ffb59de99e5dc1fbfe80b19c97a904ad48d` as its sole ZIP decompressor/CRC implementation. Joi Mobile never calls high-level path extraction. An owned, read-only raw ZIP preflight must approve names, flags, methods, Unix type/mode, extra fields, local/central agreement, entry ranges and limits before any staging output is opened.
- **Restricted profile:** ZIP64, multidisk, encryption, data descriptors, unsupported compression, special/link/executable entries, overlapping ranges and unknown/link-bearing extra fields are rejected. A safe but unsupported profile returns `unsupportedArchiveProfile`, not `corruptArchive`.
- **Conditions:** Exact revision resolution and MIT notice, malicious corpus, cancellation at every phase, fuzz seeds, post-write regular/single-link checks, recovery and mutation tests must pass before `.joi-character` or Live2D ZIP support closes J1B.
- **Reason:** Reuse a focused decompressor while keeping security decisions, paths and filesystem writes under Joi-owned policy.

## DEC-012 — Character selection has one CAS owner

- **Status:** Accepted
- **Date:** 2026-08-11
- **Decision:** `CompanionSessionStore` owns the active `CharacterSelection`. Activation is a compare-and-swap from the selection observed before renderer preparation to an installer-validated selection. App views derive character identity from this snapshot and do not keep a second mutable current-character field.
- **Reason:** A late renderer callback, cancellation or surface switch must not overwrite a newer selection or split Chat and Map identity; thread, session and accepted events survive a successful character switch.

## DEC-013 — Activation is an installer-owned lease

- **Status:** Accepted
- **Date:** 2026-08-11
- **Decision:** `prepareActivation` registers the installation, content, validation generation and root-capability tuple. The App must validate that lease after renderer preparation and immediately before the `CompanionSessionStore` CAS. Failure/cancellation releases the new renderer generation and lease; a successful switch releases the previous resource only after the CAS. Installer removal returns `inUse` while any matching lease remains.
- **Revocation rule:** A failed tree revalidation revokes *every* lease on that installation, not only the calling handle, and marks the catalog entry unavailable. A merely stale handle — one whose tree still verifies — revokes only itself. Rationale: `inUse` is only a safe answer while some lease could still become valid. Once content is proven mutated, no outstanding lease can ever validate, so keeping one alive would make a compromised installation permanently undeletable instead of protecting a live renderer.
- **Reason:** A UI-only current-character check cannot prevent direct or racing deletion of files a renderer may still use. The store remains selection truth while the installer remains asset-lifetime truth.

## DEC-014 — Character deletion reports durable truth

- **Status:** Accepted
- **Date:** 2026-08-11
- **Decision:** Last-reference removal writes and fsyncs a stable recovery journal before atomically moving the verified content root to Trash, deleting/fsyncing catalog state and verifying physical absence. Any interrupted or failed phase returns `recoveryRequired` with a stable recovery key and can be resumed by the same removal request or startup recovery; it cannot report success while bytes remain in an untracked state.
- **Reason:** Catalog disappearance alone is not evidence that local character assets were deleted, and silent filesystem failures make user-facing deletion claims untrustworthy.

## DEC-015 — The transcript is server-accepted, not locally optimistic

- **Status:** Accepted
- **Date:** 2026-08-12
- **Decision:** A user message becomes a transcript line only when the backend returns its `acceptedInput` event. The App does not append it locally at send time. While a turn is in flight the text is shown as explicitly unconfirmed pending content, and `CompanionSessionStore` remains the sole owner of accepted transcript ordering, refusing duplicate `eventID`s and foreign `threadID`s.
- **Reason:** Local optimism plus a server echo is the classic double-append bug, and de-duplicating two differently-keyed copies of the same line is guesswork. One source of truth keyed by `eventID` makes "appended exactly once" checkable instead of hopeful. The cost is that a sent message is visibly pending until accepted; that is honest rather than hidden.
- **Consequence:** A backend that never echoes accepted input would leave the user's line pending forever. `/v1/chat/streams` must keep emitting it, and that expectation is now covered by the mock-backend integration lane.

## DEC-016 — Owned SSE framing; loopback is the only plain-HTTP exception

- **Status:** Accepted
- **Date:** 2026-08-12
- **Decision:** CharacterRuntime-style ownership applies to transport too: Joi Mobile parses server-sent-event framing with its own incremental `SSEFrameParser` rather than any line-splitting convenience API, and `ChatBackendEndpoint` rejects every non-loopback plain-HTTP host. `NSAllowsLocalNetworking` is enabled with `NSAllowsArbitraryLoads` false so the local mock can serve development traffic without weakening production HTTPS.
- **Reason:** `AsyncSequence.lines` does not emit empty lines, and a blank line is exactly the SSE frame delimiter, so it merges consecutive events into one invalid payload. This was found only by running the app against the real mock; unit tests over hand-written single frames passed while the live stream failed. Framing is a correctness boundary and must be owned and tested directly.
- **Conditions:** Token-level streaming, `Last-Event-ID` resume and any retry policy remain unproven until a backend actually chunks events; the draft projection path is implemented and tested but carries no production evidence.

## DEC-017 — The provider key lives only in the proxy process environment

- **Status:** Accepted
- **Date:** 2026-08-12
- **Decision:** `Backend/proxy_server.py` is the only component that may hold a provider credential, and it reads it exclusively from `DEEPSEEK_API_KEY` in its own process environment. The key is never written to a repository file, a build setting, an Xcode scheme, the App bundle, a log line or an SSE payload. The proxy exits rather than starting without a key, so a missing credential can never degrade into a silently faked answer. `mock_server.py` remains a separate deterministic contract mock with no network access, so the test lanes stay hermetic.
- **Provider opacity:** The selected provider and model (`deepseek-v4-flash`) are server-side facts. Client-visible frames carry only `joi.companion-event.v1` fields and the stable codes `upstream_unavailable`, `upstream_rejected` and `upstream_malformed`; an unrecognised code degrades to honest copy rather than raw upstream text. A test asserts no client-visible field contains the provider name, host, model or an `Authorization` fragment, and a repository test rejects any committed `sk-` key literal.
- **Reason:** `JM-P0-004` forbids a provider secret anywhere in the app, packages, repository, fixtures or logs, and provider independence is a product requirement rather than an implementation detail. Keeping the key in one process and the provider name out of the wire means swapping providers is a backend change with no client release.
- **Conditions:** This is a local development proxy on loopback. A public deployment needs the official HTTPS proxy with real authentication, rate limiting, abuse controls, retention decisions and cost controls; none of that is in scope here, and no cloud resource has been created.

## DEC-018 — Joi Mobile is a Live2D "Expandable Application", so the small-business exemption does not apply

- **Status:** Accepted as a constraint; external approval outstanding
- **Date:** 2026-08-12
- **Finding:** Live2D defines an Expandable Application as a derivative work that uses and generates an indefinite number of models by adding or combining files or data, giving avatars as the example. `JM-P0-015` is exactly that: users import arbitrary `.joi-character`, `.vrm` and Live2D packages. Joi Mobile is therefore an Expandable Application by definition, not by choice of wording.
- **Consequence:** Live2D's ordinary exemption for individuals and small-scale businesses **explicitly excludes** Expandable Applications. The familiar "free for small developers" path is unavailable to this product. Every Expandable Application requires Live2D Inc.'s review and a special Publication License Agreement **before release**, regardless of publisher size, and the published conditions include a valid revenue model — free applications typically do not qualify — plus sales reporting, revenue-share fees, display of the Expandable Application logo and a Showcase listing.
- **Product implication:** A monetisation model is a precondition of Live2D approval, not a later growth decision. This interacts with the "local useful by default, no account required" principle: the product may remain usable without an account, but revenue must exist somewhere before Live2D can approve Live2D support.
- **Fallback:** VRM is an open standard with no equivalent per-application approval gate. Because DEC-003 keeps both runtimes behind one `CharacterRenderer` boundary, shipping VRM-first with Live2D support gated behind approval is a viable path that does not require an architecture change. Static fallback remains supported in all cases.
- **Not public:** Fee amounts, revenue-share percentages and review timelines are not published and must be obtained from Live2D directly via the Expandable Application request form. Do not plan against assumed numbers.
- **Authority:** No vendor has been contacted and no licence has been applied for. That step needs explicit user action and is out of scope for implementation work.

## DEC-019 — Live2D is an opt-in build variant, not a repository dependency

- **Status:** Accepted
- **Date:** 2026-08-12
- **Decision:** The Cubism SDK is vendored by `Tools/setup_live2d.sh` into an untracked `Vendor/Live2D/`, and admission happens only through `project.live2d.yml`, which `include:`s the default `project.yml` and adds the Framework sources, the Metal renderer, the Core XCFramework and the Joi bridge. `project.yml` stays free of every Live2D reference, so a clone without the SDK still generates, builds, tests and ships the static fallback.
- **Boundary preserved:** The bridge lives in the App target, not in CharacterRuntime. The J1B rule that CharacterRuntime admits exactly one pinned dependency is therefore unchanged, and its 60 tests keep running with no vendor runtime. `CharacterRenderer` remains the experience boundary.
- **Build facts that are not obvious:** Cubism's Metal renderer is written for manual reference counting and sends `-retain`/`-release`/`-autorelease` explicitly, so those sources are compiled with `-fno-objc-arc` while the Joi bridge keeps ARC. The Metal renderer is selected by `CSM_TARGET_IPHONE_ES2` despite the name. Shader libraries are platform-specific and are compiled per build into a `FrameworkMetallibs` bundle subdirectory, which is where `CubismShader_Metal` looks them up by name; the repository's script sandboxing stays enabled, so that phase declares every file it reads.
- **A sandboxed phase may create only its declared output directory** (found 2026-08-14): the phase also has to avoid writing anywhere else, including `$DERIVED_FILE_DIR` — it is a *pre-build* phase, so that directory does not exist yet and creating it is denied. Verifying this requires building under Xcode's `DerivedData` root: script sandboxing permits writes anywhere under `/tmp`, so a `-derivedDataPath /tmp/…` build silently passes rules the IDE enforces, and the failure appears only when a human presses Run. `Tools/run_native.sh` therefore builds where Xcode builds.
- **Reason:** A non-redistributable, licence-gated runtime must not become a precondition for building or testing the product. Making it an explicit build variant keeps the static-fallback promise of DEC-003 honest and testable rather than aspirational.
- **Conditions:** Compiling and linking is proven; rendering is not. The extended blend-mode shader matrix (about 470 variants) is not generated, so a model requiring one must fall back rather than render an incorrect blend.

## DEC-020 — Renderers reach content through an installer-issued access value

- **Status:** Accepted
- **Date:** 2026-08-12
- **Decision:** `CharacterPackageInstaller.contentAccess(for:)` issues a `CharacterContentAccess` carrying the sealed content root, the manifest-declared entry path and the renderer kind. It revalidates the lease and the tree first, exactly as `validateActivation` does, and its initializer is restricted to the installer SPI. The App publishes it only after a successful `CompanionSessionStore` CAS and clears it when the installation is removed.
- **Why a root is handed out at all:** the earlier intent was that asset roots are never exposed. A renderer has to read real files, so that intent was unachievable as written. What the boundary actually buys is preserved: the value cannot be constructed by a consumer, it is refused for a stale, removed, mutated or quarantined installation, and the entry file comes from the verified manifest rather than a caller's guess.
- **Consequence found while wiring this:** a bare Live2D `.zip` or raw `.vrm` installs but stays quarantined with `rightsUnverified`, so it can never be activated and therefore never rendered. The render link is reachable only for a rights-cleared canonical package. That is the J1B rule working as designed, not a defect, and it means "import a loose model and see it on stage" is blocked on the G5 rights-confirmation workflow rather than on renderer code.
- **Development consequence:** until that workflow exists, the native stage falls back to an explicitly supplied local fixture, which is a development affordance and is not a product path.

## DEC-021 — The spoken language is separate from the displayed language

- **Status:** Accepted
- **Date:** 2026-08-12
- **Decision:** Joi Mobile displays Simplified Chinese and speaks Japanese with the character's own voice. `CompanionEventV1` already separated `displayText` from `voiceLine`, so the Chinese reply travels in `displayText` and the Japanese spoken line in `voiceLine`. The proxy asks the model for both halves in one turn, separated by a delimiter, rather than making a second translation call: one round trip keeps the two consistent and the audio close behind the text. Drafts stream only the displayed half, so the spoken line never appears as visible text.
- **Silence rule, carried from desktop Joi:** `fallback_to_system: false`. If speech synthesis or playback fails, the turn stays silent and keeps its text. No system voice, and no other voice, may speak as the character. A model that ignores the output format yields no `voiceLine`, which is silence rather than Chinese text read by a Japanese voice.
- **Lip sync is audio-only:** mouth opening is computed from the amplitude of the audio actually playing, so silence closes the mouth with no separate bookkeeping. Driving a mouth from text timing would animate speech that is not being spoken; this product stays still instead of miming.
- **Reason:** The character's voice is part of its identity, and the audience reads Chinese. Treating display and voice as one string would have forced a choice between the two.

## DEC-022 — Voice identity is read from the character package, never copied

- **Status:** Accepted
- **Date:** 2026-08-12
- **Decision:** The proxy loads the voice at run time from a character package manifest named by `JOI_VOICE_PROFILE`, reading `localizations.<lang>.voice`: a per-emotion map of reference clip, transcript and speed. Nothing about the voice is committed to this repository.
- **Pairing rule:** a reference clip and its transcript always travel together, and `VoiceTake` has no way to hold one without the other. A clip described by the wrong text degrades the voice rather than colouring it, so an entry missing either half is skipped instead of paired with a mismatched transcript.
- **Reason:** The clips, their transcripts and their absolute paths are private data, and desktop Joi already owns them. Reading that manifest directly keeps one source of truth that cannot drift, instead of a second copy in this repository that would.

## DEC-023 — VRM renders natively via VRMMetalKit; Unity stays excluded

- **Status:** Accepted with conditions
- **Date:** 2026-08-13
- **Decision:** Native VRM uses [VRMMetalKit](https://github.com/arkavo-org/VRMMetalKit) (Apache-2.0) pinned at revision `8d87fd565c7629881cea980752c9d5518a504c7d`, vendored by `Tools/setup_vrm.sh` into an untracked `Vendor/` and admitted only through the `project.native.yml` build variant. DEC-003's exclusion of Unity, WKWebView and Three.js is unchanged.
- **Evidence that decided it:** the real `AvatarSample_A` is VRM **0.x** with 7 of 7 materials `VRM/MToon`, 10 spring-bone groups, 10 collider groups, 54 humanoid bones and 14 blend-shape groups. A renderer without MToon therefore renders this model *wrong*, not merely plainer, which ruled out `tattn/VRMKit` (MToon unimplemented, RealityKit path experimental). VRMMetalKit loaded and rendered that asset correctly on first attempt, drove its `happy` blend shape, passed 237 spring-bone conformance tests locally, animated its hair under a VRMA spin at 141 fps, and built for the iOS 26 simulator.
- **Why not Unity:** UniVRM is the most mature VRM implementation, but adopting it would rebuild the hardened `.joi-character` installer, the Live2D runtime that already works, and the SwiftUI two-surface shell in C#; it would not improve the Live2D Expandable Application position at all; and Unity-as-a-Library would add a second GC runtime plus tens of megabytes to an app meant to sit resident, against the G4 energy and thermal gates. The native path delivered the fidelity that was the only real argument for Unity.
- **Spec ladder:** `project.yml` (no vendor runtime, static fallback only) → `project.live2d.yml` (adds Cubism) → `project.native.yml` (adds VRM). Every rung stays independently buildable, so a clone with no SDK still compiles and ships the honest fallback.
- **Conditions:** VRMMetalKit has very low adoption and a single maintainer, so this is a bounded bet: it is a pinned, opt-in, App-target-only dependency, `CharacterRuntime` still admits exactly one dependency, and the static fallback remains testable. Its spring-bone simulation and MToon output are unverified on a real device, and no rights-cleared VRM package exists yet, so the in-app VRM stage is built but not yet visually confirmed inside the app.
- **Correction (2026-08-13):** "rendered that asset correctly on first attempt" was too strong. It renders the *materials* correctly; it does not render *hands* correctly. Every finger on both hands collapses into a single tapering cone. This is not a Joi defect and not an animation defect: it reproduces in VRMMetalKit's own `VRMRender` static CLI, on the plain bind pose, with no animation, no spring bones and no Joi code in the process, and it reproduces equally on the SDK's own bundled `AvatarSample_A_1.0.vrm.glb` driven by the SDK's own bundled `VRMA_01.vrma`. The skin has 91 joints, far below the shader's 256-matrix clamp, so the trivial explanation is ruled out and the cause is unidentified. **Open defect:** hands are visibly wrong on every VRM the stage draws. Fixing it means debugging skinning inside the pinned vendor copy, which is its own slice and its own decision; nothing in the character-package or animation contract is affected.

## DEC-024 — A VRM package declares its own motions; the model file carries none

- **Status:** Accepted
- **Date:** 2026-08-13
- **Why the frozen contract had to move:** a `.vrm` file contains a rig, materials and blend shapes — and no animation whatsoever. Every idle, greeting and dance clip is a separate `.vrma` file. The J1B `case .vrm` rule required `assets` to equal exactly `{entryPath, portraitPath}`, so a package carrying one extra `.vrma` was rejected as `invalidRenderer`. Under that rule a VRM character could physically never be anything but a T-pose. This is a contract defect, not a missing feature.
- **Decision:** `CharacterPackageManifestV1` gains an optional `motions` array of `{ motion, animation, loop }`, ported from desktop Joi's `appearance.motions` semantics: `motion` is the semantic name the product triggers (`idle`, `greet`, `happy`, …), `animation` is a package-relative `.vrma` asset, `loop` marks the clip that plays continuously. Only a `vrm` package may declare motions.
- **The motion table is the renderer graph.** J1B's rule is that a renderer graph — not a generic asset list — decides which files may enter runtime content, and `case .vrm` had no graph because a lone model file references nothing. `motions` supplies one: each entry must name a `.vrma` that is *also* declared in `assets`, and `assets` must still equal exactly `{entry} ∪ {portrait} ∪ {declared animations}`. An undeclared `.vrma` sitting in the tree is still rejected, so the contract admits animation without weakening into "any extra file is fine".
- **Rejections, all `invalidRenderer`:** motions declared on a `static` or `live2d` package (Live2D declares its motions inside its own `.model3.json` closure, and a second mechanism would create two sources of truth); a duplicate, empty, over-long or non-`[a-z0-9][a-z0-9_-]*` motion name; more than 64 motions; an `animation` that is not declared in `assets`; an `animation` that is not a `.vrma`; an `animation` that equals the entry model; an entry whose GLB does not inspect as VRM 0.x/1.0; an animation whose GLB does not inspect as VRMA. Format is checked by parsing the file's own glTF extensions, so a renamed `.vrm` cannot enter as a motion.
- **`duration_ms` is deliberately not ported.** Desktop records it beside each motion, but the clip file already carries its own duration; a second copy can only ever disagree with the file, and the player reads the real one.
- **Reached by renderers through the installer, not the filesystem:** `CharacterContentAccess` carries the verified motion table alongside the entry path, so a renderer plays a manifest-declared clip that revalidation has just re-hashed, and cannot be pointed at an arbitrary file. That is DEC-020 applied unchanged to animation.
- **Found while wiring this:** `VRMRenderer.enableSpringBone` defaults to `false` and the host must set it. The stage had never set it, so spring bones were not running at all — the hair and skirt were rigid, which was invisible while the pose was a static T-pose and would have read as "the animation is not working" the moment one played. Spring bones also need a pose applied before `warmupPhysics`, otherwise they settle at bind pose and snap on the first animated frame.
- **Spring bones are a device capability, and the host must gate them** (found 2026-08-17): every spring-bone kernel in the renderer is issued with `dispatchThreads`, which requires non-uniform threadgroup support. That arrived with Apple4 (A11), so every real target device has it and the **Simulator does not** — its Metal device is `Apple iOS simulator GPU`, and `supportsFamily(.apple4)` is false. Each of those dispatches is therefore an invalid call on the Simulator, and with Metal API Validation on — Xcode's default for a Run — the first one aborts the process inside `warmupPhysics`. The renderer has no capability check anywhere, so `VRMStageSurface` decides once from the device: unsupported means no warmup, `enableSpringBone` left off, and a named log line. Animation and motions still play; hair and cloth stay rigid, which is the honest degradation DEC-003 asks for rather than a crash.
- **The harness was weaker than the IDE, again:** `simctl launch` does not enable Metal API Validation, so the illegal dispatches went unchecked in every command-line run and the stage appeared to work. This is the same shape as the script-sandbox defect of 2026-08-14: verifying only through the repository's own scripts passes rules Xcode enforces. Reproduce Metal misuse with `SIMCTL_CHILD_MTL_DEBUG_LAYER=1`.
- **Two SDK defaults are wrong for authored characters, and both are host choices:** `VRMLoadingOptions.augmentSpringBoneColliders` defaults to `true`, adding a synthetic head/brow capsule and leg capsules on top of whatever the model authors; the SDK's own CLI additionally injects downward global gravity into any rig whose joints author `gravityPower == 0`. Both exist to rescue under-rigged models. `AvatarSample_A` is not under-rigged: it authors ten collider groups and pairs `gravityPower: 0` with `stiffiness ≈ 0.85` and `dragForce: 0.4`, which is hair built to hold its silhouette and merely lag behind the head. The stage therefore turns augmentation off and sets no global gravity, leaving per-joint `gravityPower` as the only gravity source. Measured effect of the collider change alone on the idle silhouette: hair span 332 px → 325 px. That is a real but small tidy-up, not a fix for gross deformation.

## DEC-025 — VRM lip sync opens one viseme from played audio

- **Status:** Accepted
- **Date:** 2026-08-13
- **Decision:** The VRM stage drives the `aa` expression each frame from `SpeechPlayer.currentAmplitude`, the amplitude of the audio actually playing, and writes it after the animation clip's own morph weights so a clip that animates the mouth cannot fight the voice. This is DEC-021's audio-only rule applied to the second runtime; Live2D already had it through `setLipSyncValue`.
- **One viseme, deliberately:** amplitude carries no phoneme information, so blending `ih`/`ou`/`ee`/`oh` out of loudness would animate speech shapes the audio never implies. DEC-021's standing rule is that this product stays still rather than mimes, so loudness drives exactly the one shape loudness justifies.
- **One path covers both VRM versions:** the loader maps VRM 0.x's `a` blend-shape group onto the VRM 1.0 `aa` preset, so `AvatarSample_A` (VRM 0.x, vowel groups `a`/`i`/`u`/`e`/`o`) and a VRM 1.0 model are driven identically. A model that declares neither has nothing bound to the weight and simply keeps its mouth shut.
- **Silence needs no bookkeeping:** the weight is written every frame including zero, so the mouth closes on its own when playback stops or fails, and a failed fetch stays silent with a closed mouth rather than a stuck open one.
- **The app must claim the audio session, or the character is mute** (found 2026-08-14): nothing configured `AVAudioSession`, so playback ran on the default `soloAmbient` category. That category is silenced by the ring/silent switch, which on a real device means no voice, a still mouth, and nothing in the log explaining either. `SpeechPlayer` now takes `.playback` with mode `.spokenAudio`, claimed lazily immediately before the first line rather than at launch — configuring it at startup would interrupt whatever the user was already listening to merely because they opened the app. A session the system refuses is logged, because a diagnosable silence is the whole point of DEC-021's silence rule.
- **Mouth motion is shaped in seconds, not in frames:** amplitude is smoothed by an exponential approach with real time constants — about 35 ms opening, 90 ms closing — instead of a fixed per-poll factor that changed character whenever the stage missed 60 fps. The asymmetry is what a mouth does: symmetric smoothing either chatters on syllable edges or hangs open at the end of a line. Neither `stop()` nor end-of-playback zeroes the level any more, so a line ends with a mouth that closes over the same constant the gaps between syllables use.
- **Two loader defaults are wrong for an authored rig.** `VRMLoadingOptions.augmentSpringBoneColliders` defaults to `true` and adds a synthetic head/brow capsule and leg capsules on top of the ones the model authors; the SDK's own CLI additionally injects downward spring gravity into any rig authoring `gravityPower == 0`. Both exist to rescue under-rigged models. `AvatarSample_A` authors ten collider groups and pairs `gravityPower: 0` with `stiffiness ≈ 0.85` and `dragForce: 0.4`, which is a rig built to hold its silhouette and merely lag behind the head. The stage therefore loads with augmentation off and sets no global gravity. Measured effect on the hair silhouette: 332 px wide → 325 px, about 2% — real but small, and not the whole story of why the hair reads differently from desktop Joi.

## DEC-026 — Cross-platform semantics are executable vectors, not prose

- **Status:** Accepted, with one open identity question
- **Date:** 2026-08-13
- **What was actually shared before this:** `Contracts/*.schema.json` really is platform-neutral — any Draft 2020-12 validator agrees with iOS about a document's *shape*. Everything else that a second client must reproduce exactly was Swift source with English around it: that a duplicate key makes a manifest inadmissible rather than last-key-wins; which of two incompatible envelopes sharing the label `joi.character.v1` a document belongs to, and that matching both is a refusal; that a key whose name contains `memory`, `token` or `credential` is refused at any depth; **which stable code** each refusal produces, when the codes are what select the sentence a user reads; how content identity is computed byte for byte; and how the event stream is framed.
- **Decision:** `Contracts/conformance/` holds executable vectors that every Joi client runs. Four files today — content identity, the strict JSON scanner, document-level manifest admission, and SSE framing. `content-id.json` is generated by `Tools/make_conformance_corpus.py` from the written rule rather than recorded from an implementation, so the corpus is a specification that implementations are measured against and not a snapshot of current behaviour. A vector changes only with a decision recorded here; adding one is ordinary work.
- **Why the corpus rather than a shared core:** extracting a shared native core is the other way to guarantee agreement, and it is much more expensive: a C++ or KMP core would have to be reached from Swift and from Kotlin, would take a build-system dependency into both apps, and would still need vectors to prove the bridges behave. Vectors buy the agreement without the coupling, and they keep working if a shared core ever does arrive.
- **Found on the first run, and this is the point:** two disagreements between the written rule and the shipping iOS implementation.
  1. `StrictJSON.object` let a raw `NSError` escape. The owned scanner accepts a well-formed top-level scalar, which `JSONSerialization` then refuses as a fragment, and that Foundation error propagated out of a boundary every caller expects to produce a stable import code. Fixed by wrapping the call; a manifest that is a bare JSON string now answers `invalidManifest` like every other malformed document.
  2. **Open:** content identity is computed over the path bytes the filesystem hands back, not the bytes the package declared. Darwin returns `café.txt` decomposed (`U+0065 U+0301`) for a file written composed (`U+00E9`), so iOS hashes NFD while a port on ext4 hashes NFC, and the same `.joi-character` installs under two different identities on the two platforms. No existing test could catch it, because Swift's `String` equality is canonical: the installer's `normalized == path` guard compares NFC against NFD and returns `true`. Kotlin's `==` does not, so the same guard would *reject* the tree there — the platforms would disagree about admissibility as well as identity.
- **Confirmed on both sides (2026-08-14):** this stopped being an inference the moment the Kotlin core compiled. Its `content identity of a materialised tree` case passed on every vector *including* `decomposable-path`, because it normalizes to NFC before hashing; the Swift twin had to skip that one case to stay green. Two implementations sharing no source, one corpus file, disagreeing precisely where the rule predicted — and the platform that did not conform was iOS.
- **Closed (2026-08-14):** `CharacterTreeVerifier.contentID` now hashes and orders paths by their **NFC UTF-8 bytes**, keeping the on-disk form only for opening the file. `decomposable-path` is normative and both platforms pass it. Ordering is explicitly over UTF-8 bytes rather than `String.sorted()`: the two agree for NFC-normalized paths, but the corpus states bytes, so the code says bytes.
- **What the migration actually costs, and why it was cheap now:** `contentID` names the installed content directory *and* is re-verified against the stored record on every activation, so a package whose identity changes becomes an unreachable install rather than a silently different one. That only reaches packages with decomposable non-ASCII filenames — accented Latin, kana with dakuten. Every fixture in this repository is ASCII and unaffected; nothing is shipped; the only exposure was local development installs, which reinstall. The same change after release would have been a data migration on user devices, which is why it was worth closing the moment the divergence was measurable rather than filing it.
- **Deliberately not covered:** the restricted ZIP profile, per-asset digest verification, media magic bytes, the Live2D reference closure, the VRM motion-table renderer graph, activation leases and journaled removal. They need a tree fixture rather than a document, and the corpus format has to grow one first. Until it does, a second implementation of that layer is a re-derivation, not a port.

## DEC-027 — Android is a second native client with a portable JVM core

- **Status:** Accepted for the initial slice
- **Date:** 2026-08-13
- **Decision:** `android/` is a Gradle build whose default targets are three plain-JVM Kotlin modules — `companion-core`, `character-runtime`, `chat-feature` — mirroring the Swift packages of the same names and carrying no Android dependency and no third-party dependency whatsoever. They are verified against `Contracts/conformance/` in the same lane as iOS. The Android application module joins the build only when an SDK is actually present, detected from `ANDROID_HOME`, `ANDROID_SDK_ROOT` or `local.properties`.
- **Why the core before the shell:** a Compose shell with two tabs is the cheapest part of an Android client and the least likely to be wrong. What is expensive and silent is *disagreeing with iOS*: a package must have the same identity on both, and a manifest refused on one must be refused on the other with the same code, or one file produces two different explanations. Building the shell first would mean re-deriving those semantics later, under deadline, from prose.
- **Why the SDK gate:** it is the same spec ladder as `project.yml` → `project.live2d.yml` → `project.native.yml`, applied to a second platform, and it keeps the portable core reviewable and testable on any machine with a JDK. It also keeps a licence decision where it belongs: Google's SDK requires accepting its agreement, which a build script must not do on a developer's behalf.
- **Why no third-party dependency in `character-runtime`:** iOS admits exactly one (ZIPFoundation, pinned to an exact revision) and owns every security decision above it. The Kotlin core tightens that to zero for now, and specifically does not parse manifests with `JSONObject`, Gson or kotlinx.serialization: every mainstream parser silently accepts a duplicate key and keeps the last one, which is the whole attack the owned scanner exists to refuse.
- **Not decided here:** the Android VRM and Live2D renderers, the Compose surfaces, map/location/camera adapters and any UI code. Filament plus `gltfio` is the plausible renderer base — it covers mesh, skinning, morph targets and material bases, leaving MToon, humanoid normalization, LookAt, spring bones, constraints and VRMA as Joi's own work, which is the same division as iOS with a different GPU layer underneath. None of that is evaluated yet.
- **Live2D on Android is a second licence, not a second build.** DEC-018 establishes that Joi is an Expandable Application and therefore needs Live2D Inc.'s review and a Publication License Agreement before release, with no small-business exemption. That agreement is per application: an Android build is a separate application and needs its own approval. VRM-first with Live2D gated behind approval applies to Android exactly as it does to iOS, and the total licence exposure of supporting both platforms is two approvals, not one.

## DEC-028 — The declared asset list is bounded by the contract, not by the generic array guard

- **Status:** Accepted
- **Date:** 2026-08-13
- **The defect:** the forbidden-content walk caps every JSON array at 300 elements, and that walk runs over the whole manifest, so it capped the declared `assets` array too. Meanwhile the schema's `assets.maxItems`, `CharacterPackageLimits.maximumFileCount`, the ZIP preflight and the tree verifier all say 2000. A package declaring 301 assets was therefore schema-valid, inside every stated limit, and refused as `invalidManifest` — a code that names nothing its author can act on. Measured before the fix: 300 admitted, 301 refused.
- **Who it hits:** a rich Live2D character. A few hundred motion, expression and texture files is an ordinary authored model, not an abusive one, and it was silently unimportable.
- **How it was found:** by the DEC-026 conformance work, probing the boundary instead of reading it. The 300 was a generic anti-blowup guard for arbitrary nested arrays that nobody had noticed also governed the one array the contract sizes explicitly.
- **Decision:** the declared asset list, and only that array, is bounded by `maximumFileCount`. The exemption is keyed on the canonical envelope, `depth == 1` and the exact path `["assets"]`, so an array nested *inside* an asset entry arrives with the same path but a greater depth and keeps the generic 300 bound. Every other array in the document, and any JSON carried as package content, is unchanged.
- **Second-order consequence, and the reason this is not a one-line fix:** 2000 declared assets do not fit in a 256 KiB manifest at realistic path lengths, so the byte bound would simply have bitten first — and reported `unsafeArchive`, capping the declared asset count at a number the contract never states and explaining it with the wrong code. `maximumManifestBytes` is therefore raised to 1 MiB and named, rather than left as a literal at the call site.
- **Why not lower the schema to 300 instead:** the count is not the safety property. Path safety, digest verification, media typing and renderer-graph closure are, and each is checked independently of how many entries there are. Capping the contract at 300 would refuse legitimate characters to enforce a bound that protects nothing the other checks do not already cover.
- **Why not simply give the 300 its own stable code:** a clearer sentence for a refusal that should never have happened is not a fix. The schema would still validate a 500-asset package that the runtime then refuses, and a new code would make that disagreement permanent by naming it.
- **What is left, stated rather than hidden:** the two bounds are on different axes, so the byte bound still decides in one corner. 2000 assets fit while paths average under roughly 400 characters; a document whose paths all approach the schema's 512-character maximum exceeds 1 MiB and is refused for size. Above that bound the platforms answer with different codes — iOS reads `manifest.json` through a bounded read and answers `unsafeArchive`, a platform handed the bytes answers `invalidManifest` from the scanner. That is the read-path boundary `manifest-validation.json` already excludes from the admission stage, not a new divergence, and both the corpus notes and the iOS test say so explicitly rather than leaving it to be rediscovered.
- **Guarded where the drift happened:** the defect was three artifacts disagreeing in silence, which no single artifact can notice. `Tests/test_contracts.py` now reads the schema, the Swift limits and the Kotlin limits together and fails if the declared bound stops being one number, if the two platforms' generic guards stop matching, or if the manifest byte bound stops holding a real 2000-asset document.
- **Not vectored in the corpus:** a case with 2000 declared assets is a quarter of a megabyte of filler that no reviewer would read. The numbers are asserted in the Swift and Kotlin test twins instead, and `Contracts/conformance/manifest-validation.json` notes point at both — including the assertion that every *other* array stayed at 300, so a later change cannot remove the guard while believing it corrected it.

## DEC-029 — The restricted ZIP profile refuses every mainstream archiver

- **Status:** Accepted; four changes made and measured
- **Date:** 2026-08-15
- **How it was found:** `Contracts/conformance/zip-profile.json` (DEC-026's layer applied to archives) put 40 complete archives through the preflight. Thirty-seven agreed with the written policy on the first run. Chasing the three that did not led to archives produced by real tools, and none of them can be imported.
- **Measured on 2026-08-15**, one folder containing two files, archived four ways:

  | Producer | Extra fields written | Directory mode | Outcome |
  |---|---|---|---|
  | `zip -r` | `0x5455` extended timestamp, `0x7875` Unix UID/GID | `0o40755` | `unsupportedArchiveProfile` |
  | `ditto -c -k` (Finder's Compress) | `0x5855` old Info-ZIP Unix | `0o40755` | `unsupportedArchiveProfile`, and it adds a `__MACOSX/` sidecar tree |
  | Python `zipfile` | none | n/a | `unsafeArchive` |
  | `zip -rX` | none | `0o40755` | `unsafeArchive` before the fix below |

- **The defect, fixed:** `validateAttributes` refused any Unix entry with an execute bit, including directories. On a directory that bit is the *search* bit — a directory without it cannot be entered, so every archiver writes `0o755`. The rule was written for files and silently applied to folders, which refused every archive containing one. Since a Live2D package is a folder of textures and motions, this refused essentially every real Live2D ZIP. Execute bits are still refused on files.
- **Resolved by ordinary practice, since none of these is a Joi-specific question.** Four changes, each narrow:
  1. **Extra fields `0x7875` and `0x5855` are admitted**, length-checked and their bodies ignored. They carry uid, gid and timestamps — integers, no path, no link target. Every extractor ignores them and `zip` and Finder write one or the other on every entry. ZIP64 (`0x0001`) and everything unrecognised stay refused, because those change field meanings or could carry a target.
  2. **A zero file-type nibble is admitted** for a Unix host, as "permissions recorded, type not". This is not a way to smuggle a link: a symbolic link is only a link when `S_IFLNK` is *set*, so an absent type is an absent claim rather than a false one. Python's `zipfile` and several Java libraries write exactly this. An earlier note in this file argued the opposite; that reasoning was wrong.
  3. **`__MACOSX/` and `.DS_Store` are validated and then not extracted.** They are Apple archiver bookkeeping, never package content, and a renderer graph would refuse them as undeclared assets — so a Finder archive would fail for a reason the user can neither see nor fix. The skip happens *after* every other check, so a hostile entry hiding under `__MACOSX/` is refused on exactly the same terms as any other; it simply never reaches disk.
  4. **The data-descriptor flag is admitted.** Finder streams its output and sets bit 3 on every entry, putting zeros in the local header and the real CRC and sizes after the payload. What this gives up is the local header confirming the central directory — and that was never the guarantee: the central directory is what every extractor treats as authoritative, its values are still bounded here, and extracted bytes are still hashed against the manifest afterwards. A local header that is *neither* the placeholder nor the truth is still `malformedArchive`, and encryption stays refused because nothing here can read those bytes at all.
- **Measured after the changes**, the same folder archived four ways: `zip -r`, `ditto -c -k`, Python `zipfile` and `zip -rX` are all admitted, and the `ditto` archive's plan contains its two real files with no sidecar. That is the evidence this decision rests on — not that the vectors pass, but that archives from the tools people actually use now import.
- **What did not change:** ZIP64, multidisk, encryption, unsupported compression methods, traversals, absolute paths, backslashes, colons, control characters, case and normalization collisions, symlinks, executable *files*, directory entries carrying payload, non-UTF-8 names, overlapping ranges and every limit. The profile is narrower than the format in every way that touches what lands on disk.
- **Why this stayed invisible until now:** the J1B corpus was built by the test code, which chose header fields that satisfied the parser. Nothing exercised an archive a person would actually hand the product. The three producer archives are carried in the corpus as non-normative vectors recording what happens today, so the finding cannot be lost between sessions.

## DEC-030 — Android VRM: Filament supplies the GPU layer, Joi supplies all of VRM

- **Status:** Accepted as the direction; **no prototype has been built**
- **Date:** 2026-08-15
- **What the renderer has to do**, read off `VRM/VRMStageSurface.swift` rather than imagined: load a GLB; load `.vrma` clips; blend animation and apply per-frame morph weights; drive one expression by name each frame (`setExpression(.aa, weight:)`) after the clip's own weights; run spring bones with a warm-up pass before the first animated frame; render MToon, which needs lights present or the model comes out flat; set a view matrix; draw per frame.
- **Measured on 2026-08-15:**

  | Fact | Value |
  |---|---|
  | Filament, Maven Central | `com.google.android.filament` 1.75.0 |
  | `filament-android` / `gltfio-android` / `filament-utils-android` | 5.2 MB / 5.8 MB / 2.4 MB, multi-ABI |
  | `matc`, the material compiler | ships in `filament-v1.75.0-mac.tgz`, 43.8 MB, build-time only |
  | `filamat-android`, the *runtime* compiler | 12.5 MB — too large to ship for one material |
  | **VRM libraries on Maven Central** | **zero results** |

- **Decision:** Filament plus `gltfio` is the GPU layer — mesh, skinning, morph targets, material base, camera, frame loop. MToon is written as a Filament material and compiled to a `.filamat` blob by `matc` at build time, shipped as an asset; the runtime compiler is not admitted. Everything with VRM in its name is Joi's: 0.x→1.0 normalization, humanoid, expressions, LookAt, spring bones, node constraints, VRMA parsing and retargeting.
- **The strategy document understates this, and the difference matters.** It says Android "likewise has no direct equivalent of UniVRM". iOS had one: VRMMetalKit, which already implements spring bones, MToon, expressions and VRMA. Android has **nothing** — the search returns zero. So the Android renderer is not the same amount of work as the iOS one was; it is the iOS work *plus* everything VRMMetalKit already did.
- **Consequence for the shared-core question.** The document's advice to defer a shared VRM core rested on "extract it only when duplicate implementation cost is clearly visible". That cost is now visible before either side is written twice: Android must implement the whole VRM semantic layer from scratch, and iOS's implementation is a single-maintainer dependency with an open, unexplained hand-skinning defect (DEC-023). The parser, 0.x→1.0 normalization, humanoid and expression semantics, spring bones, constraints and VRMA retarget are all pure computation over model data with no GPU in them — which is exactly the shape that ports well. This is not a decision to build that core; it is a record that the premise for deferring it no longer holds and the question should be re-asked before Android renderer work starts.
- **Not evaluated, and not claimed:** no prototype exists. Nothing here is evidence that Filament loads a VRM, that a hand-written MToon matches VRMMetalKit's output, that spring bones behave, or that any of it holds a frame rate on a real phone. The next slice is a bounded spike — one model, one clip, on the emulator and then on a device — and it should be run before any of this is treated as a plan.
- **Unchanged:** DEC-003's exclusion of Unity, WKWebView and Three.js. Filament is a native renderer admitted the same way VRMMetalKit is on iOS: pinned, opt-in, app-target only, with the static fallback still testable.

## DEC-031 — Voice input recognises on device or not at all

- **Status:** Accepted
- **Date:** 2026-08-17
- **Decision:** Push-to-talk uses `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`. When a device or locale cannot recognise on device, voice input reports itself unavailable and the keyboard remains; it never quietly falls back to server recognition.
- **Why the fallback is refused:** server recognition uploads the recording to Apple. This product's standing rule is that nothing leaves the device without an explicit, inspectable act by the user — the same rule that keeps location out of memory and keeps character packages local. A microphone that sometimes uploads and sometimes does not, with no visible difference, is exactly the silent-transmission case that rule exists to prevent. Speaking into a companion is not consent to send the recording to a third party.
- **Consequence, stated rather than hidden:** on-device recognition is not available for every locale or on older hardware, so voice input is a capability that can be absent. It says so in Chinese and the composer keeps working, which is the same honest-degradation shape as the static character fallback and the spring-bone gate.
- **The audio itself stays put:** recognition consumes the live buffer and nothing is written to disk. The transcription lands in the composer as an editable draft rather than being sent, because a misheard sentence should be correctable before it becomes a turn the character answers.
- **The system prompt is Apple's and cannot be argued with:** iOS always tells the user that speech data may be sent to Apple, because the permission itself covers server recognition. An app string next to it claiming "the recording never leaves this device" reads as the app contradicting the operating system on the same screen, and the user has no way to tell which is true. The usage description therefore states what Joi does with the permission — asks only for the on-device recogniser, and closes voice input rather than taking the uploading path — which is both accurate and compatible with the sentence above it.

## DEC-032 — A journey attachment is coarsened before it is shown, and authorised for one turn

- **Status:** Accepted
- **Date:** 2026-08-18
- **Decision:** When the user hands the current walk to the conversation, the payload is rounded onto a 0.001° grid (~111 m of latitude, ~95 m of longitude at this route's latitude) at the moment the offer is constructed, its `horizontalAccuracyMeters` is raised to that grid, and it is stamped `consentScope = "chat-one-turn"`. Sending binds it to that request with a `JourneyUseReceiptV1` and spends the receipt through `JourneyUseReceiptStore`. The offer expires after five minutes.
- **Why coarsen at construction rather than before transmission:** DEC-002 permits location into Chat "only through explicit, inspectable attachment/consent". *Inspectable* is doing the work: if the card renders a precise fix and something downstream reduces it — or does not — the user has approved one thing and the product has sent another, and no test can tell the two apart from outside. Building the reduced value first makes the preview and the payload the same object, so the card cannot show a number that is not the number being sent. The card prints three decimals for the same reason: a fourth would display precision the payload does not contain.
- **Why coarsen at all, when the act is already explicit:** an explicit act makes sending *permitted*, not unlimited. What the companion is being asked — what is this place, what is around me on this walk — is answerable from route identity, progress and a neighbourhood-level position. The remaining metres add nothing to the answer and everything to the exposure, and PRD Journey 3's own success criterion is that ongoing precise location does not reach the transcript. The receipt's `precision` field, which until now had no producer, is what records which of the two was authorised.
- **`precision` is stated as the grid, not as a distance:** `coarse-0.001deg` is exact and latitude-independent; "100 m" is neither. The Chinese copy says 约 100 米 because that is what a person needs, and the receipt says the grid because that is what a reader of the record needs.
- **Scope is part of the payload, so authority is bound to purpose.** `payloadDigest()` covers `consentScope`, and the receipt carries the digest. The same coordinates re-labelled for memory or sync produce a different digest and fail validation against a chat receipt. The one-turn approval therefore cannot be lifted onto a durable write by reusing the bytes — a property the contract already made possible and nothing had yet used.
- **Expiry refuses the send rather than stripping the attachment.** A walking fact answers "where am I now" and is usually wrong five minutes later. The tempting behaviour — send the message without the location — is the one thing that must not happen: the question was written expecting the context, the answer would be wrong, and nothing on screen would say why. The named failure keeps the draft, and re-attaching costs one tap.
- **Stopping the walk withdraws an un-sent offer.** PRD §6.5 lists send, cancel, expiry and revoke as what ends an attachment, and ending the journey is not among them. It is added here anyway: leaving a staged position behind after the user has visibly stopped sharing is a surprise this product should not spring, and the fact is worthless by then in any case.
- **Not proven by this slice:** no place identity, no source projection, no memory proposal, no device-location evidence. The attachment describes a route and a position on it, because that is all the journey owner currently holds.

## DEC-033 — Memory is user-initiated, gated by eligibility, and never location

- **Status:** Accepted
- **Date:** 2026-08-18
- **Decision:** A durable memory is created only by the user accepting a visible proposal. The backend's `memoryEligibility` decides whether a line may be proposed at all; the proposal shows the wording, category, reason and storage location before anything is written; the wording is editable and an edit is recorded as `editedAndAccepted`. `preciseLocation` and `protectedNeverSync` are not offerable categories, and nothing written this way is sync-eligible.
- **Why user-initiated rather than model-proposed:** `JM-P0-005` says no model-generated proposal becomes durable silently, which implies model-generated proposals exist — but `CompanionEventV1` carries only an eligibility flag and no proposal payload. Building the model side now would mean inventing the content locally and presenting it as the model's suggestion, which is the sort of fiction this repository keeps finding and deleting. So eligibility is used as what it actually is — a gate — and the content comes from the user. A backend that proposes needs a contract field first, and adding one is a separate decision.
- **Why the control is absent rather than disabled** on an ineligible line: a greyed-out button invites the user to argue with a decision the app does not own. Eligibility is the backend's answer; the app either offers the action or does not.
- **Why location cannot arrive this way.** Talking about where you are is not authorising the storage of where you are. TDD §8.3 forbids implicit promotion of precise location to long-term memory, and a chat proposal is exactly the implicit path. A location memory would need its own authorisation carrying its own precision and retention — the neighbouring decision DEC-032 made for one chat turn — so the categories are absent from the picker *and* refused by the record builder, because a rule enforced only by a picker is enforced by the UI.
- **Why the store is not encrypted, said plainly:** it is JSON under Application Support, protected by the device. There is no key, no keychain material and no threat model here beyond that, and describing it as encrypted would be a claim without a mechanism. It sits beside the character root rather than inside it, so removing a character package cannot take the conversation's memory with it.
- **Not proven by this slice:** export, server-acknowledged deletion, sync replay and tombstones are `JM-P0-019` and `JM-P0-023` and remain unimplemented. The G3 gate is untouched by this.

## DEC-034 — A source may be refused, and a refused source is still shown

- **Status:** Accepted
- **Date:** 2026-08-18
- **Decision:** Whether a `SourceProjectionV1` may stand behind an answer is decided by `SourceEligibility` in CompanionCore, not by a view. A withdrawn revision and a retracted claim are refused outright; evidence below a `claimSupportConfidence` floor of 0.5 is refused as not supporting the claim. Refused sources are still listed, with the reason. An answer that carried sources and has none left is a distinct state from one that carried none.
- **Why the rule is in CompanionCore rather than the view:** a second client has to reach the same verdict from the same event. A rule written inside a SwiftUI file cannot be run anywhere else, and cannot become a conformance vector when the Android side implements it.
- **Why refused sources stay visible.** The tempting design is to filter them out and show a clean list. But "the source for this was withdrawn" is information about the claim, not clutter — it is often the most important thing on the screen. Hiding it would turn a retracted claim into what looks like an ordinary unsourced remark, which is the precise failure PRD §8.1 is written to prevent. So the withheld set is carried alongside the eligible one and rendered with its reason.
- **The floor is 0.5, and it is a product judgement.** It is the only place in this rule where a number becomes a decision, and it exists because presenting a source as supporting a claim when its own support value is 0.1 would be a misrepresentation. On balance means half.
- **It applies to evidence support and nothing else.** PRD §8.1 keeps four questions apart — what is this, who says it, does this source support this claim, which version and when — and forbids collapsing them into one probability. So a source with 0.05 identity confidence or `community` authority still supports: those are shown, separately, for the reader to weigh. Nothing in this rule adds or averages them, and there is no combined score to display because none is computed.
- **Sources are an App projection, not a `TranscriptEntry` field.** That type is frozen, mirrored in the Kotlin core and encoded into the session schema; nothing yet needs citations to survive a session reload. Widening it is the right move when persistence needs it, and should be a decision rather than a side effect.
- **Not proven, and not claimed:** no backend emits sources — both the mock and the proxy return an empty array — so this is a rule and a renderer with fixtures behind them, not a live sourced answer. Place identity, cached-narration freshness and conflict resolution across real publishers remain unimplemented, and the G5 rights gate is untouched.

## DEC-035 — A failure state is implemented, partial or absent, and says which

- **Status:** Accepted
- **Date:** 2026-08-18
- **Decision:** The 32 named failure states of PRD §7/§7.1 are published as `Contracts/failure-states.json`, generated from the PRD by `Tools/make_failure_corpus.py`. Each entry carries its fixture ID, the PRD's own cancellation text, a status of `implemented`, `partial` or `absent`, the module that owns it, and the tests that hold it there. A state may not claim `implemented` without evidence that exists, may not be `partial` or `absent` without naming its gap, and may not be `absent` while citing evidence.
- **Why generate rather than retype:** the states and their cancellation rules are the requirement. Copying them into a second file creates two sources that drift, and the drift is invisible until someone reads both. Generating means the corpus cannot disagree with the PRD about *what* the states are; the guard covers the other direction, failing when a PRD edit has not been regenerated.
- **Why three statuses rather than a checkbox.** Most of these states are partly true. `FAIL-016` rejects an unusable accuracy but ignores sample age; `FAIL-026` verifies a pack but cannot quarantine one. Recording those as implemented would be false and as absent would be misleading, and both readings would hide the specific thing that is missing. `partial` plus a written gap is the only form that survives contact with the actual code.
- **`absent` is a claim too.** Thirteen states are absent because their features do not exist. Saying so in the corpus means a reader learns it from the artefact rather than inferring it from silence — which is the failure mode the traceability table had, where a fictional test name read as coverage.
- **What it found immediately:** `FAIL-015` was a defect, not a gap. `startWalk` opens a journey before the system answers about location permission, because a reading needs somewhere to be reduced into, and nothing undid that when the answer was "no" — the walk stayed nominally in progress, `JourneyContextStore` kept a snapshot for a route nothing was tracking, and Map went on offering to carry that context into the conversation. Writing down the declared semantics is what made the contradiction visible.
- **Thresholds are not invented to close a row.** `FAIL-016` wants stale and inaccurate samples refused. Choosing an accuracy ceiling and a staleness window is a field decision that needs G4 evidence, so the gap is recorded and the current behaviour is pinned by a test instead — adding a ceiling later has to be deliberate rather than silent.

## DEC-036 — A recap separates fact from reflection by shape, not by a flag

- **Status:** Accepted
- **Date:** 2026-08-18
- **Decision:** A cached route carries ordered `RouteStop`s with their own narration and source revisions. A trip recap is a list of `RecapEntry` values with exactly two cases: `.fact`, which carries source revisions, and `.reflection`, which cannot. Only a fact may be proposed as durable memory, as a `travelRecap` item that still has to be accepted. Completion follows the furthest point reached, held by the App; `RouteNarrative` stays a pure function.
- **Why two cases rather than `sourced: Bool` plus an optional list:** `JM-P0-012` asks for a recap that distinguishes sourced facts from the character's reflective language, and a flag makes both wrong states constructible — a fact with no source, a reflection carrying a citation. The rule then lives in whichever reader remembers to check it, which over time is none of them. As two cases neither is representable, and the compiler enforces what the requirement asks for.
- **An unsourced stop is not an unsupported claim.** It is not a claim. That distinction matters because `FAIL-022 sourceUnsupported` is about factual narration that has lost its evidence and must be withheld; a character saying the wind changed is not withheld, it is simply not a fact. Conflating them would either silence the companion or dress its remarks as research.
- **Why only facts can be remembered.** PRD Journey 6 offers to save selected recap *facts*. Putting the model's passing remark into durable memory wearing the clothes of something the user learned is the failure this separation exists to prevent — and `travelRecap` was already a `MemoryCategory` with no producer, so this is the producer it was waiting for.
- **Completion is a high-water mark, and it lives in the App.** Walking back to look at something again must not un-visit the stops beyond it, and a paused walk must resume with what it covered. Keeping the mark outside the narrative type makes both true without any session state to lose: the walk's history is one number, so pause and resume are free.
- **The bundled sample stays a sample.** It is not a rights-cleared travel pack, so its stops are almost entirely the character's own words. The single factual line carries a revision beginning `fixture://`, which announces what it is; a test enforces both halves so the sample cannot quietly grow research it has no rights to.
- **Not implemented, and not claimed:** travel-pack import, so `FAIL-025` and `FAIL-026` are unchanged and `JM-P0-014` stays partial. Route-narration speech is absent too — `SpeechPriority.placeNarration` still has no producer, because speaking a stop needs the voice pipeline and device audio evidence rather than one more call site.

## DEC-037 — A travel pack ships what it declares, and is a directory, not an archive

- **Status:** Accepted
- **Date:** 2026-08-18
- **Decision:** `TravelPackInstaller` verifies a candidate pack completely before anything is moved: schema, rights, expiry, every declared file's SHA-256, refusal of undeclared files, refusal of paths that could reach outside the pack, and construction of the tour itself. Only then is the candidate copied into the store under `packID@version`, re-read and re-verified in place. A refusal leaves the installed pack byte-identical. `TravelPackContentV1` is a separate contract carrying the route and its stops, declared and hashed like any other file.
- **Why undeclared files are refused.** A hash list proves the content it covers and says exactly nothing about content nobody declared. Admitting extra files would let a pack carry assets no receipt mentions and no rights statement covers — the same hole DEC-020 closes for character packages, and the reason that rule is worth restating rather than assuming.
- **Why missing and invalid are different errors.** `FAIL-025` is content the pack promised and did not bring; the recovery is to fetch it again. `FAIL-026` is content that is present and wrong; the recovery is to distrust the pack. Collapsing them into one "bad pack" message would push users to re-download something they should not install.
- **Why it is not an archive reader.** `CharacterRuntime` owns the restricted ZIP profile (DEC-011, DEC-029), which is the most safety-critical code in this repository and took a full gate plus rework to get right. Writing a second ZIP policy here would create a weaker copy of it, and the copy would drift. A pack arrives as a directory; packaging is a later decision that should reuse that profile, not re-derive it.
- **Why the sealed copy is re-read.** A check that passed on the candidate proves nothing about the bytes that ended up in the store. The character installer re-opens after moving for the same reason, and this does too — including re-verifying every hash from the sealed location.
- **`FAIL-026` stays partial on purpose.** There is no signature. Self-declared hashes prove integrity, not publisher authenticity, so no pack can yet be attributed to anyone. DEC-010 records the same gap for character packages, and marking this state closed would claim an authenticity property nothing here provides.
- **Not implemented, and not claimed:** downloading packs. This imports a pack the user already has, which is enough to make the walk a verified tour and leaves network fetch, catalogues and update policy as separate work. Flight-mode field behaviour remains G4, and map/tile rights remain G5.

## DEC-038 — Local-first is pinned by a guard, and the welcome is not a gate

- **Status:** Accepted
- **Date:** 2026-08-18
- **Decision:** `JM-P0-002`'s property — usable with no account and no permission grant — is enforced by a test that pins each permission API to the single file that owns it and forbids all of them on the launch path. `requestAlwaysAuthorization` and the camera and photo APIs may not appear anywhere. The first-run welcome explains local-first storage, durable memory and just-in-time permissions, and is an overlay that can be dismissed with one tap.
- **Why a source-level guard and not only a behavioural test.** A behavioural test can show that *today's* launch asks for nothing; it cannot stop tomorrow's diff from adding a request inside a view's `.task`, where it would look entirely reasonable in review. The property is about code that must not exist, so the guard checks for code that must not exist. A negative control keeps the guard itself honest.
- **Why the welcome is not a walkthrough.** PRD §3.2 defines first run as complete once a character is visible and a message can be sent. Anything standing between the user and that makes first run longer than the requirement says it is, so this is an overlay over a working app rather than a sequence of pages, and a test asserts a message can be sent while it is still on screen.
- **Why dismissing without reading is remembered.** Reading is not a requirement. Making the dismissal conditional on scrolling to the end would turn an explanation into a toll, and would teach users that this app's consent surfaces are obstacles — which is the opposite of what the memory and location previews need them to believe.
- **What the welcome says is limited to what is true now:** no account exists, nothing syncs, memory is durable only after an explicit confirmation, and the two permissions are requested at the moment they are used. Every one of those is enforced by a test elsewhere in the suite, so the copy is a description rather than a promise.
- **`UserDefaults` is now injected.** The last three direct `UserDefaults.standard` uses meant a test could write the active-character pointer to one store and read it from another, and that any first-run test would depend on the workstation's own state. The model takes its store.
- **Not built, deliberately:** the rest of PRD §3.2 as screens. Character choice has the Character Library, Chat introduction is the stage, Map introduction is the Map surface. Adding pages in front of surfaces that already explain themselves would be onboarding for its own sake.

## DEC-039 — An import that will not fit is refused with both numbers, before it starts

- **Status:** Accepted
- **Date:** 2026-08-18
- **Decision:** `TravelPackInstaller` computes the exact byte requirement while verifying declared files, compares it against what the destination volume reports, and refuses with `storageInsufficient(requiredBytes:availableBytes:)` before copying anything. A volume that cannot report capacity is treated as having room. Any failed copy removes its staging directory. The capacity source is injected.
- **Why both numbers travel in the error.** `FAIL-029`'s requirement is to show required against available. "Not enough space" is not actionable — the user cannot tell whether to delete one photo or ten thousand. Carrying the pair in the error type means no layer has to re-derive them, and the App only formats.
- **Why an unreported capacity is not a refusal.** Failing closed is usually right, but here the closed direction is wrong: refusing an import because the filesystem declined to answer a question would block a user whose device is fine. The risk of proceeding is a copy that fails part-way, which the staging cleanup already handles safely.
- **Why the capacity source is injected.** The refusal branch is only reachable through `install` by controlling what the volume reports. The alternative — filling the real disk — would test the filesystem rather than the rule, and would break the machine running the suite.
- **Recorded because it nearly escaped:** the first version of these tests called the space check directly rather than through `install`, so the call site was untested and deleting it left the suite green. Mutation testing caught it. The tests now drive the real path.
- **`FAIL-029` stays partial.** Character-package import is not covered: its expanded size is only known while streaming, and giving the user the two numbers needs a new failure reason carrying them — which widens a taxonomy the Kotlin core mirrors and the conformance vectors cover. That is a contract decision, not a bug fix, and it should be made deliberately. Export does not exist at all.
