import java.util.Properties

// Release signing comes from android/key.properties (never committed; see
// docs/release.md). Without it a release build fails rather than silently
// shipping with debug keys.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null
val allowDebugSigning = System.getenv("READING_LIBRARY_DEBUG_SIGNING") == "1"

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.readingroom.reading_library"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Placeholder. Set the real, permanent ID with tool/set_bundle_id.sh
        // before the first store upload; it cannot be changed afterwards.
        applicationId = "app.readingroom.reading_library"
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
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = when {
                hasReleaseKey -> signingConfigs.getByName("release")
                // Local smoke builds only; Google Play rejects debug-signed bundles.
                allowDebugSigning -> signingConfigs.getByName("debug")
                else -> null
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

gradle.taskGraph.whenReady {
    val releaseBuild = allTasks.any {
        it.project == project && it.name.contains("Release") && it.name.startsWith("assemble") ||
            it.project == project && it.name.startsWith("bundle") && it.name.endsWith("Release")
    }
    if (releaseBuild && !hasReleaseKey && !allowDebugSigning) {
        throw GradleException(
            "No release signing key. Create android/key.properties (see docs/release.md), " +
                "or set READING_LIBRARY_DEBUG_SIGNING=1 for a local, non-uploadable build."
        )
    }
}
