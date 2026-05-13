plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "br.uerj.bdt_uerj"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // ✅ Necessário pelo flutter_local_notifications (usa java.time)
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "br.uerj.bdt_uerj"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // multidex pode ser necessário em projetos com muitos plugins
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // ✅ Força CMake 3.31.6 (NDK 28+ requer este patch — o 3.22.1 antigo
    //    passa flags --no-rosegment/--no-undefined-version que o lld do
    //    NDK 28 rejeita, quebrando o build com CXX1429).
    externalNativeBuild {
        cmake {
            version = "3.31.6"
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ✅ Backport de APIs Java 8+ (java.time, etc.) para minSdk antigos —
    // exigido pelo flutter_local_notifications quando isCoreLibraryDesugaringEnabled = true.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
