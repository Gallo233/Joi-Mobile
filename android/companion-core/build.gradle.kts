plugins {
    alias(libs.plugins.kotlin.jvm)
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

// The shared contracts. No dependencies at all — not even a JSON library — so
// nothing about the wire format is decided by a third party's defaults.
dependencies {
    testImplementation(kotlin("test"))
}
