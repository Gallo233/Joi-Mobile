// Bare ids, no versions: every version lives in the root build, which is also
// what keeps these in one classloader — see the comment there.
//
// There is deliberately no `org.jetbrains.kotlin.android`. AGP 9 compiles
// Kotlin itself, and applying the standalone plugin on top of it is refused
// outright rather than merely redundant.
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.joi.mobile"
    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        applicationId = "com.joi.mobile"
        minSdk = libs.versions.minSdk.get().toInt()
        targetSdk = libs.versions.targetSdk.get().toInt()
        versionCode = 1
        versionName = "0.1.0"
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    // The portable core, unchanged. Every semantic this app relies on — package
    // admission, content identity, stream framing — is the same code the
    // conformance corpus already holds to the same answers as iOS.
    implementation(project(":companion-core"))
    implementation(project(":character-runtime"))
    implementation(project(":chat-feature"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.material3)
    implementation(libs.compose.ui.tooling.preview)
    debugImplementation(libs.compose.ui.tooling)

    testImplementation(libs.kotlin.test.junit5)
    testRuntimeOnly(libs.junit.jupiter.engine)
    testRuntimeOnly(libs.junit.platform.launcher)
}

tasks.withType<Test>().configureEach {
    useJUnitPlatform()
    testLogging { events("passed", "failed", "skipped") }
}
