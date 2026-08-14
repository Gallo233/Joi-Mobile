// Every plugin is declared here, with its version, and applied nowhere.
//
// This is not style. A plugin resolved in a subproject's `plugins {}` block gets
// its own classloader, a child of the root's — so a plugin loaded at the root
// cannot see one loaded in a subproject. Declaring the Kotlin plugin here and
// the Android plugin in `:app` put them in sibling scopes, and applying
// `org.jetbrains.kotlin.android` then failed with
// `NoClassDefFoundError: com/android/build/gradle/api/BaseVariant` — a class
// that is present in every AGP version we tried. The class was never missing;
// the classloader that needed it could not see the one that had it.
//
// Declaring them all here puts them in one classloader, which is what lets the
// Kotlin plugin read AGP's variant model at all. Subprojects then apply them by
// bare id, with no version.
plugins {
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.compose) apply false
}
