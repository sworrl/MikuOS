// Miku Voice Check: a dev tool for reviewing the generated voice clips and sound effects on the
// device itself. Not part of the image; installed with adb. It bundles the clips straight from
// ../mikuos/data at build time, so it always plays what the pipeline last rendered.
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

val soundsSrc = rootProject.file("../mikuos/data")
val genAssets = layout.buildDirectory.dir("generated/voicecheckAssets")
val copySounds by tasks.registering(Copy::class) {
    from(soundsSrc) { include("voice/**", "sfx/**", "sounds_index.json") }
    into(genAssets)
}

android {
    namespace = "com.miku.voicecheck"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.miku.voicecheck"
        minSdk = 30
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"
    }
    sourceSets["main"].assets.srcDir(genAssets)
    // MediaPlayer plays straight from the APK via openFd, which needs the clips stored as-is.
    androidResources { noCompress += listOf("ogg", "opus") }
    buildFeatures { compose = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    lint { abortOnError = false }
    applicationVariants.all {
        outputs.all {
            if (this is com.android.build.gradle.internal.api.BaseVariantOutputImpl) outputFileName = "MikuVoiceCheck.apk"
        }
    }
}
tasks.matching { (it.name.startsWith("merge") && it.name.endsWith("Assets")) || it.name.contains("LintVital") }.configureEach { dependsOn(copySounds) }

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.09.02"))
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.core:core-ktx:1.13.1")
}
