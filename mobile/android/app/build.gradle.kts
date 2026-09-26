plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val bpEnv = providers.environmentVariable("BP_ENV").orElse("development").get()
require(bpEnv in setOf("development", "preview", "production")) { "Invalid BP_ENV" }
val releaseKeys = listOf("ANDROID_KEYSTORE_PATH", "ANDROID_KEYSTORE_PASSWORD", "ANDROID_KEY_ALIAS", "ANDROID_KEY_PASSWORD")
val hasReleaseKeys = releaseKeys.all { !System.getenv(it).isNullOrBlank() }
val previewKeys = listOf("ANDROID_PREVIEW_KEYSTORE_PATH", "ANDROID_PREVIEW_KEYSTORE_PASSWORD", "ANDROID_PREVIEW_KEY_ALIAS", "ANDROID_PREVIEW_KEY_PASSWORD")
val hasPreviewKeys = previewKeys.all { !System.getenv(it).isNullOrBlank() }

if (bpEnv == "preview" && !hasPreviewKeys) {
    throw GradleException(
        "BP_ENV=preview requires the permanent preview signing key. " +
            "Use BP_ENV=development for local debug builds instead of producing an incompatible preview APK."
    )
}

android {
    namespace = "pl.bezpiecznapolska.bezpieczna_polska"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = when (bpEnv) {
            "production" -> "pl.bezpiecznapolska"
            "preview" -> "pl.bezpiecznapolska.preview"
            else -> "pl.bezpiecznapolska.dev"
        }
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeys) {
            create("production") {
                storeFile = file(System.getenv("ANDROID_KEYSTORE_PATH"))
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            }
        }
        if (hasPreviewKeys) {
            create("preview") {
                storeFile = file(System.getenv("ANDROID_PREVIEW_KEYSTORE_PATH"))
                storePassword = System.getenv("ANDROID_PREVIEW_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_PREVIEW_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_PREVIEW_KEY_PASSWORD")
            }
        }
    }
    buildTypes {
        debug {
            if (bpEnv == "preview" && hasPreviewKeys) {
                signingConfig = signingConfigs.getByName("preview")
            }
        }
        release {
            if (hasReleaseKeys) signingConfig = signingConfigs.getByName("production")
        }
    }
}

gradle.taskGraph.whenReady {
    if (allTasks.any { it.name.contains("Release") } &&
        (bpEnv != "production" || !hasReleaseKeys)) {
        throw GradleException("Release requires BP_ENV=production and all owner-managed signing secrets")
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
