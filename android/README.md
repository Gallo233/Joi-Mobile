# Joi for Android

The second native client. Same product contract, own implementation.

This directory holds the **portable core** — the character package contract, the
strict manifest scanner, content identity, package admission and event-stream
framing, in Kotlin, with no Android dependency and no third-party dependency at
all — and a **Compose shell** over it. The core is verified against
`Contracts/conformance/`, the same vectors the iOS suite runs.

There is no renderer and no networking. The shell's stage and composer are
placeholders that say so on screen. Why the core came before the shell is under
*Why this order* below.

## What builds today

```bash
cd android
./gradlew test
```

16 tests, about a second once the toolchain is warm. The three core modules are
plain JVM and need no Android SDK:

| Module | Mirrors | Contents |
|---|---|---|
| `companion-core` | `Packages/CompanionCore` | `CharacterPackageManifestV1`, `CompanionEventV1`, renderer kinds, limits, stable upstream codes |
| `character-runtime` | `Packages/CharacterRuntime` | `StrictJson`, `PackagePath`, `ContentTreeIdentity`, `CharacterManifestAdmission`, the stable import codes |
| `chat-feature` | `Packages/ChatFeature` | `SseFrameParser` |

`:app` is the Android module: `MainActivity`, the two-surface Compose shell, and
`CompanionSessionStore` — the single writer of character, thread, session and
accepted transcript, written with no Android import so its rules are testable on
the JVM in milliseconds rather than on a device. Verified on a Pixel 8 / API 37 /
arm64 emulator: Chat → Map → Chat returns a capture differing from the first in
zero of 2,473,200 pixels.

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
| Kotlin | 2.4.10 | Applies to the plain-JVM modules only. AGP 9 compiles `:app`'s Kotlin itself and **refuses** the standalone `org.jetbrains.kotlin.android` plugin, so JetBrains' KGP-to-AGP table does not bind here |
| Android Gradle Plugin | 9.3.1 | The first AGP supporting API 37, which the Compose artifacts require to compile against |
| JDK | 17–24 | AGP requires ≥ 17. **Android Studio's own JBR is 25, which Gradle does not accept** |

Two traps cost hours here, both recorded in `gradle/libs.versions.toml`: every
plugin must be declared in the *root* build with `apply false` or the Kotlin and
Android plugins land in sibling classloaders and fail with a
`NoClassDefFoundError` naming a class that is present in every AGP jar; and
`kotlin("test")` is unavailable in `:app` for the same reason the Kotlin plugin
is, so its test dependencies are written out by coordinate.

SDK side: platform `android-37.0` and build-tools `36.0.0`. Installing them is
where Google's licence gets accepted — which has to be a person, not a build
script.

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
JOI_SKIP_APP=1 JOI_GRADLE_MIRROR=aliyun ./gradlew test   # core only, ~240 MB
JOI_GRADLE_MIRROR=aliyun ./gradlew assembleDebug test    # the rest, expect 16 tests
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

That mechanism has earned its keep repeatedly. Running the vectors against the
shipping iOS implementation found, in order:

- a raw `NSError` escaping the stable-code boundary (fixed);
- the declared asset list capped at 300 while the schema promised 2000, which
  made an ordinary Live2D character unimportable (DEC-028);
- content identity computed over filesystem bytes rather than package bytes, so
  the same package had two identities on two platforms. The Kotlin twin
  satisfied that vector on its first compile while the Swift one had to skip it
  — the divergence measured rather than argued (DEC-026, now closed);
- every archive containing a folder refused, because the execute-bit rule for
  files was silently applied to directories, where the same bit is the search
  bit every archiver writes (DEC-029);
- and behind that, no mainstream archiver producing an importable archive at all
  (DEC-029, four changes, now fixed and measured against `zip`, `ditto`, Python
  and `zip -X`).

## Deliberately not ported yet

The installer's tree layer. What exists and what does not:

| Piece | Vectored | Ported to Kotlin |
|---|---|---|
| Strict scanner, admission, content identity, SSE framing | Yes | Yes |
| Restricted ZIP profile | **Yes**, 45 archives in `zip-profile.json` | No |
| Per-asset digests, media magic bytes, Live2D reference closure, VRM motion graph | No — needs a tree fixture | No |
| Immutable storage, activation leases, journaled removal | No — stateful protocols, the wrong shape for vectors | No |

The ZIP profile is the next thing to port, because it is the only remaining
security-critical piece that is already pinned by vectors: the port can be
checked rather than trusted. Everything below it is still a re-derivation.

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

1. **Live2D on Android is a second licence, not a second build.** The Expandable
   Application agreement is per application; an Android build is a separate
   application and needs its own review and approval. VRM-first applies here
   exactly as it does on iOS.
2. **Which renderer.** Settled as a direction in DEC-030: Filament plus `gltfio`
   for the GPU layer, MToon compiled to a `.filamat` blob at build time, and
   every VRM semantic — normalization, humanoid, expressions, LookAt, spring
   bones, constraints, VRMA — written here. Note that this is *more* work than
   the iOS renderer was, not the same: iOS had VRMMetalKit to build on and
   Maven Central has no VRM library at all. No prototype has been built, so
   nothing about fidelity or frame rate is claimed.
