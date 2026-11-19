import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The release key, kept out of git: android/key.properties (storeFile,
// storePassword, keyAlias, keyPassword), or the same as environment
// variables (ANDROID_KEYSTORE, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS,
// ANDROID_KEY_PASSWORD) on a build machine. Without either, a release build
// is signed with the debug key, which no store accepts.
val releaseKey: Map<String, String>? = run {
    val file = rootProject.file("key.properties")
    if (file.exists()) {
        val props = Properties().apply { file.inputStream().use { load(it) } }
        mapOf(
            "storeFile" to props.getProperty("storeFile"),
            "storePassword" to props.getProperty("storePassword"),
            "keyAlias" to props.getProperty("keyAlias"),
            "keyPassword" to props.getProperty("keyPassword"),
        ).takeIf { m -> m.values.all { !it.isNullOrBlank() } }?.mapValues { it.value!! }
    } else {
        val env = System.getenv()
        mapOf(
            "storeFile" to env["ANDROID_KEYSTORE"],
            "storePassword" to env["ANDROID_KEYSTORE_PASSWORD"],
            "keyAlias" to env["ANDROID_KEY_ALIAS"],
            "keyPassword" to env["ANDROID_KEY_PASSWORD"],
        ).takeIf { m -> m.values.all { !it.isNullOrBlank() } }?.mapValues { it.value!! }
    }
}

android {
    namespace = "com.example.avalon_shadow_council"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.avalon_shadow_council"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseKey != null) {
            create("release") {
                storeFile = file(releaseKey.getValue("storeFile"))
                storePassword = releaseKey.getValue("storePassword")
                keyAlias = releaseKey.getValue("keyAlias")
                keyPassword = releaseKey.getValue("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseKey != null) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("No release key (android/key.properties): release build signed with the debug key")
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}
