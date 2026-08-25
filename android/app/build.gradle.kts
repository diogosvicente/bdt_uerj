import java.io.FileInputStream
import java.util.Properties

/*
 * A chave de assinatura do release, lida de android/key.properties.
 *
 * O arquivo NAO esta no repositorio, e nao pode estar: ele carrega as senhas
 * do keystore. O .gitignore do Flutter ja barra key.properties, *.jks e
 * *.keystore. Ver android/key.properties.example para o formato.
 *
 * Sem o arquivo, o build NAO quebra: cai para a chave de debug, para que
 * `flutter run --release` continue funcionando em maquina que nao tem a
 * chave. O aviso abaixo existe porque essa queda e silenciosa por natureza, e
 * um APK de debug distribuido parece igual a um assinado de verdade.
 */
val arquivoChave = rootProject.file("key.properties")
val temChave = arquivoChave.exists()
val propsChave = Properties()

if (temChave) {
    FileInputStream(arquivoChave).use { propsChave.load(it) }
} else {
    logger.warn(
        "AVISO: android/key.properties nao encontrado. O release sera assinado " +
        "com a CHAVE DE DEBUG, que e publica. Nao distribua este APK."
    )
}

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

    signingConfigs {
        // So existe quando ha key.properties. Criar sempre exigiria valores
        // que nao temos, e o build quebraria em quem nao tem a chave.
        if (temChave) {
            create("release") {
                keyAlias = propsChave.getProperty("keyAlias")
                keyPassword = propsChave.getProperty("keyPassword")
                storeFile = propsChave.getProperty("storeFile")?.let { file(it) }
                storePassword = propsChave.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (temChave) {
                signingConfigs.getByName("release")
            } else {
                // Ver a nota no topo do arquivo: queda consciente, com aviso.
                signingConfigs.getByName("debug")
            }
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
