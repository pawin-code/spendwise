import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: create android/key.properties (never commit it) with
//   storePassword=...  keyPassword=...  keyAlias=upload  storeFile=C:/path/to/upload-keystore.jks
// See docs/PLAY_STORE_RELEASE.md. Without it, release builds fall back to the
// debug key so `flutter run --release` works, but such builds CANNOT be uploaded to Google Play.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    // The namespace is the code package. The applicationId below is the Play identity.
    namespace = "in.creovix.spendwise"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (java.time on older Android versions).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Keep configurable until the first Play release: changing it afterwards creates a different app.
        // Override with: -PapplicationId=com.yourcompany.spendwise
        applicationId = (project.findProperty("applicationId") as String?) ?: "in.creovix.spendwise"
        minSdk = flutter.minSdkVersion
        // Re-check Google Play's current target API requirement before every release.
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
