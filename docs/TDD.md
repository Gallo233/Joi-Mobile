# Joi Mobile Technical Design Document

> Version: 1.0  
> Baseline date: 2026-08-11  
> Platform: iPhone / iOS 26+, Swift 6, SwiftUI  
> Status: Independent G0 Scheme Gate approved with named G1–G6 implementation, device, rights, and release conditions

## 1. Technical outcome and boundaries

Build a modular native iOS companion whose Chat and Map surfaces share identity, thread, speech arbitration, and explicitly allowed memory while keeping precise journey state separate. The first engineering slice is a deterministic app shell, frozen contracts, mock backend and three replaceable PoCs: native Live2D, native VRM/VRMA, and cached-route offline walking.

The first slice does not claim a complete AI product, complete Map, production account/sync/backend, broad renderer compatibility, arbitrary offline rerouting, or public-release readiness. Desktop Joi and legacy `aiguide-ios` remain read-only semantic references.

## 2. Layering and dependency direction

```text
JoiMobile app / composition root
├── ChatFeature ───────────────┐
├── MapFeature ── OfflinePack ─┼──> CompanionCore
├── CharacterRuntime ──────────┤
└── SyncClient ────────────────┘

Official Backend Proxy <── typed HTTPS/SSE ── ChatFeature/SyncClient
        │
        ├── model / speech / vision providers (server-side only)
        └── Valhalla-compatible routing adapter

Contracts/ JSON Schema + OpenAPI
        ├── generated/validated by iOS DTO fixtures
        ├── consumed by Backend
        └── adapted by desktop Joi; never coupled to its local sidecar transport
```

Dependency rules:

- `CompanionCore` contains versioned value types, state-owner actors, protocols and deterministic mocks; it imports no feature or vendor module.
- `CharacterRuntime`, `ChatFeature`, `OfflinePack` and `SyncClient` depend only on `CompanionCore` and platform APIs.
- `MapFeature` may depend on `CompanionCore` and `OfflinePack`; it never owns renderer, speech or sync truth.
- The app target is the composition root and the only place that chooses concrete adapters.
- Experimental/proprietary SDK types never cross a package's public boundary.
- Backend and iOS share schemas/examples, not source code or provider credentials.

## 3. State ownership and lifecycle

### 3.1 Unique mutable owners

| Owner | Sole authority | Must not own |
|---|---|---|
| `CompanionSessionStore` | current character ID, thread ID, accepted transcript ordering, primary-surface attachment identity | coordinate, route progress, audio session, renderer resources |
| `JourneyContextStore` | permissioned coordinate snapshot, accuracy/time, confirmed place, route/session/progress and ephemeral travel attachment | durable memory, transcript, provider calls, speech |
| `SpeechCoordinator` | cue generation, audio priority, interruption, synthesis/playback cancellation and stale-completion rejection | transcript acceptance, route truth, renderer truth, memory |

These are app-scoped instances injected through `AppContainer`; no feature creates a private copy or uses a global service locator. Switching `PrimarySurface` changes shell presentation only. It does not create a character/thread, end a route, write memory, or grant location attachment.

### 3.2 Cancellation and recovery

- Key every request, route session, speech cue and renderer load with stable IDs and a cancellation generation.
- Structured tasks belong to an owning store/service and cancel on explicit stop, supersession, deletion or shutdown—not merely because a SwiftUI child disappears.
- Ignore completions whose request/generation no longer matches current state.
- Make import, pack activation, sync cursor advance and tombstone acknowledgement atomic/idempotent.
- On restoration failure, keep the last validated record, quarantine corrupt data, and expose a typed recovery instead of silently resetting unrelated state.

### 3.3 Persistence

| Data | Initial store | Protection / retention |
|---|---|---|
| package manifests and immutable assets | Application Support, content-addressed directories | file protection; no user state inside package |
| conversation/thread metadata | local structured store behind repository protocol | per-character/thread; export/delete capable |
| layered memory | local structured store with category/provenance | category controls; protected/never-sync honored |
| active journey | ephemeral store plus resumable minimal checkpoint | exact samples not retained by default |
| travel packs | atomic version directories plus current pointer | hashes/signature/version/rights checked before activation |
| sync queue | durable cursor/outbox/tombstones | no upload without account and category consent |

### 3.4 Transcript, memory eligibility and speech priority

Input/output acceptance is explicit:

| State | Transcript | Speech/expression | Memory eligible |
|---|---|---|---|
| partial transcription | visible as editable draft only | never | never |
| user-accepted input | appended once with input/request ID | may start request phase expression | only through a later proposal |
| streamed draft output | replaceable event projection | never spoken as final | never |
| final accepted companion output | appended once after current-request terminal event | may create current speech cue | may generate an inspectable proposal, never direct write |
| cancelled/stale/failed output | diagnostic status only | cancel/reject generation | never |

`CompanionEventV1` carries `contentState = partial | acceptedInput | streamingDraft | acceptedFinal | cancelled | failed` and `memoryEligibility = none | proposalAllowed`. Unknown values do not become accepted or memory eligible.

