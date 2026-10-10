package com.miku.update.ota

import org.json.JSONObject
import java.time.Instant

/** The signed manifest. Schema in mikuos/ota/README.md. Parsed only after the signature checks out. */
data class OtaManifest(
    val schemaVersion: Int,
    val channel: String,
    val build: String,
    val minBuild: String?,
    val publishedAt: Instant,
    val changelog: String,
    val systemUpdate: SystemUpdate?,
    val apks: List<ApkEntry>,
    /** Releases pulled after the fact. A device running one of these goes back to its image copy. */
    val revoked: List<Revoked> = emptyList(),
) {
    data class Revoked(val packageName: String, val versionCode: Long, val reason: String)

    fun isRevoked(pkg: String, vc: Long) = revoked.any { it.packageName == pkg && it.versionCode == vc }

    data class SystemUpdate(
        val required: Boolean,
        val build: String,
        val notes: String,
        val installerUrl: String,
    )

    data class ApkEntry(
        val packageName: String,
        val versionCode: Long,
        val versionName: String,
        val url: String,
        val size: Long,
        val sha256: String,
        val minSdk: Int,
        val requiresBuild: String?,
    )

    companion object {
        private val HEX64 = Regex("^[0-9a-f]{64}$")

        /** org.json's optString turns a JSON null into the text "null"; this does not. */
        private fun JSONObject.str(name: String): String? =
            if (isNull(name)) null else optString(name, "").ifBlank { null }

        fun parse(bytes: ByteArray): OtaManifest {
            val o = JSONObject(String(bytes, Charsets.UTF_8))
            val schema = o.getInt("schema_version")
            require(schema in 1..OtaConfig.SCHEMA_VERSION) {
                "This manifest uses format $schema and this app only knows ${OtaConfig.SCHEMA_VERSION}. Update Miku Update with a full system image."
            }
            val su = (if (o.isNull("system_update")) null else o.optJSONObject("system_update"))?.let {
                SystemUpdate(
                    required = it.optBoolean("required", false),
                    build = it.getString("build"),
                    notes = it.str("notes") ?: "",
                    installerUrl = it.str("installer_url") ?: OtaConfig.DEFAULT_INSTALLER_URL,
                )
            }
            val arr = o.optJSONArray("apks")
            val apks = buildList {
                if (arr != null) for (i in 0 until arr.length()) {
                    val a = arr.getJSONObject(i)
                    val sha = a.getString("sha256").lowercase()
                    require(HEX64.matches(sha)) { "Bad sha256 for ${a.optString("package")}" }
                    val size = a.getLong("size")
                    require(size > 0) { "Bad size for ${a.optString("package")}" }
                    add(
                        ApkEntry(
                            packageName = a.getString("package"),
                            versionCode = a.getLong("versionCode"),
                            versionName = a.str("versionName") ?: "",
                            url = a.getString("url"),
                            size = size,
                            sha256 = sha,
                            minSdk = a.optInt("min_sdk", 0),
                            requiresBuild = a.str("requires_build"),
                        )
                    )
                }
            }
            val rarr = o.optJSONArray("revoked")
            val revoked = buildList {
                if (rarr != null) for (i in 0 until rarr.length()) {
                    val r = rarr.getJSONObject(i)
                    add(Revoked(r.getString("package"), r.getLong("versionCode"), r.str("reason") ?: ""))
                }
            }
            return OtaManifest(
                schemaVersion = schema,
                channel = o.getString("channel"),
                build = o.getString("build"),
                minBuild = o.str("min_build"),
                publishedAt = Instant.parse(o.getString("published_at")),
                changelog = o.str("changelog") ?: "",
                systemUpdate = su,
                apks = apks,
                revoked = revoked,
            )
        }
    }
}
