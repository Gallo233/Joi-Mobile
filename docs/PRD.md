# Joi Mobile Product Requirements Document

> Version: 1.0
>
> Baseline date: 2026-08-11
>
> Platform: iPhone, iOS 26+, Swift 6, SwiftUI
>
> Status: Product scheme `approved-with-conditions`; implementation and public release remain gated
>
> Product owner: Product Design Director

## 1. Product outcome

### 1.1 Positioning

**Joi Mobile is the iPhone home of a user-owned character companion: Chat provides the full relationship stage, while Map lets the same companion understand and narrate a real journey.**

The product has exactly two primary surfaces:

- **Chat** is the everyday home: character stage, text conversation, push-to-talk, speech playback and inspectable local memory.
- **Map** is the mobile travel capability: arrive-and-tell, see-and-ask, cultural walking navigation, routes-as-narrative and trusted sources.

Character companionship is the product identity. Map is not a separate generic map product, and Chat is not a disconnected generic chatbot. The same current character and conversation thread survive switching between the two surfaces. Precise travel context remains separately governed and is attached to Chat only after explicit user action.

### 1.2 Launch users

| Priority | User | Launch need | Why Joi Mobile |
|---|---|---|---|
| Primary | Existing desktop Joi user | Bring a trusted character package and relationship onto iPhone | Compatibility with `.joi-character` and continuity without requiring an account |
| Primary | Character-companion enthusiast who travels | Talk naturally at home, then take the same character on a walk | One character identity across a full stage and a context-aware map |
| Secondary | Independent cultural traveler | Understand places without reading long guides or trusting unsupported claims | Audio-first narration, camera questions, route context, correction and sources |
| Future | Cross-language traveler | Hear local culture in a familiar language while retaining local names | Additional human-reviewed UI/content/TTS locales after the Chinese lane is stable |

The public launch is not directed at children. Child-specific safety, parental consent and age-assurance requirements require a separate product decision.

### 1.3 Jobs to be done

- When I have a few minutes, let me meet my character in a visually complete stage and continue the same conversation by text or voice.
- When Joi proposes remembering something, let me understand, edit, reject or delete it instead of silently building a hidden profile.
- When I leave for a cultural walk, let the same character move with me into Map without losing the active thread.
- When I reach or photograph a place, tell me what it is, why it matters and how certain the answer is.
- When I follow a downloaded tour without network, keep the known route, narration and recovery usable without pretending arbitrary rerouting works.
- When I import a character, preserve its intended appearance and persona while keeping its files isolated from my messages, memory, permissions and credentials.

## 2. Product principles

1. **One companion, two surfaces.** Chat and Map share companion continuity; secondary tools never become additional primary tabs.
2. **Local useful by default.** Character use, local memory controls, downloaded travel packs and core browsing do not require an account.
3. **Consent before context.** Location, photos, microphone input, memory and sync are separate choices; permission to perform one action is not permission to retain it.
4. **Identity before narration.** Map confirms a place or shows ambiguity before delivering factual narration.
5. **Sources before certainty.** Place identity, source authority, evidence support, freshness and conflict remain distinct.
6. **Characters present state; they do not own truth.** A renderer or expression cannot decide location, memory, source status or network success.
7. **Native and degradable.** Live2D and VRM render natively behind one product boundary; static presentation remains a supported fallback.
8. **Audio-first, screen-safe.** Speech reduces screen attention, but every essential status and action has a visible and accessible equivalent.
9. **Offline claims stay narrow.** A downloaded tour completes its known route; arbitrary offline route computation is not implied.
10. **Compatibility is measured, not advertised broadly.** Character support is published through tested fixture matrices and explicit exceptions.

## 3. Information architecture

### 3.1 Primary and secondary destinations

| Level | Destination | Responsibilities |
|---|---|---|
| Primary | Chat | Full character stage, active thread, text composer, push-to-talk, speech controls, memory proposal and travel handoff |
| Primary | Map | Persistent map, contextual drawer, place confirmation, narration, cultural walking route, camera question, sources and offline status |
| Secondary | Character Library | Current character, import, preview, compatibility report, switch, remove and asset/license details |
| Secondary | Settings | Simplified-Chinese copy entry, future language/accessibility entry points, voice, appearance, downloads, memory, account/sync, privacy, export/delete and diagnostics |
| Secondary | Account | Optional sign-in and category-level sync consent; never required to begin locally |

Chat and Map use one persistent two-item switcher. Character Library opens from the character affordance; Settings and Account open from the profile/control affordance. Downloads are reachable from Map and Settings but are not a third primary surface.

### 3.2 First run

1. **Welcome:** the current slice uses editable `zh-Hans` copy. A later Settings entry will add language selection; no multi-language completeness is claimed now.
2. **Local-first choice:** continue without an account by default; optional sign-in is visibly secondary.
3. **Choose a character:** use a bundled starter character or import a package. Import shows validation, rights/provenance and fallback before installation.
4. **Chat introduction:** enter the stage and send a text message. Microphone permission is requested only when push-to-talk is first used.
5. **Memory explanation:** explain ephemeral conversation context and optional long-term categories; all durable categories begin with inspectable controls.
6. **Map introduction:** location is requested only when the user first opens a location-dependent Map action. Camera and photo permissions are likewise just-in-time.

First run is complete once a character is visible and the user can send a text message. Account, microphone, location, camera and photo access are not completion requirements.

## 4. Six hero journeys

### Journey 1 — Bring my desktop character to iPhone

**Start:** A desktop Joi user opens Character Library during first run or later.

