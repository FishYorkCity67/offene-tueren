import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Signierschlüssel liegt AUSSERHALB von OneDrive (C:\Users\erika\OffeneTuerenKeys).
// Ohne denselben Schlüssel lassen sich später keine Updates über die installierte App spielen.
val keyProps = Properties().apply {
    val f = file(System.getenv("OFFENE_TUEREN_KEYS") ?: "C:/Users/erika/OffeneTuerenKeys/key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "app.offenetueren.offene_tueren"
    compileSdk = 37   // flutter_local_notifications 23 verlangt mindestens 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true   // für flutter_local_notifications
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Nie ändern – sonst gilt jede neue Version als andere App.
        applicationId = "app.offenetueren"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keyProps.getProperty("storeFile") != null) {
            create("release") {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
        debug {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