| Speech cue priority | Preempts | Cancelled by | Surface switch |
|---|---|---|---|
| emergency/system interruption | all app speech | OS completion/user stop | app stays silent until revalidated |
| route maneuver | narration and conversation | newer maneuver, route stop, user mute/stop | continues foreground; visible in both surfaces |
| place narration | conversation | maneuver, newer narration, journey stop, user stop | continues if current and no maneuver |
| conversation | older conversation | new input/response, maneuver, character change, user stop | continues if current; switch alone does not cancel |
| preview/test voice | none above | any production cue or dismissal | cancels on leaving its preview |

Every cue contains session/thread or journey identity plus `SpeechGeneration`. Character changes cancel all character-bound cues. A transcript remains usable whenever audio fails.

## 4. Frozen public contracts

The following surfaces are frozen for the first slice. Breaking changes require versioning, affected Director review, consumer pause and new fixtures.

### 4.1 Data contracts

**`CharacterPackageManifestV1`**

- `schema = "joi.character.v1"`, package/character IDs, version, display names and locale overlays.
- presentation kind `static | live2d | vrm`; entry paths, portrait fallback and declared capabilities.
- voice, expressions, motions/VRMA, lip-sync, lore, author/license, hashes and provenance.
- no messages, memory, affinity, permissions, credentials, executables or runtime/sync state.
- initial ceilings: 128 MB archive, 512 MB expanded, 2,000 files.

**`ValidatedCharacterPackageHandle`**

- opaque, immutable and constructible only by the package installer after all security checks pass.
- contains an installation/content ID, immutable root capability (never a caller path), manifest version/hash, validation-receipt digest, compatibility receipt and validated portrait/bundled-fallback references.
- grants read access only to declared content under its root; consumers cannot substitute paths or mutate installed files.
- renderer loading accepts this handle, never an arbitrary decoded manifest or raw URL.

**`CompanionEventV1`**

- event/request/project/thread/session/character IDs, timestamp and public phase.
- phases: `idle`, `received`, `understanding`, `thinking`, `acting`, `waiting`, `paused`, `done`, `failed`.
- separates display card, voice-safe line, character presentation state, source projection and typed error.
- voice-safe content excludes coordinates, typed secrets/raw input, JSON, commands, paths, model/provider names, tokens, logs and internal IDs.

**`MemorySyncRecordV1`**

- record/category/character IDs, encrypted payload envelope, provenance, logical revision, device ID and timestamps.
- operation `upsert | tombstone`; cursor and deterministic conflict metadata.
- category consent is evaluated before enqueue and again before transmission; precise location/photos/tracks are not implicit categories.

**`MemoryRecordV1`, `MemoryProposalV1` and `MemoryRepository`**

- semantic categories: `profile`, `preference`, `relationship`, `travelRecap`, `preciseLocation`, `protectedNeverSync`; absence/unknown is rejected, never normalized to long-term.
- data classifications: `standard`, `sensitiveLocation`, `protectedNeverSync`. A `preciseLocation` record must use `sensitiveLocation`; a protected record cannot be downgraded.
- record includes character/thread scope, user-visible value, provenance (`userEntered`, `userApprovedProposal`, `importedWithConsent`), reason, created/updated time, retention, classification and sync eligibility.
- location-derived records additionally persist the user-visible precision, location-memory authorization digest/version and purpose provenance, but never place authorization receipts in analytics/logs.
- proposal lifecycle is `proposed → accepted | editedAndAccepted | rejected | expired`; only accepted values reach `MemoryRepository.save`.
- repository exposes list, save-with-authorization, delete, export and change stream. Protected records cannot enter a sync envelope.
- `preciseLocation` defaults to `syncEligibility = false` even after an authorized local save. Upload requires a separate `LocationSyncAuthorizationV1` plus independent category consent bound to the record/revision; general travel-recap sync never authorizes it.
- deleting a local record writes a tombstone only when that category was already consented for sync; disabling sync cannot resurrect it.

**`JourneyContextSnapshot`**

- journey/place/route/stop IDs, optional coordinate, accuracy, observation time, progress, confidence and source revision IDs.
- carries freshness and consent scope; defaults to ephemeral and cannot itself authorize memory or sync.
- Chat receives only a user-approved, payload-bound derivative; raw coordinates stay out of transcript/log/cache/analytics.

**`JourneyUseReceiptV1` and `LocationMemoryAuthorizationV1`**

- a journey-use receipt binds purpose `chatOneTurn`, payload digest, precision, issued/expiry time, thread/request IDs and explicit user-action provenance; it contains no raw coordinate and is revocable/one-use.
- `ChatRequest` construction and `JourneyUseReceiptStore.consume` fail closed on missing pairs, wrong purpose, identity/digest mismatch, not-yet-valid, expired, revoked or reused receipts; `ChatSessionController` consumes before calling `ChatGateway`.
- a location-memory authorization is a separate receipt binding the exact previewed memory payload, category, precision and retention. A journey-use receipt cannot authorize persistence.
- expired, revoked, reused, unknown-purpose, missing-retention or digest-mismatched receipts fail closed and produce no transcript/memory/sync/log payload.

**`LocationSyncAuthorizationV1`**

- separate from journey use and local memory save; binds record/revision digest, `preciseLocation` category, chosen precision, remote retention, account and explicit sync action.
- one category toggle may enable future prompts but cannot retroactively upload existing precise-location records without a matching per-record authorization.
- revoke/disable emits tombstones for already uploaded records and leaves local retention under the user's separate local-memory choice.

**`TravelPackManifestV1`**