**Flow:** Select `.joi-character` → local archive validation → preview identity, renderer type, included assets, provenance and license → install → render Live2D or VRM natively → use static fallback if the model cannot safely render → make current without importing memory or history.

**Recovery:** Rejected packages retain no executable/runtime state and show the exact failed rule; unsupported-but-safe assets can install only when a trustworthy static fallback exists.

**Success:** The character becomes current in Chat and appears in lightweight form in Map; conversation and memory remain independent of the package.

### Journey 2 — Continue an everyday conversation

**Start:** The user opens Chat.

**Flow:** Stage restores the current character and thread → user types or holds push-to-talk → partial and final input are visibly distinguished → backend response streams → speech and character expression follow the accepted response → user interrupts or stops speech without stale audio resuming.

**Recovery:** If the model, network, microphone, transcription, TTS or renderer fails, typed local controls and the thread remain usable; unavailable operations are never shown as successful.

**Success:** The user completes a coherent exchange and can inspect what, if anything, was proposed for durable memory.

### Journey 3 — Turn a conversation into a trip

**Start:** The active conversation contains a place or walking intent.

**Flow:** Joi offers an explicit “Open in Map” action → user inspects the place/intent being transferred → Map opens with the same character and thread identity → search resolves ambiguity → user selects a cultural route or destination.

**Recovery:** Cancelling the handoff leaves Chat unchanged; an ambiguous or unavailable destination opens search rather than manufacturing a route.

**Return flow:** In Map, “Ask in Chat” first shows a one-turn preview containing the confirmed place/route fact, precision and expiry. The user can send, edit, cancel or revoke it. Sending authorizes only that payload for the current turn; saving it to memory is a separate preview and confirmation. Returning to Chat without this action transfers no location.

**Success:** Map receives only the approved travel intent. Chat receives only a separately approved one-turn journey attachment. Ongoing precise location is not added to the transcript, analytics, sync or long-term memory.

### Journey 4 — Walk with arrive-and-tell

**Start:** The user starts a cultural walking route or explores nearby.

**Flow:** Map stays persistent → location and route progress propose a place → high-confidence results show a clear confirmation state; ambiguous results show candidates → user confirms/corrects → Joi narrates without covering essential navigation → source and freshness are available → route advances.

**Recovery:** Location denial permits manual search; drift does not auto-confirm; driving requests hand off to system maps; speech failure leaves text and route controls available.

**Success:** A confirmed, source-eligible narration is engaged and the user can continue to the next stop.

### Journey 5 — See an object and ask about it

**Start:** The user taps the camera action in Map.

**Flow:** Just-in-time consent → capture or photo selection → local preprocessing and metadata removal → explicit upload consent when remote recognition is needed → top candidates and confidence → user confirms → asks follow-ups in the same journey context → opens sources or corrects the identity.

**Recovery:** Camera denial offers photo/manual search; low confidence requires choice; unsupported or failed recognition does not alter the confirmed place.

**Success:** The confirmed visual identity becomes the current Map subject while the original photo follows the chosen retention policy.

### Journey 6 — Finish a downloaded route offline and remember it deliberately

**Start:** The user opens a previously verified travel pack without network.

**Flow:** Integrity check → cached map/route/content opens → progress advances along the known route → off-route state gives bearing/distance guidance back to the route → cached narration displays source version and freshness → trip recap is generated locally from completed stops → user chooses whether to save selected recap facts to memory.

**Recovery:** Missing or invalid pack content identifies what is unavailable; arbitrary rerouting is not offered; the user can stop navigation, return manually or retry after network recovery.

**Success:** The known tour is completable offline, and no travel detail becomes long-term memory without an explicit save.

## 5. Launch requirements

Each P0 identifier below is a single stable requirement definition. The TDD must trace every one to a module, interface, automated or manual test, and release gate.

### 5.1 P0 — Required for public launch

