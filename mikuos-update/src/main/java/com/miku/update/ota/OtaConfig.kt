package com.miku.update.ota

/**
 * Fixed facts about the OTA system. The server layout and the manifest format are documented in
 * mikuos/ota/README.md; keep the two in step.
 */
object OtaConfig {
    /** Where the channels live: <base>/<channel>/manifest.json and manifest.json.sig. */
    const val DEFAULT_BASE_URL = "https://mikuos.falcontechnix.com/ota/"

    /** Where a full image goes on. Used when a manifest does not name its own installer_url. */
    const val DEFAULT_INSTALLER_URL = "https://mikuos.falcontechnix.com/install/"

    val CHANNELS = listOf("stable", "beta", "dev")
    const val DEFAULT_CHANNEL = "stable"

    /** The manifest schema this app understands. A higher number is refused, not guessed at. */
    const val SCHEMA_VERSION = 1

    /** Assets copied from mikuos/ota/keys at build time (see build.gradle.kts). */
    val KEY_ASSETS = listOf(
        "primary" to "ota-keys/ota-signing-primary-p521.pub.pem",
        "backup" to "ota-keys/ota-signing-backup-p521.pub.pem",
    )

    /** Hard cap on the manifest download. A real one is a few KB. */
    const val MAX_MANIFEST_BYTES = 512 * 1024
    const val MAX_SIGNATURE_BYTES = 4 * 1024

    /**
     * Packages that must only ever come from the system image. A /data copy of the FM app loses
     * the shared linker namespace its JNI needs and the tuner stops working, so it is refused here
     * whatever a manifest says, and the publish script refuses to list it too.
     */
    val NEVER_UPDATE = setOf("com.caf.fmradio")

    /** Packages this app may update: MikuOS's own apps and nothing else. */
    fun isUpdatable(pkg: String): Boolean {
        if (pkg in NEVER_UPDATE) return false
        return pkg.startsWith("com.miku.") || pkg == "com.m500.hardware"
    }

    /** Friendly names for the list. Unknown packages fall back to the package name. */
    fun displayName(pkg: String): String = when (pkg) {
        "com.miku.player" -> "Miku Music"
        "com.miku.launcher" -> "Miku Launcher"
        "com.miku.settings" -> "MikuOS Settings"
        "com.miku.systemui" -> "MikuOS System UI"
        "com.m500.hardware" -> "Hardware Settings"
        "com.miku.sysbridge" -> "System Bridge"
        "com.miku.tools" -> "Miku Tools"
        "com.miku.media" -> "Miku Media"
        "com.miku.update" -> "Miku Update"
        "com.miku.tv" -> "Miku TV"
        else -> pkg
    }
}
