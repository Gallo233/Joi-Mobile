// Opt-in dependency mirrors, off by default.
//
// The canonical repositories are the default because a mirror is a supply-chain
// decision and nobody should acquire one by cloning. Where the canonical hosts
// are unusably slow, `JOI_GRADLE_MIRROR=aliyun ./gradlew test` swaps them for the
// run — an explicit, visible, per-invocation choice rather than a line in a
// config file that outlives the reason for it.
// Gradle lifts `pluginManagement` out and evaluates it before the rest of this
// script, so it cannot see a script-level declaration. The environment read is
// therefore repeated rather than shared — the alternative is a buildSrc or an
// included build, which is a lot of machinery for one optional string.
pluginManagement {
    repositories {
        if (System.getenv("JOI_GRADLE_MIRROR") == "aliyun") {
            maven("https://maven.aliyun.com/repository/gradle-plugin")
            maven("https://maven.aliyun.com/repository/public")
            maven("https://maven.aliyun.com/repository/google")
        }
        gradlePluginPortal()
        mavenCentral()
        google()
    }
}

val mirror: String? = System.getenv("JOI_GRADLE_MIRROR")?.takeIf { it.isNotBlank() }
require(mirror == null || mirror == "aliyun") {
    "unknown JOI_GRADLE_MIRROR '$mirror'; the only value is 'aliyun'"
}

@Suppress("UnstableApiUsage")
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        if (mirror == "aliyun") {
            maven("https://maven.aliyun.com/repository/public")
            maven("https://maven.aliyun.com/repository/google")
        }
        mavenCentral()
        google()
    }
}

rootProject.name = "joi-android"

// The portable core. Plain JVM modules with no Android dependency and no
// third-party dependency at all, so they build, test and are reviewable on any
// machine with a JDK — including one with no Android SDK installed.
include(":companion-core")
include(":character-runtime")
include(":chat-feature")

// The spec ladder, carried over from iOS: `project.yml` builds with no vendor
// runtime, `project.live2d.yml` adds Cubism, `project.native.yml` adds VRM, and
// every rung stays independently buildable. Here the rung is the Android app
// itself: it joins the build only when an SDK is actually present, so a clone
// without one still compiles and tests everything that does not need it.
//
// Google's SDK requires accepting its licence agreement, which is the developer's
// decision to make and not something a build script should make for them.
val androidSdk = sequenceOf(
    System.getenv("ANDROID_HOME"),
    System.getenv("ANDROID_SDK_ROOT"),
    file("local.properties")
        .takeIf { it.exists() }
        ?.readLines()
        ?.firstOrNull { it.startsWith("sdk.dir=") }
        ?.removePrefix("sdk.dir="),
).filterNotNull().map(::File).firstOrNull { it.isDirectory }

// Both halves have to be there. An SDK on the machine says the rung *can* be
// climbed; `app/build.gradle.kts` says it has been. Gating on the SDK alone
// breaks the build the moment someone installs Android Studio, which is exactly
// the wrong time to break it.
when {
    // The recovery hatch. Configuring :app resolves the Android Gradle Plugin, so
    // an interrupted first download would otherwise take the portable core's lane
    // down with it — on a slow link that is the difference between "still
    // fetching" and "nothing runs".
    System.getenv("JOI_SKIP_APP") != null ->
        logger.lifecycle("joi: :app skipped by JOI_SKIP_APP; building the portable core only.")
    !File(rootDir, "app/build.gradle.kts").isFile ->
        logger.lifecycle("joi: no :app module in the tree yet; building the portable core only.")
    androidSdk == null ->
        logger.lifecycle(
            "joi: :app exists but no Android SDK was found; building the portable core only. " +
                "Set ANDROID_HOME or write sdk.dir into android/local.properties."
        )
    else -> include(":app")
}