| ID | Requirement and observable acceptance |
|---|---|
| JM-P0-001 | **Two-surface shell:** expose exactly Chat and Map as primary destinations; switching preserves the current character, active thread, draft, playback ownership and active journey where compatible, while Character Library, Settings, Downloads and Account remain secondary. |
| JM-P0-002 | **Local-first first run:** a new user can use the current Simplified-Chinese experience, choose a bundled or imported character, enter Chat and send text without creating an account or granting microphone, location, camera or photo access. |
| JM-P0-003 | **Full Chat stage:** Chat presents the current static, Live2D or VRM character with text chat, push-to-talk, streaming response status, stop/interruption controls, expression/lip-sync presentation and a readable transcript. Continuous hands-free realtime voice is not required. |
| JM-P0-004 | **Official AI boundary:** chat, transcription/vision where remote, narration and speech model requests use a typed official backend proxy with cancellation, stable user-visible errors and provider-independent fallback; no provider secret may exist in the app, packages, repository, fixtures or logs. |
| JM-P0-005 | **Layered local memory:** distinguish ephemeral thread context, user-approved profile/preferences, companion relationship notes and travel memories; every durable item records category and provenance and can be viewed, edited, rejected, exported or deleted. No model-generated proposal becomes durable silently. |
| JM-P0-006 | **Cross-surface continuity:** one companion session owns current character and thread identity across Chat and Map; precise place/route context has a separate journey owner and enters Chat only through an explicit, inspectable handoff that can be revoked. |
| JM-P0-007 | **Speech coordination:** only one speech owner plays at a time; new input, user stop, route-priority guidance, surface change and superseding responses cancel stale synthesis/playback; interruption never commits unaccepted transcript or memory, and text controls remain available. |
| JM-P0-008 | **Persistent Map experience:** Map remains visible beneath a contextual drawer and uses a lightweight, non-blocking character surface for narration and short questions; character presentation cannot obscure the next maneuver, location ambiguity, source status or primary recovery action. |
| JM-P0-009 | **Arrive-and-tell:** combine current permissioned location, accuracy, route progress and user input to propose a place; require confirmation for ambiguous/low-confidence identity, allow correction at any time, then provide text/audio narration with honest online or cached status. |
| JM-P0-010 | **See-and-ask:** support camera and photo input, local minimization, explicit remote-upload disclosure, multiple candidates, confidence/ambiguity, user confirmation, correction and contextual follow-up without overwriting a newer confirmed subject. |
| JM-P0-011 | **Cultural walking navigation:** provide in-app route preview, start/stop, maneuver/progress state, off-route detection and online rerouting for supported walking routes; driving requests hand off to system maps, and no in-app driving navigation claim is made. |
| JM-P0-012 | **Routes-as-narrative:** organize verified stops into an ordered cultural story with duration/pacing, completion state, next stop, pause/resume and a recap that distinguishes sourced facts from the character's reflective language. |
| JM-P0-013 | **Trusted sources:** factual Map narration and factual location-aware Chat answers expose place identity, source/publisher, authority/verification, evidence support, confidence, freshness/version, conflict and correction; unsupported claims abstain or are clearly non-factual rather than carrying fabricated citations. |
| JM-P0-014 | **Offline travel pack:** a downloaded, versioned and integrity-checked pack contains the assets required to complete its known tour without network, including route geometry, maneuvers, stop identity, narration, source projection and required map resources; offline recovery may guide back to the cached route but cannot promise arbitrary new-route computation. |
| JM-P0-015 | **Character library and import:** preview, validate, install, select and remove `.joi-character`; accept raw `.vrm` and Live2D ZIP only by wrapping locally into the same validated package semantics; show renderer compatibility, provenance/license and fallback before activation. |
| JM-P0-016 | **Native renderer parity:** place native Live2D and native VRM 0.x/1.0 plus tested VRMA behavior behind a stable `CharacterRenderer` experience boundary, with published compatibility tiers, a reserved motion-policy hook, deterministic resource release and a static fallback; Unity, WKWebView and Three.js runtime fallbacks are prohibited. |
| JM-P0-017 | **Package isolation and supply-chain safety:** validate manifest version, hashes, declared file types, paths, archive expansion and provenance; reject traversal, symlinks, executables and undeclared content; initial ceilings are 128 MB archive, 512 MB unpacked and 2,000 files, and packages cannot contain secrets, messages, memory, affinity, permissions or sync/runtime state. |
| JM-P0-018 | **Secondary controls:** Settings provides editable Simplified-Chinese copy plus reserved future language/accessibility entries, voice, appearance, downloads, memory, account/sync, privacy, export/delete and diagnostics; Character Library remains directly reachable from character affordances without adding a third primary tab. |
| JM-P0-019 | **Optional category sync:** local-only operation remains complete; signed-in users separately opt into character packages and each memory category, can inspect sync state, resolve deterministic conflicts, disable categories, export/delete data and propagate deletion tombstones without silently enabling travel history, photos or precise location sync. |
| JM-P0-020 | **Editable Simplified-Chinese copy contract:** current visible shell copy and permission rationale use `zh-Hans` and live in String Catalog/source contracts rather than being scattered provider text; display/content/voice locale fields remain separate so later languages do not require an API rewrite. |
| JM-P0-021 | **Deferred experience hooks:** keep semantic labels, system text styles, motion-policy hooks and centralized copy keys in the shell, but treat full VoiceOver, Dynamic Type, Reduce Motion, long-text and additional-language validation as later work rather than current acceptance evidence. |
| JM-P0-022 | **Failure and recovery contract:** every named state in Section 7 has a deterministic entry condition, non-destructive user explanation, primary recovery, cancellation semantics and test fixture; an unavailable backend, permission, runtime, pack or sensor is never rendered as success. |
| JM-P0-023 | **Data-purpose governance:** request location, camera, photos and microphone just in time; minimize precision/duration, strip image metadata before upload, disclose remote processing, apply explicit retention choices, keep protected categories out of analytics, and provide complete local and synchronized export/deletion evidence. |
| JM-P0-024 | **Privacy-preserving quality measurement:** instrument first run, conversation completion, speech interruption, character fallback, place confirmation/correction, source eligibility, route/offline completion and failure recovery using pseudonymous events without raw precise GPS, photos, audio, full prompts, full responses or memory content. |

### 5.2 P1 — Expansion after launch evidence

| ID | Requirement |
|---|---|
| JM-P1-001 | Add continuous realtime voice only after push-to-talk interruption, privacy, latency, cost and battery gates pass. |
| JM-P1-002 | Expand the tested VRM/VRMA and Live2D motion/expression/physics matrix, model diagnostics and quality tiers without weakening static fallback. |
| JM-P1-003 | Add incremental/delta travel-pack updates, regional pack discovery and content withdrawal while preserving atomic activation and rollback. |
| JM-P1-004 | Expand from launch sample routes to more cities, museums and indoor cultural routes with local content review and five-language quality gates. |
| JM-P1-005 | Add richer opt-in cross-device relationship continuity after sync conflict, deletion and protected-memory audits pass. |
| JM-P1-006 | Add `zh-Hant`, `en`, `ja` and `ko` only after editable `zh-Hans` copy, content and cache/voice contracts are stable; require human review per added locale. |
| JM-P1-007 | Complete VoiceOver, Dynamic Type, Reduce Motion, contrast, long-text and sound/motion-equivalent journey validation in a dedicated accessibility milestone. |

