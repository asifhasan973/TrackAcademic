import java.util.Base64

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.trackademic.trackademic"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.trackademic.trackademic"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        manifestPlaceholders["usesCleartextTraffic"] = "false"
    }

    buildTypes {
        debug {
            manifestPlaceholders["usesCleartextTraffic"] = "true"
        }
        release {
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

            val dartDefines = project.findProperty("dart-defines") as? String
            val isEmulatorFromDefines = dartDefines?.let { raw ->
                raw.split(",").any { part ->
                    try {
                        val decoded = String(Base64.getDecoder().decode(part.trim()), Charsets.UTF_8)
                        decoded.contains("USE_FIREBASE_EMULATORS=true")
                    } catch (_: Exception) {
                        false
                    }
                }
            } ?: false
            val isDemoEnv = System.getenv("DEMO_BUILD") == "true" || System.getenv("USE_FIREBASE_EMULATORS") == "true"

            manifestPlaceholders["usesCleartextTraffic"] = if (isEmulatorFromDefines || isDemoEnv) "true" else "false"
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

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
}