- pack/route/version/locales, corridor/route/maneuver/stop resources and content-addressed file hashes.
- narration text/audio, source revisions, freshness/withdrawal, attribution and redistribution rights.
- minimum app/schema version, size, created/expires timestamps, signature metadata and optional precomputed rejoin connectors.
- a partial, corrupt, incompatible, expired/withdrawn or unlicensed pack never becomes current.

**`SourceProjectionV1`**

- claim/place IDs; identity confidence and claim-support confidence as separate fields; publisher, title, durable locator, source type, authority/verification and evidence span.
- revision, published/retrieved time, freshness, conflict group/status, correction/override, rights/attribution and withdrawal state.
- unknown authority/support/rights/withdrawal states fail closed for factual narration; character reflection remains explicitly non-factual.

**`ConsentReceiptV1`, `MediaUploadReceiptV1`, export and deletion contracts**

- consent binds user action, purpose, data category, processor class, payload digest, retention, issued/expiry time, revocation and contract version; absence/unknown purpose or retention rejects processing.
- media receipt records safe decode/re-encode, output type/size/hash, EXIF removal, processor, retention and deletion handle; microphone upload/transcription uses a separate disclosed purpose.
- `DataExportRequestV1/ResultV1` and `DataDeletionRequestV1/StatusV1` enumerate categories, local result, remote tombstone/acknowledgement, retry identity and completion evidence.
- deletion completion requires local verification plus remote acknowledgement for previously synced data; retries are idempotent and backups/log retention is disclosed by server policy.

**`CharacterPackageSyncRecordV1`**

- transports an immutable package content ID, manifest/hash set, encrypted asset reference or tombstone, revision/device/cursor metadata and category-consent proof.
- never embeds conversation, memory, affinity, permissions or runtime state. Conflicts retain both immutable versions until explicit character selection; tombstones prevent resurrection.

JSON Schema examples use strict `additionalProperties: false` at security boundaries and ISO-8601 UTC timestamps. Swift types use `Codable`, `Sendable`, stable string enums and typed IDs. Versioned decoders reject unsupported major versions; closed security decisions reject unknown values, while display-only enums preserve `unknown(rawValue)` for forward migration without treating it as success.

### 4.2 Swift service contracts

```swift
public protocol CharacterRenderer: Actor {
    nonisolated var kind: CharacterRendererKind { get }
    func load(_ package: ValidatedCharacterPackageHandle,
              generation: RendererGeneration) async -> CharacterLoadResult
    func apply(_ state: CharacterPresentationState,
               generation: RendererGeneration) async
    func stop(generation: RendererGeneration) async
    func release(generation: RendererGeneration) async
}

public actor SpeechCoordinator {
    public func begin(_ cue: SpeechCue) -> SpeechStartResult
    public func cancel(reason: SpeechCancellationReason)
    public func acceptsCompletion(for generation: SpeechGeneration) -> Bool
}

public protocol ChatGateway: Sendable {
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<CompanionEventV1, Error>
}

public protocol RoutePlanningProvider: Sendable {
    func plan(_ request: RouteRequest,
              availability: NavigationAvailability) async throws -> AcceptedNavigationRoute
}

public protocol NavigationProvider: Actor {
    func start(_ route: AcceptedNavigationRoute,
               session: NavigationSessionID,
               mode: NavigationAvailability) async throws
    func observe(_ location: LocationObservation,
                 session: NavigationSessionID) async -> NavigationObservation
    func stop(session: NavigationSessionID,
              reason: NavigationStopReason) async
}

public protocol SyncGateway: Sendable {
    func push(_ records: [SyncEnvelopeV1], after cursor: SyncCursor?) async throws -> SyncPage
    func pull(after cursor: SyncCursor?) async throws -> SyncPage
}
```

Renderer calls are serialized by actor isolation. `RendererGeneration` identifies one load lifetime; a new load invalidates the old generation, stale callbacks are ignored, `stop` is idempotent, and `release` frees CPU/GPU/SDK resources at most once while remaining safe on repeated calls.

`CharacterLoadResult` is a frozen renderer enum:

- `animated(capabilities, generation)` — all Tier A requirements pass.
- `degradedAnimated(capabilities, omissions, generation)` — only allowed Tier B omissions exist.
- `packagePortrait(reason)` — native animation unavailable; validated portrait decodes.
- `bundledStaticJoi(reason)` — portrait absent/invalid or package has no portrait.

Import/activation wraps this as `CharacterActivationResult = loaded(CharacterLoadResult) | rejectedImport(validationCode)`. `rejectedImport` is produced only by the installer before a handle exists and is unreachable from `CharacterRenderer.load`.

`NavigationAvailability` is `online` or `cachedRouteOnly`. Only `RoutePlanningProvider` computes a new route. In cached-only mode any planning request returns `NavigationError.newRouteUnavailableOffline`. `NavigationProvider` follows one accepted immutable route, emits candidate `NavigationObservation` values, supports explicit stop/cancel and cannot commit progress. `JourneyContextStore.reduce(observation:)` is the only authoritative route/session/progress write.

Public error enums freeze at least these cases:

- `PackageValidationError`: unsupportedVersion/type, pathTraversal, absolutePath, symlink/hardLink/deviceFile, executable, duplicateEntry, unicodeOrCaseCollision, nestedArchive, expansionLimit, file/count/sizeLimit, undeclaredFile, magicMismatch, malformedModel, hashMismatch, postInstallMutation, provenanceOrRightsUnknown.
- `CharacterRuntimeError`: runtimeUnavailable, unsupportedCapability, loadCancelled, staleGeneration, resourceFailure, portraitDecodeFailed.
- `ChatGatewayError`: offline, timeout, rateLimited, unauthorized, invalidEvent, streamInterrupted, cancelled, server(code).
- `NavigationError`: routeUnavailable, newRouteUnavailableOffline, invalidCachedRoute, staleSession, locationUnavailable, cancelled.
- `ConsentError`: absent, unknownPurpose, unknownRetention, expired, revoked, reused, payloadMismatch, precisionMismatch.
- `SyncError`: accountUnavailable, categoryDisabled, cursorInvalid, conflict, deletionPending, cancelled, server(code).

Every error exposes retryability and a stable user-facing recovery key without provider internals. Unsupported contract major versions fail migration; unknown security decisions fail closed. Mocks support delay, cancellation, error, duplicate/late event and stale-completion scenarios.

## 5. Swift packages and composition

| Package | Responsibility | Public dependency |
|---|---|---|
| `CompanionCore` | frozen contracts, stores, speech arbitration and deterministic mocks | Foundation/Observation only |
| `CharacterRuntime` | package preflight, static renderer, native Live2D/VRM adapters and capability report | CompanionCore |
| `ChatFeature` | thread orchestration, push-to-talk state, streaming reduction and memory proposals | CompanionCore |
| `MapFeature` | map/drawer journey state, place confirmation, camera handoff and navigation projection | CompanionCore, OfflinePack |
| `OfflinePack` | travel-pack verification/activation, immutable route projection candidates and cached narration | CompanionCore |
| `SyncClient` | category policy, outbox, cursors, conflicts and tombstones | CompanionCore |

`AppContainer` constructs one set of stores, mocks/adapters and feature models. App UI never creates a provider, URLSession, renderer, location manager, speech synthesizer or durable store directly.

`OfflinePack` and navigation adapters are pure observation producers. They may compute nearest segment, distance, bearing, candidate stop and candidate progress, but only `JourneyContextStore` validates session/generation/freshness and commits authoritative progress.

## 6. Character runtime PoCs

### 6.1 Live2D native adapter

- Use Cubism Native Framework through an owned Objective-C++/Swift bridge and Metal view/resource owner.
- Preflight `.model3.json` and every referenced moc/texture/motion/expression/physics/pose asset inside the validated package root.
- Prove multi-texture loading, Motion, Expression, Physics, Pose, gaze, audio-energy lip sync, cancellation and deterministic GPU/resource release.
- Do not bundle or redistribute SDK/model assets until terms allow it. Absence of the bridge produces a typed unavailable result and static fallback.

### 6.2 VRM native adapter

- Use RealityKit/Metal through an owned `VRMNativeBridge`; an experimental VRMKit implementation may conform privately but cannot leak types into product modules.
- Inspect GLB/glTF extensions before load and distinguish VRM 0.x, VRM 1.0 and VRMA.
- Compatibility evidence covers Humanoid, MToon, Expressions, LookAt, Constraints, Spring Bone, VRMA and audio-energy lip sync independently.
- Unsupported features yield a compatibility report and static fallback rather than partial silent success.

### 6.3 Compatibility and quality tiers

All animated tiers require safe package validation, native base rendering, correct multi-resource resolution, generation cancellation, idempotent release and visible/transcript controls. VoiceOver and Reduce Motion hooks remain in the design, but their full acceptance matrix is deferred. A declared capability that fails is not silently treated as absent.

| Format | Tier A required | Tier B allowed omission | Tier C trigger |
|---|---|---|---|
| Live2D Cubism | moc/model, all textures, declared Motion/Expression/Physics/Pose, gaze, lip sync, Metal lifecycle | an *undeclared* optional Motion/Expression/Physics/Pose group; base render/gaze/lip/release still pass | any declared asset/capability fails, runtime absent, generation/resource failure |
| VRM 0.x | Humanoid, MToon, Expressions, LookAt, declared Spring Bone, lip sync, lifecycle | undeclared Constraints/VRMA; all declared extensions pass | invalid humanoid/material/expression, declared extension failure or runtime/resource failure |
| VRM 1.0 | Humanoid, MToon, Expressions, LookAt, declared Constraints/Spring Bone, lip sync, lifecycle | undeclared VRMA only; all declared extensions pass | invalid core extension, declared constraint/spring/expression failure or runtime/resource failure |
| VRMA | compatible target humanoid, clip timing, retarget result, cancellation and release | nonessential metadata only | invalid target/clip, unsupported required channel, retarget/cancellation failure |

| Tier | Stable result | Launch behavior |
|---|---|---|
| A | `animated` | full native stage |
| B | `degradedAnimated` with explicit omissions | native stage plus compatibility note |
| C1 | `packagePortrait` | local validated portrait; Chat/Map/narration continue |
| C2 | `bundledStaticJoi` | used when portrait is absent or cannot decode; controls continue |
| Rejected | `CharacterActivationResult.rejectedImport` | installer-only result; no renderer call, install/activation/fallback rescue; previous character remains |

Fixture registry is part of the gate, not an informal sample folder:

| Fixture ID | Scope / expected result | Provenance and rights status |
|---|---|---|
| `L2D-MANIFEST-SELF-01` | self-authored multi-texture/model3 reference graph; preflight only | repository-authored metadata; no Cubism/model binary redistribution |
| `L2D-A-LICENSED-01` | all declared Live2D capabilities → Tier A | private test asset; hash, owner and Cubism/model permission receipt required before admission; never committed until cleared |
| `L2D-C-BROKEN-01` | declared motion/texture failure → C1/C2 | self-authored malformed metadata plus licensed portrait or bundled fallback |
| `VRM0-A-LEGAL-01` | VRM 0.x launch capabilities → Tier A | legal fixture URL/license/author/hash must be recorded before admission |
| `VRM1-A-LEGAL-01` | VRM 1.0 launch capabilities → Tier A | legal fixture URL/license/author/hash must be recorded before admission |
| `VRMA-A-LEGAL-01` | VRMA timing/retarget → Tier A | legal fixture URL/license/author/hash and target-model pairing required |
| `VRM-C-BROKEN-01` | malformed/unsupported declared extension → C1/C2 or Rejected per validation boundary | repository-authored malformed metadata; no third-party model payload |
| `PORTRAIT-SELF-01` | valid portrait then forced decode failure → C1 then C2 | repository-authored image plus licensed bundled static Joi |

Fixtures without a complete rights receipt can drive parser/mocked-bridge tests only and cannot close runtime or release gates. Live2D expandable approval remains G5 but does not block asset-free adapter scaffolding.

Before device evidence, deterministic local budgets are: 50 load/cancel/release cycles with zero accepted stale callback, zero live generation after release, exactly-once bridge release, cancellation acknowledgement ≤100 ms in the fake bridge, metadata preflight ≤250 ms for the fixed self-authored fixture, and static fallback that never removes Chat/Map/transcript/navigation controls. These are harness budgets, not public FPS/thermal claims.

Adaptive quality reacts to thermal/process/memory signals through renderer policy: reduce update rate and secondary physics, pause when hidden, honor Reduce Motion, then fall back statically. Only real-device measurement can set public thresholds or close ≥30 FPS/30-minute thermal gates.

## 7. Map, navigation and offline PoC

- Wrap MapLibre Native in `MapSurfaceProvider`; it renders online styles and verified downloaded corridor resources but never owns route truth.
- Wrap Ferrostar in `NavigationSessionAdapter`; it consumes a route and emits progress/maneuver/off-route events through `NavigationProvider`.
- Use an online backend route endpoint compatible with Valhalla request/response semantics. Provider changes remain server-side/adapted.
- Store a travel pack atomically and activate only after schema, version, hash/signature, rights and completeness checks.
- In flight mode, project accepted location observations onto cached route geometry, advance stops, and play cached narration/transcript.
- When off route offline, provide distance/bearing to the cached route or a pack-authored rejoin connector. Emit `newRouteUnavailableOffline`; never invent a new street route, maneuver or ETA.
- Keep driving out of in-app navigation and hand destination/intent to system maps.

The first deterministic PoC uses route/location fixtures and provider mocks. Actual MapLibre tile download, Ferrostar SDK integration, field GPS and airplane-mode walks remain explicit integration/device gates.

## 8. Official backend, transport and sync

### 8.1 API boundary

- HTTPS JSON endpoints live under versioned `/v1`; chat uses server-sent events with event IDs and terminal/error events.
- `POST /v1/chat/streams` accepts typed thread/character/locale data and an optional consent-scoped journey attachment.
- Upload endpoints use purpose, content type, size/hash and retention metadata; strip EXIF client-side before remote vision upload.
- `POST /v1/routes` accepts walking intent and returns a Valhalla-compatible normalized route.
- `/v1/sync/push` and `/v1/sync/pull` exchange cursor pages and tombstones.
- Provider keys, model names and raw tool traces stay server-side. Client errors expose stable codes, retryability and support correlation only.

### 8.2 Streaming and cancellation

SSE event IDs are monotonic per request. The client reducer accepts events only for the current request/thread. Cancelling closes the task; a late terminal event cannot append text, speak, animate or propose memory. Resume may use `Last-Event-ID` only when the backend contract proves idempotence.

### 8.3 Sync

No account means no sync queue transmission. After sign-in, each character-package and memory category has independent consent. Push is idempotent by record/revision/device; pull advances a cursor only after atomic local apply. Tombstones outrank older updates and persist until server acknowledgement. Unknown retention/category fails closed, especially for location-derived data.

### 8.4 Privacy runtime decisions

- The first slice and P0 architecture do **not** enable background location. Entering background stops location collection and stores only route/stop/session IDs—not a coordinate/track. Foreground resume reacquires permission/freshness and revalidates progress. Any future active-route background mode requires a new product/safety decision, entitlement, disclosure and device evidence.
- Account refresh/access tokens live in Keychain with this-app access group, device-only accessibility where compatible, rotation/revocation and no backup/export/logging. Sign-out clears tokens and stops network sync without resurrecting deleted local data.
- Analytics use a versioned allowlist: event name, coarse result bucket, app/schema version, renderer tier, locale and pseudonymous rotating install ID. Raw coordinates/tracks, media/audio, prompts/responses, memory values, filenames, package payloads and stable account/character identity are forbidden.
- Disable category → delete → reinstall → conflict replay tests must prove tombstones and server acknowledgement prevent resurrection. Identifier rotation must break longitudinal linkage without losing deletion status.
- Photos are safely decoded and re-encoded to an allowlisted raster type/size before upload; merely deleting EXIF fields is insufficient. Microphone capture/transcription displays whether processing is local or remote and uses a separate receipt/retention choice.
- The backend contract publishes processor classes plus primary-store, diagnostic-log and backup retention/deletion windows. A client must not show “complete deletion” until required acknowledgement arrives.