### 5.3 P2 — Candidates requiring separate approval

| ID | Requirement |
|---|---|
| JM-P2-001 | Consider a curated character/content catalog only with package review, rights, reporting, revocation and age/safety policy; an open unmoderated marketplace is not implied. |
| JM-P2-002 | Consider additional Apple platforms only after iPhone state ownership, renderer performance and accessibility are stable. |
| JM-P2-003 | Consider creator and cultural-institution publishing tools only after source revision, rights expiry, withdrawal and localization operations are proven. |

## 6. Detailed product behavior

### 6.1 Chat

- The stage is the dominant visual surface; transcript and composer remain reachable without hiding character state.
- Push-to-talk has `idle`, `requestingPermission`, `listening`, `transcribing`, `readyToSend`, `sending`, `cancelled` and `failed` states.
- Character speech may begin only from the current accepted response. User interruption immediately stops audio and lip sync.
- The transcript distinguishes user text, accepted transcription, character response, system/recovery status and memory proposal.
- A travel suggestion is an explicit handoff action containing an inspectable destination, route preference or place reference; it is never an invisible transfer of the whole conversation.
- Factual answers that use a confirmed journey context follow the same source policy as Map. Persona, emotion and fictional role-play language must not masquerade as a sourced fact.

### 6.2 Map

- A persistent map and contextual drawer replace separate Guide, Scan, Trips and Search tabs.
- The drawer moves through nearby/unknown, candidates, confirmed place, narration, route progress, camera result, sources and recovery states.
- Short Map questions stay attached to the current place/route. A full-stage conversation can open Chat while preserving journey state.
- Walking route instructions outrank conversational speech. Users can mute character narration without muting essential visible navigation.
- Driving and unsupported transport modes use a clear system-maps handoff.
- Offline packs are corridor/tour products, not a promise of a full offline world map.

### 6.3 Character Library

- The library separates installed packages from current companion relationship state.
- Preview shows name, author/provenance, format, requested renderer, package size, license/usage restrictions, included locales, voice/motion assets, validation results and expected fallback.
- Removing a package does not automatically delete related conversations or memory; the user chooses whether to retain, export or delete those separately.
- Switching character does not inherit memory by default. Any inheritance is explicit, category-specific and reversible.
- Raw input is normalized locally; the installed form follows the versioned `.joi-character` contract.

### 6.4 Settings, account and controls

- Settings is grouped by `Character & Voice`, `Language & Appearance`, `Memory`, `Travel & Downloads`, `Account & Sync`, `Privacy & Data`, `Accessibility` and `Diagnostics`.
- Each synchronized category has an independent on/off control, last sync status and deletion behavior.
- Export distinguishes packages, conversations, memory, travel history and account data.
- Delete offers granular categories and a complete-delete action with local result, pending remote tombstones and final remote acknowledgement.
- Diagnostics never reveal credentials, raw prompts, precise location, photos or memory values.

### 6.5 Chat/Map transition contract

Surface switching is a presentation action, not a request-cancellation, route-cancellation, consent or memory event.

| Current state | On Chat ↔ Map switch | Explicit cancellation / recovery |
|---|---|---|
| idle | Preserve character, thread, surface-specific scroll/selection and active journey | None |
| unsent Chat draft | Retain locally and never send, speak, attach to Map or extract for memory | User may clear the draft explicitly |
| request streaming | Continue under the shared thread/request owner; Map shows a non-blocking activity indicator | User stop, superseding request, timeout or app termination cancels; switching alone does not |
| companion speaking | Continue if no higher-priority cue exists; preserve transcript | User stop or route-priority preemption cancels the speech generation, not the accepted text |
| route guidance speaking | Continue as highest-priority foreground cue and expose a visible banner in Chat | Stopping/ending the route or user mute cancels; Chat conversation cannot silently preempt it |
| permission or consent sheet | Queue the visual surface change until the sheet resolves; never interpret the tab tap as grant/deny | Dismissal fails closed and resumes the prior stable surface |
| active foreground journey | Preserve route/session/progress in `JourneyContextStore`; Chat cannot read exact context directly | Explicit stop ends the journey; app background pauses location updates in P0 and resume revalidates |
| one-turn journey attachment | Preserve only its visible preview/receipt until send, cancel, expiry or revoke | Cancel/expiry/revoke removes it; it cannot authorize memory or sync |
| offline | Preserve cached route/content and pending drafts; show unavailable online actions honestly | User may stop route or retry online later; no arbitrary offline reroute |
| failure/recovery | Preserve the typed failure and its primary recovery; do not replace it with success on switch | The owning operation defines retry/cancel; unrelated session/journey state remains intact |

## 7. Named failure and degraded states

