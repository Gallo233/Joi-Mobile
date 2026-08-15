# Joi for Android

The second native client. Same product contract, own implementation.

This directory currently holds the **portable core** and nothing else: the
character package contract, the strict manifest scanner, content identity,
package admission and event-stream framing, in Kotlin, with no Android
dependency and no third-party dependency at all. All of it is verified against
`Contracts/conformance/` — the same vectors the iOS suite runs.

There is no Compose UI, no renderer, no networking and no app module yet. That
is deliberate and is explained under *Why this order* below.

## What builds today

```bash
cd android
./gradlew test
```

11 tests over the 100 conformance vectors, about a second once the toolchain is
warm. No Android SDK is required, and none is used. The three modules are plain
JVM:

| Module | Mirrors | Contents |
|---|---|---|
| `companion-core` | `Packages/CompanionCore` | `CharacterPackageManifestV1`, `CompanionEventV1`, renderer kinds, limits, stable upstream codes |
| `character-runtime` | `Packages/CharacterRuntime` | `StrictJson`, `PackagePath`, `ContentTreeIdentity`, `CharacterManifestAdmission`, the stable import codes |
| `chat-feature` | `Packages/ChatFeature` | `SseFrameParser` |

`settings.gradle.kts` adds an `:app` module only when an Android SDK is actually
present — the same ladder as `project.yml` → `project.live2d.yml` →
`project.native.yml` on iOS, where every rung stays independently buildable. A
clone with no SDK still compiles and tests everything above. Accepting Google's
SDK licence is a developer decision and not one a build script should make.

To add the app module later, install the SDK and either export `ANDROID_HOME` or
write `sdk.dir=/path/to/sdk` into `android/local.properties`.

## Toolchain

These four versions are one combination, not four independent choices:

| Component | Version | Why this one |
|---|---|---|
| Gradle | 9.5.0 | AGP 9.3 requires ≥ 9.5.0 and ships 9.5.0 as its default |
| Kotlin | 2.2.21 | Gradle 9 support starts at Kotlin 2.2; the Compose compiler always carries the Kotlin version |
| Android Gradle Plugin | 9.3.1 | Latest stable; supports API 37 at most, which is the installed platform |
| JDK | 17–24 | AGP 9.3 requires ≥ 17. **Android Studio's own JBR is 25, which Gradle does not accept** |

SDK side, both already at AGP 9.3's minimum: platform `android-37.0`, build-tools
`36.0.0`. Installing them is where Google's licence gets accepted — which has to
be a person, not a build script.

```bash
JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-22.jdk/Contents/Home ./gradlew test
```

Moving any one of the four means rechecking the other three.

### Mirrors

Two separate things are mirrored, by two separate mechanisms.

**Gradle itself** is fetched by the wrapper, which does not read
`JOI_GRADLE_MIRROR`. `distributionUrl` currently points at a mirror while
`distributionSha256Sum` is the checksum Gradle published — the mirror delivers
bytes, and the bytes still have to be the ones Gradle signed for. To go back to
the canonical host, change the URL and leave the checksum: it is valid either
way. Be aware that the wrapper's cache directory is named from a hash of the URL,
so switching it re-downloads the distribution rather than reusing what is on disk.

That pin is not theoretical. Fetching a distribution from a mirror during setup
produced a file `curl` reported as a complete success and which was in fact
truncated at half its length — 67 MB of a 137 MB archive, exit code 0. The
checksum caught it in a second; without one it would have surfaced as an
inscrutable failure somewhere inside the first build.

**Maven dependencies** are opt-in per invocation, so the choice stays visible in
the command that made it:

```bash
JOI_GRADLE_MIRROR=aliyun ./gradlew test
```

### First run, in two stages

The Android toolchain is roughly 600 MB. Do it in two, so an interrupted download
costs one stage rather than all of it — `JOI_SKIP_APP` keeps `:app` out of the
build until the core is known good:

```bash
JOI_SKIP_APP=1 JOI_GRADLE_MIRROR=aliyun ./gradlew test   # ~240 MB, expect 11 tests
JOI_GRADLE_MIRROR=aliyun ./gradlew assembleDebug test    # the rest, expect 16
```

## Why this order

The obvious way to start an Android client is a Compose shell with two tabs. It
would demo well and would prove nothing: the shell is the cheapest part to write
and the least likely to be wrong.

What is expensive and easy to get wrong is agreeing with iOS. A package installed
on a phone and a tablet must have the *same identity*; a manifest refused on one
platform must be refused on the other, with the same code, or the user reads two
different explanations for one file. Those semantics lived only in Swift, so
building the UI first would have meant re-deriving them later, under deadline,
against prose.

So the first slice is the part where divergence is silent and expensive, and it
ships with the mechanism that keeps it from diverging again.

That mechanism has already earned its keep, twice over.

Running the vectors against the shipping iOS implementation for the first time
found three disagreements, two of which are fixed (DEC-026, DEC-028).

The third is now demonstrated rather than predicted. `content identity of a
materialised tree matches every vector` passes here, on every case including
`decomposable-path`; the Swift twin has to skip that one. Two runners, one file,
one of them right — which is exactly the shape of finding the corpus exists to
produce, and is not a shape any amount of re-reading the Swift source would have
given. See DEC-026.

## Deliberately not ported yet

The larger half of the installer:

- the restricted ZIP profile and its preflight;
- per-asset digest verification, media magic-byte checks and the nested-archive
  refusal;
- the Live2D `.model3.json` reference closure and the VRM motion-table renderer
  graph;
- immutable content-addressed storage, activation leases and journaled removal.

None of it is vectored yet, so an Android port would be a *re-derivation* rather
than a port, carrying the risk that implies. Growing the corpus to cover a tree
fixture is the next slice, and it should come before the Kotlin code does.

## What is genuinely reusable, and what is not

Reusable as-is, no Android work needed:

- `Contracts/*.schema.json` — any Draft 2020-12 validator agrees with iOS.
- `Contracts/conformance/` — this is what makes semantics shared rather than
  parallel.
- The backend. `/v1/chat/streams` is provider-opaque by design; the provider and
  model are server-side facts, so a second client is a client change only.
- Character packages, personas, voice profiles and motion tables.

Not reusable, and no attempt should be made to force it:

- UI. SwiftUI and Compose map cleanly onto each other conceptually, and share no
  code.
- Renderers. Metal and VRMMetalKit have no Android counterpart; Filament plus a
  Joi-owned VRM semantic layer is the path, and MToon is a custom material that
  has to be written either way.
- Map, location, camera and audio. Platform adapters behind the shared journey
  vocabulary.

## Open questions that belong to a decision, not to code

1. **Path normalization in content identity** — DEC-026, and the reason the
   `decomposable-path` vector is marked non-normative. Until it is settled, a
   package with an accented or dakuten filename has two identities.
2. **Live2D on Android is a second licence, not a second build.** The Expandable
   Application agreement is per application; an Android build is a separate
   application and needs its own review and approval. VRM-first applies here
   exactly as it does on iOS.
3. **Which renderer.** Settled as a direction in DEC-030: Filament plus `gltfio`
   for the GPU layer, MToon compiled to a `.filamat` blob at build time, and
   every VRM semantic — normalization, humanoid, expressions, LookAt, spring
   bones, constraints, VRMA — written here. Note that this is *more* work than
   the iOS renderer was, not the same: iOS had VRMMetalKit to build on and
   Maven Central has no VRM library at all. No prototype has been built, so
   nothing about fidelity or frame rate is claimed.
