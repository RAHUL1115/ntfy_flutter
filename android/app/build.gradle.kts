plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val localSigningEnvironment = rootProject.file("../.env")
    .takeIf { it.exists() }
    ?.readLines()
    ?.mapNotNull { line ->
        val separator = line.indexOf('=')
        if (separator <= 0 || line.trimStart().startsWith("#")) null
        else line.substring(0, separator).trim() to line.substring(separator + 1)
    }
    ?.toMap()
    .orEmpty()

val releaseKeystorePath = System.getenv("ANDROID_KEYSTORE_PATH")
    ?: localSigningEnvironment["ANDROID_KEYSTORE_PATH"]
val releaseKeystorePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
    ?: localSigningEnvironment["ANDROID_KEYSTORE_PASSWORD"]
val releaseKeyAlias = System.getenv("ANDROID_KEY_ALIAS")
    ?: localSigningEnvironment["ANDROID_KEY_ALIAS"]
val hasReleaseSigning = listOf(
    releaseKeystorePath,
    releaseKeystorePassword,
    releaseKeyAlias,
).all { !it.isNullOrBlank() && it != "YOUR_SIGNING_KEY_PASSWORD" }

android {
    namespace = "com.rahul1115.ntfy_flutter"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.rahul1115.ntfy_flutter"
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
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseKeystorePath!!)
                storePassword = releaseKeystorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeystorePassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
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
    androidTestImplementation("androidx.test:runner:1.3.0")
}