| State | Entry condition | User-visible recovery |
|---|---|---|
| `backendUnavailable` | Proxy is unreachable, rate-limited or unhealthy | Preserve draft/thread; retry, use cached/local content where truthful, or continue with non-AI controls |
| `responseCancelled` | User stop, superseding request, timeout or app termination cancels a request | Mark cancelled without appending a fabricated answer; surface switching alone never cancels; resend remains optional |
| `staleSpeechSuppressed` | Audio belongs to an obsolete response, route step or character | Stop audio/lip sync immediately; current text/state stays authoritative |
| `microphoneDenied` | Microphone permission is denied/restricted | Open settings guidance and keep text input fully usable |
| `transcriptionFailed` | Audio capture succeeds but no accepted transcript is produced | Let the user retry or type; do not send or remember partial text |
| `speechPlaybackFailed` | TTS/audio route cannot play | Keep readable text and visible navigation; retry after route/interruption recovery |
| `audioInterrupted` | Call, Siri, route change, headset loss or app lifecycle interrupts audio | Pause/stop safely and require current-state validation before resume |
| `memoryWriteDeclined` | User rejects a proposed durable memory | Continue conversation without saving or repeatedly prompting |
| `memorySyncConflict` | Local and remote changes share no deterministic ordering | Show category/item conflict, preserve both versions, offer explicit resolution |
| `accountUnavailable` | Sign-in or sync service is unavailable | Continue local-only; queue only already-consented changes and expose pending state |
| `characterImportRejected` | Package violates schema, limits, hash, path, type or isolation rules | Show failed checks; install nothing; allow choosing another file |
| `characterRuntimeUnsupported` | Package is safe but outside the tested renderer matrix | Explain incompatibility and use trusted static fallback when available |
| `characterRenderFailed` | Native renderer cannot load or loses the rendering device | Release failed resources, show static character and retain Chat/Map controls |
| `characterLicenseUnknown` | Package lacks sufficient provenance or usage terms | Allow private quarantine/inspection only; block public redistribution and release fixtures |
| `locationDenied` | Location permission is denied/restricted | Manual search, downloaded route browsing and camera/photo flows remain available |
| `locationUnavailable` | No fix, stale fix or unacceptable accuracy | Show age/accuracy, avoid auto-confirm, offer retry or manual place selection |
| `placeAmbiguous` | Multiple identities remain plausible | Show candidates and evidence; require user confirmation |
| `placeCorrectionPending` | Correction is submitted but not acknowledged | Apply local session override immediately and show pending case status |
| `cameraDenied` | Camera permission is denied/restricted | Offer photo library or manual search without blocking Map |
| `photoAccessDenied` | Selected-photo access is unavailable | Offer camera or manual search and explain limited-library recovery |
| `recognitionLowConfidence` | Visual result does not meet confirmation threshold | Show candidates; never replace the confirmed subject automatically |
| `sourceUnsupported` | A factual claim lacks adequate current evidence | Abstain or label non-factual guidance; do not display a verified badge/citation |
| `sourceConflict` | Authoritative sources materially disagree | Show conflict and versions; avoid one false certainty |
| `networkDegraded` | Slow/intermittent connection changes expected behavior | Show online retry versus cached mode and preserve cancellation |
| `offlinePackMissing` | Required known-tour asset is absent | Identify missing content, stop affected action safely and offer redownload when online |
| `offlinePackInvalid` | Manifest signature/hash/version or atomic activation fails | Quarantine pack, keep last valid version and offer verified redownload |
| `offRouteOffline` | User leaves cached route with no routing service | Give bearing/distance back to route or stop; never offer arbitrary reroute |
| `drivingRouteRequested` | User requests driving navigation | Explain scope and hand off destination/route intent to system maps |
| `storageInsufficient` | Import, pack or export cannot complete atomically | Show required/available space, preserve current data and offer storage management |
| `languageAssetMissing` | Content, voice or package overlay lacks selected locale | Fall back through a declared locale chain and label it; never show blank or mis-keyed content |
| `deletionPending` | Remote deletion tombstone awaits acknowledgement | Complete local deletion, show pending remote status and retry safely |
| `deletionFailed` | Local deletion or remote acknowledgement cannot be verified | Keep a visible failure record, retry and block any “complete” claim |

### 7.1 Cancellation and fixture contract

Every named state has a deterministic fixture. “Preserve” means retain the last accepted character/thread/journey data and discard only the failing operation's uncommitted output.

