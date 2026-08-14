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

dependencies {
    implementation(project(":companion-core"))
    testImplementation(kotlin("test"))
    // Test-only. The conformance corpus is read with Joi's own strict scanner
    // rather than by adding a JSON library for tests: a second parser here would
    // be a second answer to a question this repository has already answered once.
    testImplementation(testFixtures(project(":character-runtime")))
}
