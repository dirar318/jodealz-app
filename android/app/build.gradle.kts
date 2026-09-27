import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    // Uploads R8 mapping files so Crashlytics stack traces are readable.
    id("com.google.firebase.crashlytics")
}

// Release signing (upload key), in order of precedence:
//  1. Codemagic: android_signing in codemagic.yaml exports CM_KEYSTORE_PATH,
//     CM_KEYSTORE_PASSWORD, CM_KEY_ALIAS and CM_KEY_PASSWORD.
//  2. Local: android/key.properties (git-ignored) with storeFile, storePassword,
//     keyAlias, keyPassword.
// Without either, release builds are left unsigned — never debug-signed — so a
// debug-signed bundle can't reach Google Play by accident.
data class ReleaseSigning(val storeFile: String, val storePassword: String, val keyAlias: String, val keyPassword: String)

val releaseSigning: ReleaseSigning? = run {
    val env = System.getenv()
    val cmKeystore = env["CM_KEYSTORE_PATH"]
    if (!cmKeystore.isNullOrBlank()) {
        return@run ReleaseSigning(
            storeFile = cmKeystore,
            storePassword = env["CM_KEYSTORE_PASSWORD"] ?: error("CM_KEYSTORE_PASSWORD is not set"),
            keyAlias = env["CM_KEY_ALIAS"] ?: error("CM_KEY_ALIAS is not set"),
            keyPassword = env["CM_KEY_PASSWORD"] ?: error("CM_KEY_PASSWORD is not set"),
        )
    }
    val keyPropertiesFile = rootProject.file("key.properties")
    if (!keyPropertiesFile.exists()) return@run null
    val props = Properties().apply { keyPropertiesFile.inputStream().use { load(it) } }
    ReleaseSigning(
        storeFile = rootProject.file("app").resolve(props.getProperty("storeFile")).path,
        storePassword = props.getProperty("storePassword"),
        keyAlias = props.getProperty("keyAlias"),
        keyPassword = props.getProperty("keyPassword"),
    )
}

android {
    namespace = "com.jodealz.app"
    // Pinned so CI builds don't depend on the Flutter SDK's defaults.
    // Google Play requires targeting API 36 for new apps and updates from Aug 31, 2026.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        if (releaseSigning != null) {
            create("release") {
                storeFile = file(releaseSigning.storeFile)
                storePassword = releaseSigning.storePassword
                keyAlias = releaseSigning.keyAlias
                keyPassword = releaseSigning.keyPassword
            }
        }
    }

    defaultConfig {
        applicationId = "com.jodealz.app"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        // From pubspec.yaml "version: x.y.z+N", overridden in CI by
        // `flutter build appbundle --build-name ... --build-number ...`.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = if (releaseSigning != null) signingConfigs.getByName("release") else null
            isDebuggable = false
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}