| State | Fixture | Cancellation semantics |
|---|---|---|
| `backendUnavailable` | `FAIL-001` | Cancel transport task; preserve draft/thread and accepted events |
| `responseCancelled` | `FAIL-002` | Reject late events; preserve accepted transcript and request a new ID on retry |
| `staleSpeechSuppressed` | `FAIL-003` | Cancel obsolete generation/audio/lip sync; preserve current text/state |
| `microphoneDenied` | `FAIL-004` | End capture attempt; never create audio/transcript data |
| `transcriptionFailed` | `FAIL-005` | Discard partial/unaccepted transcript; preserve composer and thread |
| `speechPlaybackFailed` | `FAIL-006` | End playback generation; preserve visible text/navigation |
| `audioInterrupted` | `FAIL-007` | Stop/pause current generation and revalidate before explicit resume |
| `memoryWriteDeclined` | `FAIL-008` | Delete proposal/authorization; preserve conversation and do not reprompt automatically |
| `memorySyncConflict` | `FAIL-009` | Stop cursor advance; preserve both versions until explicit/deterministic resolution |
| `accountUnavailable` | `FAIL-010` | Cancel network auth/sync; preserve local state and already-consented outbox |
| `characterImportRejected` | `FAIL-011` | Abort/quarantine staging atomically; preserve active character |
| `characterRuntimeUnsupported` | `FAIL-012` | Cancel animated load; select validated portrait then bundled static fallback |
| `characterRenderFailed` | `FAIL-013` | Cancel load generation and release once; preserve session/journey controls |
| `characterLicenseUnknown` | `FAIL-014` | Block activation/redistribution; retain private inspection receipt only |
| `locationDenied` | `FAIL-015` | Stop collection request; clear pending exact snapshot and keep manual actions |
| `locationUnavailable` | `FAIL-016` | Reject stale/inaccurate sample; preserve last confirmed place as historical, not current |
| `placeAmbiguous` | `FAIL-017` | Cancel auto-confirm; preserve candidate set until choice/clear |
| `placeCorrectionPending` | `FAIL-018` | Cancel remote wait without reverting local session override |
| `cameraDenied` | `FAIL-019` | End capture attempt; create no image/upload record |
| `photoAccessDenied` | `FAIL-020` | End selection attempt; create no copied/uploaded asset |
| `recognitionLowConfidence` | `FAIL-021` | Reject auto-replacement; preserve confirmed subject and candidates |
| `sourceUnsupported` | `FAIL-022` | Cancel factual narration for unsupported claims; allow clearly non-factual content |
| `sourceConflict` | `FAIL-023` | Cancel single-certainty projection; preserve conflicting revisions |
| `networkDegraded` | `FAIL-024` | Cancel/supersede timed-out operation; keep cached/accepted state |
| `offlinePackMissing` | `FAIL-025` | Stop affected tour action; preserve last valid pack and unrelated downloads |
| `offlinePackInvalid` | `FAIL-026` | Abort activation and quarantine candidate; keep last valid pointer |
| `offRouteOffline` | `FAIL-027` | Cancel any new-route request; keep cached route and return guidance only |
| `drivingRouteRequested` | `FAIL-028` | Do not start in-app navigation; hand off only after explicit confirmation |
| `storageInsufficient` | `FAIL-029` | Abort atomic import/download/export; remove staging and preserve current data |
| `languageAssetMissing` | `FAIL-030` | Cancel missing asset request; apply and label the declared fallback chain |
| `deletionPending` | `FAIL-031` | Keep local deletion final; retry tombstone without resurrecting payload |
| `deletionFailed` | `FAIL-032` | Stop completion claim; preserve failure/audit proof and safe retry identity |

## 8. Trust, location and memory governance

### 8.1 Source model

- **Place identity confidence** answers “what is this?”; **source authority** answers “who says it?”; **evidence support** answers “does this source support this claim?”; **freshness** answers “which version and when?” These values are not collapsed into one probability.
- Every factual narration segment points to an immutable source revision or is marked unsupported and withheld from factual output.
- Source projection includes publisher, title, URL or durable locator, source type, revision/version, updated/retrieved time, rights/attribution, verification and withdrawal state.
- Conflicts are preserved and explained. Correction creates a traceable local/session result even while remote review is pending.
- Cached content always shows content version and freshness; withdrawn or rights-expired revisions invalidate affected narration and packs.

### 8.2 Location, photos and microphone

- Precise location is processed only while a user-visible Map task requires it. Background behavior must have a separate purpose statement and real-device evidence.
- Analytics receive neither raw tracks nor exact coordinates. Coarse quality buckets may be recorded only when they cannot reconstruct a journey.
- Photos are resized to task need and stripped of EXIF before remote upload. Remote use, retention and deletion are disclosed before upload.
- Raw microphone audio is not retained by default. Accepted transcript and audio retention are separate choices.
- Permissions are reversible; revocation immediately stops future collection and preserves manual recovery paths.

### 8.3 Memory and sync

- Memory categories are `ephemeral thread`, `user profile/preferences`, `relationship`, `travel recap` and `protected/never-sync`.
- Each durable item records origin, created/updated time, character/thread scope, sync category and user-visible reason.
- Precise location, raw photos, raw audio and complete travel tracks are never implicitly promoted to long-term memory.
- Character packages contain no user memory or affinity. Conversation and memory remain available for explicit export/delete after a character package is removed.
- Account sync is opt-in per category. Disabling a category stops new uploads and exposes whether remote deletion is requested or complete.

## 9. Language and accessibility staging

- The current implementation and content lane is `zh-Hans` only. All visible shell copy is centralized in an editable String Catalog.
- `zh-Hant`, `en`, `ja` and `ko` are deferred and must be added as human-reviewed lanes; they are not silently machine-filled or counted as current completeness.
- Place names use local name plus a user-language explanation where useful; map basemap labels may remain provider-controlled.
- Display locale, knowledge/content locale and character voice locale are separate values carried through requests and cache keys.
- Existing system text styles, semantic labels and Reduce Motion hooks are retained as forward-compatible scaffolding only. Full accessibility validation is deferred and must not be presented as passed.

## 10. Success metrics

### 10.1 North-star metric

**Meaningful companion days per weekly active user.** A day is meaningful when the user completes either:

- a Chat exchange of at least three user/companion turns or two minutes of active engagement; or
- a confirmed, source-eligible Map narration engaged for at least 30 seconds, or one completed cultural-route stop.

Chat and Map contributions are reported separately. Repeated automatic playback, failed requests and background time do not count.

### 10.2 Launch hypotheses

| Metric | Pilot target |
|---|---:|
| Existing desktop Joi users completing local-first setup | ≥ 70% |
| Valid test packages installed successfully or given an actionable compatibility result | ≥ 95% |
| New users completing one meaningful Chat session on first day | ≥ 60% |
| Activated users using both Chat and Map within 28 days | ≥ 20% |
| Accepted Chat requests ending in current text or an explicit recoverable error | ≥ 98% |
| Stale speech observed after stop/supersession | 0 in release test matrix |
| Production factual segments with eligible source revision and evidence support | 100% |
| Downloaded known-tour core completion without network | ≥ 95% |
| High-confidence wrong automatic place confirmation | ≤ 3% |
| Complete local-delete verification | 100% |
| Crash-free sessions | ≥ 99.5% |

