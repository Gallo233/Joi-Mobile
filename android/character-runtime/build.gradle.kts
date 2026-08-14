plugins {
    alias(libs.plugins.kotlin.jvm)
    // The conformance corpus reader is shared with :chat-feature's tests. Sharing
    // it as a test fixture keeps one reader for one corpus without putting test
    // scaffolding into the published module.
    `java-test-fixtures`
}

kotlin {
    compilerOptions {
        // Java 17 is the floor Android Gradle Plugin 8.x requires and the level
        // Android desugars to, so a class can move into the app module without
        // becoming a compatibility question.
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        // A warning is the first sign of an assumption that stopped holding.
        allWarningsAsErrors.set(true)
    }
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

tasks.withType<Test>().configureEach {
    useJUnitPlatform()
    testLogging { events("passed", "failed", "skipped") }
}

// iOS admits exactly one dependency here, pinned to an exact revision, and owns
// every security decision above it. This module admits none: package admission is
// where hostile input arrives, so every decision in it is one somebody in this
// repository made.
dependencies {
    implementation(project(":companion-core"))
    testImplementation(kotlin("test"))
}