## 9. Character package security and isolation

1. Copy user input into an isolated staging directory without following links.
2. Normalize each entry to NFC plus case-folded comparison and reject traversal/absolute paths, duplicate/colliding names, symlinks, hard links, device files and executable bits/types before extraction.
3. Reject nested archives and enforce streaming ceilings: 128 MB archive, 512 MB expanded, 2,000 files and maximum 20:1 aggregate expansion ratio. Stop before writing beyond a limit.
4. Require extension **and** magic/content agreement using an allowlist for JSON, GLB/VRM, PNG/JPEG/WebP, audio and declared Cubism resources. Unknown/active content is rejected.
5. Parse strict schema/version/type; raw VRM or Live2D ZIP is wrapped locally only after equivalent checks. Malformed JSON/GLB/model graphs fail before any vendor runtime call.
6. Resolve every declared reference through the immutable root capability; require hashes and reject undeclared content. Self-declared hashes prove integrity, not publisher authenticity, so provenance/signature/rights remain separate fields and gates.
7. Inspect provenance/license and produce validation plus compatibility receipts before runtime load.
8. Atomically move content-addressed read-only assets into installation storage, re-open and verify root identity/hash after move, and reject post-install mutation before each activation.
9. Keep package state separate from conversation/memory/permissions/affinity/sync/runtime state. On failure, remove staging safely, retain the active character and emit a non-sensitive typed reason.

Archive and expanded byte counting occurs while streaming, before full extraction. Logs include rule/code and package ID only—never file payload, coordinates, secrets or user content.

## 10. Language, knowledge, cache and speech

- Carry three independent values: display locale, content/knowledge locale and character voice locale.
- The current implementation lane is `zh-Hans`. Visible shell and permission copy lives in the editable String Catalog; additional locales are not current acceptance evidence.
- Cache keys include normalized locale, source/content revision, place ID, route/pack version and relevant renderer/voice variant—not raw prompts or coordinates.
- Factual segments reference immutable source revisions with publisher, authority, support, confidence, freshness, conflict, rights and correction state.
- Cached narration declares version/freshness and is invalidated by withdrawal/rights expiry.
- Speech cues carry display and voice locale separately. System TTS or bundled authorized audio remains the offline fallback; transcript is always available.

BCP-47 tags are canonicalized before lookup. Current UI strings require `zh-Hans` keys. The contract still carries requested and resolved display/content/voice locale separately, so later locale additions do not change request or cache interfaces. Future content/package overlays resolve `exact requested locale → declared package/content default when supported → unavailable`; Chinese scripts must never silently substitute for each other. TTS fallback remains labeled, and cache keys contain both requested and resolved locale.

Human G2/G5/G6 review currently covers cultural framing, local names, claim support, conflict display, corrections, attribution/rights and spoken quality in `zh-Hans`. Other languages and full accessibility/long-text review are separate later milestones. Correction fixtures apply an immediate local/session override while clearly keeping remote acknowledgement pending.

## 11. Verification matrix

### 11.1 Reproducible toolchain and dependency freeze

| Item | Frozen first-slice value | Enforcement |
|---|---|---|
| Xcode | 26.6, build 17F113 | `xcodebuild -version`; CI/local mismatch fails G1 |
| Swift | compiler 6.3.3, language mode Swift 6 | `swift --version` and strict-concurrency build |
| XcodeGen | 2.46.0 from Homebrew | `.xcodegen-version`, `Brewfile`, `options.minimumXcodeGenVersion`, `xcodegen --version` |
| generated project | not committed; `project.yml` is source | `.gitignore`; two clean temp generations must have identical normalized tree/hash |
| SPM lock | exact `Package.resolved` committed once any remote package is admitted | no floating branch/HEAD; update requires Technical + Quality review |

The asset-free first slice admits **no external runtime Swift package**. Live2D, VRMKit, MapLibre and Ferrostar remain private adapter seams or compile-time-unavailable stubs until a separate dependency/rights gate freezes an exact release or commit. Valhalla is a server contract candidate, not an iOS dependency. This prevents a PoC import from masquerading as compatibility proof.

| Candidate / asset | First-slice status | License/notice/data gate before admission |
|---|---|---|
| Cubism Native Framework / Live2D fixtures | not bundled | proprietary SDK notices, model rights, Expandable Application approval/agreement |
| VRMKit or replacement / VRM/VRMA fixtures | not linked | exact version/commit, package license, model/animation author-license-hash receipt |
| MapLibre Native | not linked | exact release, BSD notice, style/font/tile providers and offline redistribution rights |
| Ferrostar | not linked | exact release, BSD notice, API-stability review and route-provider contract |
| Valhalla / OSM-derived data | server mock only | exact service/engine version, ODbL attribution, tile/build/update and redistribution policy |
| bundled static Joi, portraits, narration/audio/content | placeholders only | creator/license/provenance/hash, locale rights and withdrawal process |

