import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// The OTA public keys live in one place, mikuos/ota/keys, next to the publish tooling. They are
// copied into the APK's assets at build time by exact file name. Never a wildcard: nothing else
// in that directory (or anything someone drops there by mistake) can end up inside the APK.
val otaKeyNames = listOf("ota-signing-primary-p521.pub.pem", "ota-signing-backup-p521.pub.pem")
val otaKeyAssetsDir = layout.buildDirectory.dir("generated/otaKeys")
val copyOtaKeys = tasks.register<Copy>("copyOtaKeys") {
    val keyDir = rootProject.file("../mikuos/ota/keys")
    doFirst {
        otaKeyNames.forEach { name ->
            val f = File(keyDir, name)
            require(f.isFile) { "missing OTA public key ${f.path}" }
            val text = f.readText()
            require(text.contains("BEGIN PUBLIC KEY") && !text.contains("PRIVATE")) {
                "${f.path} is not a public key PEM; refusing to package it"
            }
        }
    }
    from(keyDir) { otaKeyNames.forEach { include(it) } }
    into(otaKeyAssetsDir.map { it.dir("ota-keys") })
}

android {
    namespace = "com.miku.update"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.miku.update"
        minSdk = 26
        targetSdk = 34
        versionCode = 3
        versionName = "0.3.0"
    }

    sourceSets["main"].assets.srcDir(otaKeyAssetsDir)

    // Same signing pattern as miku-sysbridge: the platform key, because this app runs as the
    // system UID (sharedUserId android.uid.system) and that only installs when platform-signed.
    val signingProps = Properties().apply {
        val candidates = listOf(
            rootProject.file("../keystore.properties"),
            rootProject.file("keystore.properties"),
            rootProject.file("local.properties")
        )
        for (f in candidates) {
            if (f.exists()) {
                f.inputStream().use { load(it) }
                break
            }
        }
    }
    val platformStorePath: String? = signingProps.getProperty("platform.storeFile")
    val platformStoreFile = platformStorePath?.let { path: String ->
        listOf(
            rootProject.file("../$path"),
            rootProject.file(path),
            file(path)
        ).firstOrNull { it.exists() }
    }
    val platformStorePass: String? = signingProps.getProperty("platform.storePassword")
    val platformKeyAlias: String = signingProps.getProperty("platform.keyAlias", "platform")
    val platformKeyPass: String? = signingProps.getProperty("platform.keyPassword")
    val hasPlatformSigning = platformStoreFile != null && platformStorePass != null && platformKeyPass != null

    signingConfigs {
        if (hasPlatformSigning) {
            create("platform") {
                storeFile = platformStoreFile
                storePassword = platformStorePass
                keyAlias = platformKeyAlias
                keyPassword = platformKeyPass
                enableV1Signing = false
                enableV2Signing = true
                enableV3Signing = true
                enableV4Signing = true
            }
        }
    }

    buildTypes {
        debug {
            if (hasPlatformSigning) {
                signingConfig = signingConfigs.getByName("platform")
            }
        }
        release {
            if (hasPlatformSigning) {
                signingConfig = signingConfigs.getByName("platform")
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }

    lint {
        disable += setOf(
            "ProtectedPermissions", "MissingPermission", "NewApi", "RestrictedApi",
            "UnspecifiedRegisterReceiverFlag", "QueryAllPackagesPermission", "RequestInstallPackagesPolicy"
        )
        abortOnError = false
    }

    applicationVariants.all {
        outputs.all {
            if (this is com.android.build.gradle.internal.api.BaseVariantOutputImpl) {
                outputFileName = "MikuUpdate.apk"
            }
        }
    }
}

tasks.named("preBuild") { dependsOn(copyOtaKeys) }

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.09.02"))
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.6")
    implementation("androidx.work:work-runtime-ktx:2.9.1")
    implementation("com.google.zxing:core:3.5.3")
}
