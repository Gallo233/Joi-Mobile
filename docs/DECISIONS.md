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