Before G6, the release checklist includes dependency/advisory scan, consolidated notices/attribution, privacy manifest, permission strings, entitlements/background modes, App Store privacy declaration, rollback/incident/support runbooks and fixture/data rights receipts.

### 11.2 Public device and G4 protocol

Apple's [iOS 26 compatibility list](https://support.apple.com/en-au/guide/iphone/iphe3fa5df43/26/ios/26) includes iPhone 11/SE (2nd generation) through current iPhone 17-class models. The required physical matrix is:

| Role | Device | Required coverage |
|---|---|---|
| lowest memory/small screen | iPhone SE (2nd generation) | launch, Chat/Map layout, static fallback, import/offline recovery |
| minimum Face ID baseline | iPhone 11 | sustained native character + route script |
| compact | iPhone 13 mini | drawer/map/stage coexistence and audio/location; Dynamic Type validation deferred |
| modern baseline | iPhone 15 | all hero journeys and camera/audio/navigation |
| current performance ceiling | iPhone 17 Pro | full-quality renderer and compatibility comparison |

Run Release configuration, current iOS 26.x, Low Power Mode off, 80–100% starting battery, unplugged, case removed, 20–25°C ambient target and 10-minute idle normalization. Record deviations. Use Instruments/signposts and MetricKit where applicable.

G4 scripts:

1. 50 cold/warm renderer load/cancel/release cycles per legal fixture; record peak/residual memory, crash, stale callback and fallback.
2. 30-minute foreground cultural walk with GPS, cached route, character, five narration cues, one Chat/Map switch per five minutes and one forced off-route/rejoin; require at least 95% of active-stage frames at or above 30 FPS, no continuous sub-30-FPS interval over two seconds, and no serious/critical thermal state lasting over 60 seconds.
3. Airplane-mode downloaded tour from integrity check to recap; assert no new-route/maneuver/ETA event.
4. Call, Siri, headset/Bluetooth loss, silent mode, route-priority cue, microphone capture, camera, background/foreground and permission revoke/resume scripts.
5. Low-storage import/pack/export failure with atomic rollback; delete/disable/reinstall/conflict replay with no data resurrection.

Background location is not enabled; the background step must prove collection stops and foreground resume revalidates. Results are recorded per device/OS/build/fixture. Any untested device role keeps G4 open.

| Lane | Required evidence | Simulator/local | Real device/field/release |
|---|---|---|---|
| Unit | stores, reducers, generation cancellation, route projection, validators, conflict rules | required | — |
| Contract | JSON Schema examples, Codable round trips, OpenAPI examples, desktop-compatible fixtures | required | — |
| Integration | Chat/Map switch, mock SSE, static fallback, offline route/cues, sync tombstones | required | selected device smoke |
| UI/content | first run, two surfaces, permissions/recovery and editable `zh-Hans` copy | deterministic/UI tests | additional-language and full accessibility review deferred |
| Security/privacy | malicious archives, secrets scan, EXIF removal, zero-write location handoff, delete/export | required | Files/Photos/permission behavior and log inspection |
| Fuzz/atomic recovery | malformed JSON/GLB/images/archives, duplicate/collision/nested/expansion cases, low storage and interrupted activation | deterministic corpus and crash-free parser harness | Files import and storage-pressure drill |
| Performance | load/release loops, memory budget hooks, cancellation latency | indicative only | supported-device FPS, memory, 30-minute thermal/energy |
| Navigation | GPX drift/off-route/no-network fixtures, no arbitrary-reroute event | required | outdoor walk, GPS accuracy, background/resume, airplane mode |
| Audio/camera | stale speech and mock interruption/recognition | partial | microphone, call/Siri/headset/Bluetooth/silent/background/camera |
| Release | clean-checkout deterministic XcodeGen, builds/tests, dependency advisory/secret scan, license/notice/data-right inventory, privacy manifest and rollback | required | signing/store privacy copy/incident drill/rights/Director closeouts |

The first slice is complete when traceability, XcodeGen generation, generic simulator build, package tests, state-ownership tests, backend mock tests and three PoC fixture lanes pass. It must still label all device/field/license claims pending.

## 12. PRD Traceability