Targets are hypotheses until measured in a consented pilot. Metrics must not incentivize silent memory retention, background location or excessive notifications.

## 11. Non-functional requirements

| Dimension | Requirement |
|---|---|
| Platform | iPhone, iOS 26+, Swift 6 strict concurrency, deterministic SwiftUI state and reproducible project generation |
| Reliability | Crash-free sessions ≥99.5%; requests, speech, imports, downloads and navigation effects are cancellable/idempotent where repeated |
| Chat latency | On a defined healthy reference network, accepted text requests show first useful content p95 ≤3s; degraded/network time is measured separately |
| Map latency | Warm local candidate or cached stop p95 ≤500ms; supported remote candidate p95 ≤2.5s; camera recognition p95 ≤5s on the pilot matrix |
| Rendering | Supported character fixtures sustain ≥30 FPS while visibly active on the public device matrix; hidden/background/reduced-motion renderers pause or lower work |
| Thermal/energy | A fixed 30-minute Chat/Map/location/speech/character script must not remain in serious/critical thermal state for more than 60 seconds; publish measured energy, not estimates |
| Audio | Calls, Siri, route changes, silent mode, headphones, Bluetooth and foreground/background transitions preserve single-owner and stale-cancellation rules |
| Offline integrity | Travel packs use versioned manifests, hashes/signatures, atomic activation, last-known-good rollback and explicit source/content versions |
| Package safety | Enforce archive/file ceilings, traversal/symlink/executable rejection, declared types, hashes, provenance and state isolation before preview or runtime load |
| Security | TLS in release; credentials in approved secure storage only; logs and diagnostics redact tokens and protected data; model providers are server-side |
| Privacy | Data inventory covers local stores, caches, uploads, analytics and sync; granular and complete deletion are testable end to end |
| Localization | Current `zh-Hans` shell copy is complete and editable; additional locales require separate human-reviewed gates |
| Accessibility | Deferred: preserve implementation hooks now; require dedicated VoiceOver, Dynamic Type, Reduce Motion, contrast and long-text evidence before a later public recommendation |
| Compatibility | Renderer support is defined by fixture-based quality tiers; “broad VRM support” is not a substitute for a published VRM 0.x/1.0/VRMA and Live2D matrix |
| Observability | Quality events use pseudonymous IDs and exclude exact location, raw media, full conversation and memory content |

Simulator evidence may close compilation, deterministic state, schemas and many UI flows. Camera, GPS/background location, microphone/audio interruptions, sustained frame rate, thermals, energy and outdoor drift require real-device/field evidence.

## 12. Non-goals

- A third primary surface, five-tab legacy shell or separate companion and travel apps.
- Continuous hands-free realtime voice at P0.
- In-app driving navigation, traffic/vehicle safety product claims or CarPlay.
- Arbitrary offline rerouting or a globally complete offline map.
- Hotel/flight/restaurant booking, review marketplace, social feed or UGC community.
- Unity, embedded browser, WKWebView or Three.js as a character runtime fallback.
- Client-side provider keys, BYOK as the public architecture, or direct exposure of desktop Joi's local sidecar protocol.
- Importing executables, plugins, permissions, secrets, history, memory, affinity or sync state inside a character package.
- Automatic transfer of precise location, photos, travel tracks or whole conversations into durable memory.
- Unmoderated character marketplace, user-to-user package distribution or creator payouts at launch.
- Android, iPad-first layout, Apple Vision Pro or a desktop rewrite in this repository.
- Claiming public readiness before Live2D expandable licensing, character/content rights, map/data rights and real-device gates close.

## 13. Public release gates

| Gate | Required evidence | Release effect |
|---|---|---|
| G0 — Product and contract | This PRD approved; TDD maps every P0 requirement to module/interface/test/gate; shared state owners, schemas, errors, cancellation, fallback and migration frozen | No feature implementation claims before traceability and scheme review pass |
| G1 — Deterministic foundation | Reproducible project generation, simulator build, package tests, schema fixtures, package validation and no-secret scan | Enables integrated internal builds only |
| G2 — Hero journeys | Six journeys pass deterministic success, permission, network, cancellation, conflict and fallback fixtures in `zh-Hans`; additional languages and full accessibility validation are separate later conditions | Enables a Chinese-language device pilot, not public release |
| G3 — Trust and safety | Data inventory, just-in-time consent, photo minimization, memory proposals, granular sync, export, local/remote deletion and package-supply-chain tests independently verified | Trust & Safety may veto release until complete |
| G4 — Real device and field | Supported iPhones pass camera, GPS/drift, cultural walking, offline pack, background/audio interruption, sustained FPS and 30-minute thermal/energy scripts | Quality & Release may veto release until complete |
| G5 — Rights and licenses | Live2D Expandable Application approval/agreement, Cubism notices, VRM/model/VRMA provenance, package fixtures, content/source rights, map/tile/routing data licenses and attribution accepted | Missing external approval or data right blocks public distribution |
| G6 — Release candidate | Crash/privacy metrics, approved Chinese store/privacy copy, any subsequently selected language/accessibility gates, rollback, support and incident procedures, dependency/license inventory and final Director closeouts | Only this gate permits a public-release recommendation; submission still needs explicit user authorization |

## 14. Open-source feasibility evidence

Open-source references demonstrate that the direction is technically plausible, but no single project satisfies Joi Mobile's native runtime, privacy, source, offline and licensing requirements. They are inputs to adapters and PoCs, not drop-in product proof.

