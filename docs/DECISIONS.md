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