| ID | Requirement | Module | Interface / contract | Test evidence | Release gate |
|---|---|---|---|---|---|
| JM-P0-001 | Two-surface shell | App, CompanionCore | `CompanionSessionStore`, `PrimarySurface` | `SurfaceContinuityTests` | G1/G2 |
| JM-P0-002 | Local-first first run | App, CharacterRuntime | `AppContainer`, package importer | `LocalFirstOnboardingTests` | G2 |
| JM-P0-003 | Full Chat stage | ChatFeature, CharacterRuntime | `ChatGateway`, `CharacterRenderer` | `ChatStageStateTests` | G2/G4 |
| JM-P0-004 | Official AI boundary | ChatFeature, Backend | OpenAPI `/v1/chat/streams` | `MockSSEContractTests`, secret scan | G1/G3 |
| JM-P0-005 | Layered local memory | CompanionCore, SyncClient | memory repository, `MemorySyncRecordV1` | `MemoryProposalAndDeletionTests` | G3 |
| JM-P0-006 | Cross-surface continuity | CompanionCore, App | `CompanionSessionStore`, `JourneyContextSnapshot` | `ContextIsolationTests` | G1/G3 |
| JM-P0-007 | Speech coordination | CompanionCore | `SpeechCoordinator` | `SpeechGenerationTests` | G2/G4 |
| JM-P0-008 | Persistent Map experience | MapFeature, App | `JourneyContextStore`, drawer state | `MapShellStateTests` | G2/G4 |
| JM-P0-009 | Arrive-and-tell | MapFeature | place resolver, `JourneyContextSnapshot` | `PlaceConfirmationTests`, GPS field script | G2/G4 |
| JM-P0-010 | See-and-ask | MapFeature, Backend | vision upload contract | `RecognitionStalenessTests`, camera script | G3/G4 |
| JM-P0-011 | Cultural walking navigation | MapFeature, Backend | `NavigationProvider`, route API | `NavigationSessionTests`, outdoor walk | G2/G4 |
| JM-P0-012 | Routes-as-narrative | MapFeature, OfflinePack | `TravelPackManifestV1`, narrative state | `NarrativeProgressTests` | G2 |
| JM-P0-013 | Trusted sources | CompanionCore, MapFeature | source projection in `CompanionEventV1` | `SourceEligibilityTests` | G2/G3 |
| JM-P0-014 | Offline travel pack | OfflinePack, MapFeature | `TravelPackManifestV1`, cached navigation | `OfflineRouteProgressTests`, flight-mode walk | G2/G4/G5 |
| JM-P0-015 | Character library/import | CharacterRuntime, App | `CharacterPackageManifestV1` | `CharacterImportTests` | G2/G3/G5 |
| JM-P0-016 | Native renderer parity | CharacterRuntime | `CharacterRenderer`, compatibility receipt | `Live2DAdapterTests`, `VRMAdapterTests`, device matrix | G4/G5 |
| JM-P0-017 | Package isolation/safety | CharacterRuntime, Contracts | package schema and validator | `MaliciousPackageFixtureTests` | G1/G3 |
| JM-P0-018 | Secondary controls | App, SyncClient | settings routes, repositories | `SecondaryNavigationTests` | G2 |
| JM-P0-019 | Optional category sync | SyncClient, Backend | `SyncGateway`, `MemorySyncRecordV1`, `CharacterPackageSyncRecordV1`, `LocationSyncAuthorizationV1` | `CursorConflictTombstoneTests`, `PreciseLocationSyncIsolationTests` | G3 |
| JM-P0-020 | Editable Simplified-Chinese copy | App, all features, Backend | String Catalog, locale context and cache-key contract | `ChineseCopyCatalogTests` | G1/G2 |
| JM-P0-021 | Deferred experience hooks | App, all UI features | semantic labels, system text styles and motion-policy seams | shell hook smoke tests; full matrix deferred | G1 / later accessibility gate |
| JM-P0-022 | Failure/recovery contract | all modules | typed error/state enums | `NamedFailureFixtureTests` | G2/G3 |
| JM-P0-023 | Data-purpose governance | App, Backend, SyncClient | consent/media receipts, export and deletion request/status contracts | `PurposeAndDeletionTests`, `ExportDeletionAcknowledgementTests` | G3/G6 |
| JM-P0-024 | Privacy-safe quality metrics | App, Backend | analytics allowlist | `AnalyticsRedactionTests` | G3/G6 |

## 13. Scheme Gate decisions after G0 rework

| Director | Decision | Basis | Condition, owner and closure gate |
|---|---|---|---|
| Product Design | approved-with-conditions | Map→Chat consent, transitions and all 32 failure fixture/cancellation rules close prior rework | prove `zh-Hans` journey fixtures at G2; additional languages/accessibility are later milestones; Product Journey + Field QA |
| Technical | approved-with-conditions | validated handles, actor/generation renderer, explicit planning/following, unique progress reducer and errors close prior rework | implement schemas/types before consumers and pass contract/state/offline tests at G1; Technical integrator |
| AI & Companion | approved-with-conditions | local memory/proposal, precise-location classification/authorization, transcript and speech rules close prior rework | pass no-upload/no-resurrection/provider/cancellation tests at G1/G3; Mobile AI + Memory leads |
| Art & Character | approved-with-conditions | capability/fixture/rights/result/fallback/lifecycle matrices close prior rework | rights-receipted fixtures only; local tests G1, real-device G4 and licensing/rights G5; Character Runtime lead |
| Content & Trust | approved-with-conditions | source revision/conflict/freshness, editable `zh-Hans` copy and future-ready locale/cache keys are explicit | complete Chinese source/rights/copy fixtures at G2/G5; additional locales later; Localization & Knowledge lead |
| Trust & Safety | approved-with-conditions | consent/media/export/delete/package-sync, foreground-only location, auth/analytics/resurrection and archive rules close prior rework | implement encrypted-key/re-auth details before real sync and pass G3 safety/deletion tests; veto remains |
| Quality & Release | approved-with-conditions | exact pins, no-external-dependency slice, device protocol and clean/fuzz/release lanes close prior rework | install/verify XcodeGen and pass G1; device G4, rights G5, privacy/release G6; veto remains |
| Studio | approved-with-conditions | every independent G0 re-review returned without rework/blocked and ownership/contracts are explicit | begin frozen-contract skeleton and asset-free PoCs only; production/vendor/public-release actions remain out of scope |

No condition above authorizes public release or permits a simulator result to close a device, field, thermal, energy, camera, audio, GPS, background, license or data-right gate.
