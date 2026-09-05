import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing material, from whichever source is available:
//
//   1. android/key.properties  — a local release build on a developer machine
//   2. environment variables   — CI, which decodes the keystore from a secret
//   3. neither                 — fall back to debug signing below, so a fresh
//                                clone can still run `flutter run --release`
//
// The keystore and its passwords are never in git (see .gitignore).
// docs/RELEASING.md has the keytool invocation and the CI secret names.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

fun signingValue(propKey: String, envKey: String): String? =
    keyProps.getProperty(propKey) ?: System.getenv(envKey)

val releaseStorePath = signingValue("storeFile", "LINKDROP_KEYSTORE")
val releaseStorePassword = signingValue("storePassword", "LINKDROP_KEYSTORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "LINKDROP_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "LINKDROP_KEY_PASSWORD")

val hasReleaseSigning = listOf(
    releaseStorePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() } && file(releaseStorePath!!).exists()

android {
    namespace = "com.linkdrop.linkdrop_app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.linkdrop.linkdrop_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStorePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Debug signing is the fallback, not the intent: it lets a clone
            // without the keystore still run `flutter run --release`. Anything
            // handed to a user must be signed with the real key — an APK signed
            // with the shared debug key cannot later be upgraded in place by a
            // properly signed one, and the release job asserts this is set.
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
