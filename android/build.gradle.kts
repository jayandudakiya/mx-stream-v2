// ============================================================================
// Small APK Build Command (with .env configuration):
//
// 1. Split-per-ABI (Smallest per-device APKs, ~35-45 MB each):
//    fvm flutter build apk --split-per-abi --release --obfuscate --split-debug-info=build/app/outputs/symbols --dart-define-from-file=.env
//
// 2. Single 64-bit ARM APK (for 99% of modern phones & TV devices):
//    fvm flutter build apk --target-platform android-arm64 --release --obfuscate --split-debug-info=build/app/outputs/symbols --dart-define-from-file=.env
//
// 3. Standard Flutter (without FVM):
//    flutter build apk --split-per-abi --release --obfuscate --split-debug-info=build/app/outputs/symbols --dart-define-from-file=.env
// ============================================================================

allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") } // CloudStream library (feature/extra)
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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
