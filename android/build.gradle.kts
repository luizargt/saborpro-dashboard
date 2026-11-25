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
// sentry_flutter 8.14.2 compila su Kotlin con `languageVersion = "1.6"`, y Kotlin 2.2
// (el mínimo del Flutter 3.47 de Shorebird) ya no lo acepta: "Language version 1.6 is
// no longer supported". Se sube a 1.8 SOLO para ese plugin, después de que él ponga
// el suyo. Va ANTES de `evaluationDependsOn`, que evalúa proyectos de antemano.
subprojects {
    if (name == "sentry_flutter") {
        val subirKotlin: Project.() -> Unit = {
            tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
                compilerOptions {
                    languageVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_8)
                    apiVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_8)
                }
            }
        }
        if (state.executed) subirKotlin() else afterEvaluate { subirKotlin() }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
