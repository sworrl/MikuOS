package com.miku.update.ota

import android.content.Context

/**
 * How a full system image gets onto the device. Today there is one path: send the user to the web
 * installer on a PC. This interface is the seam for a later on-device path.
 *
 * FUTURE: on-device A/B through update_engine (not implemented, deliberately).
 * The M500 is an A/B device, so the eventual path is android.os.UpdateEngine:
 *   - manifest gains system_update.payload { url, offset, size, headers[] } pointing at a
 *     payload.bin built by brillo_update_payload / ota_from_target_files from the MikuOS image,
 *     signed with a MikuOS OTA key whose cert is in /system/etc/security/otacerts.zip;
 *   - the update_engine binder (update_engine_service) is guarded by SELinux. Running as the
 *     system UID puts this app in system_app, which AOSP's own SystemUpdater-style clients use;
 *     check HiBy's vendor sepolicy for the find/call rules before relying on it;
 *   - applyPayload(url, offset, size, headers) streams into the inactive slot, then
 *     UpdateEngineCallback reports progress and UPDATED_NEED_REBOOT, and a reboot flips slots;
 *   - the HiBy vbmeta is flashed "disabled" (flags=3) today, so a payload must not rely on AVB
 *     verification of the new slot, and the FM app, driver patches, overlays and debloat are all
 *     inside super, so a payload covers everything the web installer does except the stock boot
 *     chain images, which would need their own partitions in the payload.
 * Until that exists and is tested on hardware, [AbUpdateEnginePath.isAvailable] is false and the
 * UI only offers [WebInstallerPath].
 */
interface SystemUpdatePath {
    /** Short label for the action button. */
    val actionLabel: String
    fun isAvailable(ctx: Context): Boolean
}

/** Full images go on from a PC through the WebUSB installer. */
class WebInstallerPath(val installerUrl: String, val build: String) : SystemUpdatePath {
    override val actionLabel = "Open the web installer"
    override fun isAvailable(ctx: Context) = true

    /** The link carries the target build so the page can preselect it. */
    fun link(): String {
        val sep = if (installerUrl.contains('?')) '&' else '?'
        return "$installerUrl${sep}build=${java.net.URLEncoder.encode(build, "UTF-8")}"
    }
}

/** Placeholder for the on-device A/B path described above. Never available yet. */
object AbUpdateEnginePath : SystemUpdatePath {
    override val actionLabel = "Install on this device"
    override fun isAvailable(ctx: Context) = false
}