| Reference | Evidence | Joi Mobile decision |
|---|---|---|
| [AIRI](https://github.com/moeru-ai/airi) | Its repository documents a companion Core/Stage split plus memory, speech, Live2D, VRM and mobile-stage work. Its primary graphics/application stack remains substantially web/Electron/Capacitor-oriented. | Reuse the conceptual separation of companion core and stage; do not copy its web renderer/runtime architecture. |
| [Scowld](https://github.com/apoorvdarshan/scowld) | Demonstrates an iOS SwiftUI companion with chat, speech, local history and a VRM avatar, but its published architecture renders through WKWebView, Three.js/three-vrm and uses client BYOK provider keys. | Confirms mobile companion demand/flow precedent; explicitly reject its renderer and credential choices. |
| [VRMKit](https://github.com/tattn/VRMKit) | Provides Swift loading and experimental RealityKit rendering with expressions, bones and spring bone; its README still lists rendering quality, MToon and VRMA support as work items. | Isolate behind `CharacterRenderer`; require an owned compatibility PoC/matrix and do not equate dependency import with broad VRM/VRMA support. |
| [VRM specification](https://vrm.dev/en/vrm/vrm_features/) | Defines portable one-file avatars, author/license metadata, humanoid pose, expressions, gaze and VRM Animation semantics across VRM generations. | Use the standard as compatibility truth and retain package-level provenance/rights checks around it. |
| [Live2D native platform support](https://docs.live2d.com/en/cubism-sdk-manual/platform/) | Official documentation lists 64-bit iOS Native support with OpenGL and Metal. | Native iOS rendering is feasible; device/runtime integration remains Joi's responsibility. |
| [Live2D Expandable Applications](https://www.live2d.com/en/sdk/license/expandable/) | Official terms classify titles that add or combine indefinite avatar models as expandable and require review plus a special publication agreement before release. | Treat approval/agreement as a hard public-release dependency, not a post-launch task. |
| [MapLibre Native](https://github.com/maplibre/maplibre-native) | Provides native GPU-accelerated vector maps and an iOS package/UIKit API that can be wrapped for SwiftUI. | Feasible map/offline-rendering candidate behind a provider boundary; tile/style/data rights and pack operations still require separate proof. |
| [Ferrostar](https://stadiamaps.github.io/ferrostar/) | Provides composable iOS/SwiftUI navigation state, voice guidance and replaceable route providers, while explicitly stating it is not a basemap, search or routing engine. | Useful navigation-state reference/candidate; keep routing and map providers separate and validate beta/API stability. |
| [Valhalla](https://github.com/valhalla/valhalla) | Open routing engine for OpenStreetMap with map matching, maneuver narratives and tiled structures intended to support regional/offline use. | Feasible online routing/pack-generation input; self-hosting, mobile footprint, OSM data license and arbitrary offline routing are not solved by naming it. |

Feasibility conclusion: **approved for staged native PoCs**. The product direction is implementable if renderer, navigation, offline-pack and backend dependencies remain replaceable adapters; compatibility, performance, rights and field behavior remain release evidence rather than roadmap assertions.

## 15. Risks and unresolved external dependencies

| Risk | Impact | Required closure |
|---|---|---|
| Live2D Expandable Application approval is not yet evidenced | Public distribution with importable Live2D models may be prohibited or commercially impractical | Written approval/agreement and accepted business terms before G5 |
| Broad VRM 0.x/1.0 plus VRMA exceeds current native library proof | Models may load with incorrect materials, expressions, motion or performance | Owned adapter, representative legal fixtures, compatibility tiers and device matrix |
| Live2D/VRM + Map + GPS + speech may exceed thermal/energy budgets | Core experience may throttle or drain battery | Fixed 30-minute real-device scripts and adaptive renderer policy |
| Offline travel packs combine maps, routes, sources, narration and media rights | A technically valid pack may still be illegal, stale or too large | Versioned rights inventory, regional size budgets, withdrawal and rollback drill |
| Official backend proxy is a required online dependency | Chat/vision quality, latency, cost and abuse handling can block launch | Typed contract, deterministic mock, capacity/cost limits and production safety review |
| Account sync increases deletion and conflict complexity | Silent retention or data resurrection would violate user trust | Category consent, tombstones, conflict fixtures and end-to-end deletion proof |
| Desktop `.joi-character` may evolve independently | Mobile import compatibility may drift | Versioned fixtures and adapter tests against the current desktop contract; no sidecar coupling |
| Trusted cultural content requires continuing editorial ownership | Source coverage may be technically present but substantively weak | Named content owner, revision policy, authority/conflict review and five-language QA |

## 16. Product Design scheme recommendation

**Decision: `approved-with-conditions`.**

**Basis:** The product has a coherent identity, exactly two primary surfaces, six observable end-to-end journeys, explicit failure/recovery behavior, measurable launch requirements and truthful native/offline boundaries. It preserves Joi Map's four travel pillars while making companionship the umbrella product.

**Conditions:**

1. Technical design must trace every P0 requirement exactly once and preserve the sole mutable owners for companion session, journey context and speech.
2. Trust & Safety must approve memory proposals, location/photo/microphone consent, package isolation, sync and verifiable deletion before implementation closeout.
3. Art & Character and Quality & Release must approve renderer fixtures, static fallback and device evidence; broad compatibility cannot be inferred from one dependency.
4. Public release remains blocked until Live2D expandable approval, model/content/map rights and all real-device gates are evidenced.

**Owner:** Studio Director coordinates closure; the accountable domain Directors retain independent veto authority.
