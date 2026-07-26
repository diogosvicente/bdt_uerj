allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Sprint 15 W+M housekeeping (2026-07-26) — muitos plugins Flutter
// ainda declaram `sourceCompatibility = JavaVersion.VERSION_1_8` (Java 8)
// nos próprios build.gradle. O compilador atual (Java 17+) trata Java 8
// como obsoleto e imprime 3 warnings por plugin a cada build:
//   warning: [options] source value 8 is obsolete ...
//   warning: [options] target value 8 is obsolete ...
//   warning: [options] To suppress warnings about obsolete options, ...
//
// Como o app já roda em Java 11, forçamos todos os subprojetos Android
// (plugins) a subirem pra 11 também. Cobre AppExtension e LibraryExtension
// via ancestral comum `BaseExtension`. Se um plugin no futuro exigir Java 8
// especificamente (improvável — Flutter atual exige 11 mínimo), este
// override quebra localmente e a gente reavalia.
//
// IMPORTANTE: o override precisa ser registrado ANTES do `evaluationDependsOn`
// abaixo (senão o Gradle já avaliou o projeto e recusa `afterEvaluate`).
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt is com.android.build.gradle.BaseExtension) {
            androidExt.compileOptions.apply {
                sourceCompatibility = JavaVersion.VERSION_11
                targetCompatibility = JavaVersion.VERSION_11
            }
        }
        // Alguns plugins (ex.: image_picker_android) já subiram o Kotlin
        // pra jvmTarget=17 sem subir o Java junto — mismatch quebra o
        // build com "Inconsistent JVM Target Compatibility". Alinhamos
        // TODOS os tasks Kotlin em 11 pra bater com o Java.
        // Kotlin 2.x removeu `kotlinOptions` — usamos `compilerOptions`.
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
