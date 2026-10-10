package com.miku.update.ota

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext
import java.io.File
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Check, download, verify, install, roll back. One operation at a time (the UI and the scheduled
 * worker share this object). Everything the UI shows comes out of [state].
 *
 * Order of trust for a check:
 *   manifest.json + manifest.json.sig fetched  ->  signature verified with an embedded P-521 key
 *   ->  only then parsed  ->  channel must match  ->  published_at must not go backwards.
 * Order for each APK:
 *   download (resume) -> size + SHA-256 equal the signed manifest -> ApkVerifier (package name,
 *   versionCode, system app in this image, same signing certificate) -> keep the old APK for
 *   rollback -> PackageInstaller session.
 */
object OtaEngine {
    private const val TAG = "MikuUpdate"

    enum class Phase { READY, BLOCKED, HELD, DOWNLOADING, VERIFYING, INSTALLING, DONE, FAILED }

    data class Item(
        val entry: OtaManifest.ApkEntry,
        val name: String,
        val installedVersionCode: Long,
        val installedVersionName: String,
        val phase: Phase,
        val done: Long = 0,
        val message: String = "",
    )

    data class InstalledApp(
        val pkg: String,
        val name: String,
        val versionCode: Long,
        val versionName: String,
        val isUpdate: Boolean,
        val imageVersionName: String?,
        val imageVersionCode: Long?,
        val kept: RollbackStore.Kept?,
    )

    data class State(
        val busy: String? = null,
        val deviceBuild: String? = BuildInfo.mikuosVersion(),
        val manifest: OtaManifest? = null,
        val signedBy: String? = null,
        val error: String? = null,
        val items: List<Item> = emptyList(),
        val blockedByMinBuild: Boolean = false,
        val systemUpdate: OtaManifest.SystemUpdate? = null,
        val installed: List<InstalledApp> = emptyList(),
        val notice: String? = null,
    ) {
        val installable get() = items.filter { it.phase == Phase.READY || it.phase == Phase.FAILED || it.phase == Phase.HELD }
    }

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state

    private val mutex = Mutex()
    private val cancel = AtomicBoolean(false)
    private var manifestUrl: URL? = null

    fun requestCancel() = cancel.set(true)

    private suspend fun <T> exclusive(label: String, block: suspend () -> T): T? {
        if (!mutex.tryLock()) {
            _state.update { it.copy(notice = "Already busy: ${it.busy ?: "working"}") }
            return null
        }
        cancel.set(false)
        _state.update { it.copy(busy = label, notice = null) }
        try {
            return withContext(Dispatchers.IO) { block() }
        } finally {
            _state.update { it.copy(busy = null) }
            mutex.unlock()
        }
    }

    // ---------------------------------------------------------------- check

    suspend fun check(ctx: Context): Boolean = exclusive("Checking for updates") {
        doCheck(ctx).also { ok -> if (ok) applyRevocations(ctx) }
    } ?: false

    /**
     * A signed manifest can pull a release: any app running a revoked versionCode as a /data
     * update gets that update removed (back to the image copy) and the version held, so it is not
     * installed again. Android cannot downgrade in place on a user build; this is the only way
     * back that does not need the user.
     */
    private suspend fun applyRevocations(ctx: Context) {
        val m = _state.value.manifest ?: return
        if (m.revoked.isEmpty()) return
        val prefs = Prefs(ctx)
        val pulled = mutableListOf<String>()
        val targets = m.revoked.filter { OtaConfig.isUpdatable(it.packageName) }
            .sortedBy { it.packageName == ctx.packageName } // ourselves last: it ends this process
        for (r in targets) {
            val info = ApkVerifier.installedInfo(ctx, r.packageName) ?: continue
            if (!ApkVerifier.isUpdatedSystemApp(info) || ApkVerifier.longVersion(info) != r.versionCode) continue
            prefs.setHeldVersion(r.packageName, maxOf(prefs.heldVersion(r.packageName), r.versionCode))
            if (r.packageName == ctx.packageName) Notifier.revoked(ctx, listOf(lineFor(r)))
            val res = Installer.uninstallUpdates(ctx, r.packageName)
            if (res.ok) {
                RollbackStore(ctx).forget(r.packageName)
                pulled += lineFor(r)
            } else {
                Log.w(TAG, "could not pull ${r.packageName} ${r.versionCode}: ${res.message}")
            }
        }
        if (pulled.isNotEmpty()) {
            Notifier.revoked(ctx, pulled)
            refreshInstalled(ctx)
            _state.update { it.copy(items = planItems(ctx, m, BuildInfo.mikuosVersion(), it.blockedByMinBuild)) }
        }
    }

    private fun lineFor(r: OtaManifest.Revoked) =
        OtaConfig.displayName(r.packageName) + if (r.reason.isNotBlank()) ": ${r.reason}" else ""

    private fun doCheck(ctx: Context): Boolean {
        val prefs = Prefs(ctx)
        val channel = prefs.channel
        val device = BuildInfo.mikuosVersion()
        _state.update { it.copy(deviceBuild = device, error = null) }
        refreshInstalled(ctx)
        return try {
            val mUrl = URL(prefs.baseUrl + "$channel/manifest.json")
            val sUrl = URL(prefs.baseUrl + "$channel/manifest.json.sig")
            val verifier = SignatureVerifier.load(ctx)
            var bytes = ByteArray(0)
            var signedBy: String? = null
            // Two tries: a publish swaps manifest.json and its .sig one after the other, and a
            // check landing in between gets a mismatched pair. A second fetch a moment later
            // gets a matching one. A real forgery fails both times.
            for (attempt in 1..2) {
                bytes = Http.getBytes(mUrl, OtaConfig.MAX_MANIFEST_BYTES)
                val sig = Http.getBytes(sUrl, OtaConfig.MAX_SIGNATURE_BYTES)
                signedBy = verifier.verify(bytes, sig)
                if (signedBy != null) break
                if (attempt == 1) Thread.sleep(3_000)
            }
            if (signedBy == null) {
                throw SecurityException("The update list's signature did not check out, so it was ignored. If this keeps happening, the server or the connection is not trustworthy.")
            }
            val m = OtaManifest.parse(bytes)
            if (m.channel != channel) throw SecurityException("The server sent the ${m.channel} list when $channel was asked for, so it was ignored.")
            val seen = prefs.lastPublished(channel)
            if (m.publishedAt.epochSecond < seen) {
                throw SecurityException("The server sent an older update list than one this device already saw, so it was ignored.")
            }
            prefs.setLastPublished(channel, m.publishedAt.epochSecond)
            manifestUrl = mUrl

            val blocked = BuildInfo.isOlder(device, m.minBuild)
            val items = planItems(ctx, m, device, blocked)
            val su = m.systemUpdate?.takeIf { BuildInfo.isOlder(device, it.build) }
                ?: if (blocked) OtaManifest.SystemUpdate(true, m.minBuild!!, "", OtaConfig.DEFAULT_INSTALLER_URL) else null

            _state.update {
                it.copy(manifest = m, signedBy = signedBy, items = items, blockedByMinBuild = blocked, systemUpdate = su, error = null)
            }
            pruneCache(ctx, items)
            prefs.lastCheckMillis = System.currentTimeMillis()
            prefs.lastResult = when {
                items.isEmpty() && su == null -> "Up to date"
                else -> "${items.size} app update(s)" + if (su != null) ", system update ${su.build}" else ""
            }
            true
        } catch (e: Exception) {
            Log.w(TAG, "check failed", e)
            val msg = when (e) {
                is SecurityException -> e.message
                is java.net.UnknownHostException -> "Could not reach the update server. Check the connection."
                is java.io.IOException -> "Could not get the update list: ${e.message}"
                else -> "The update list could not be read: ${e.message}"
            }
            _state.update { it.copy(error = msg) }
            prefs.lastCheckMillis = System.currentTimeMillis()
            prefs.lastResult = "Check failed"
            false
        }
    }

    /** Drops downloads (and partial ones) that no longer match anything on offer. */
    private fun pruneCache(ctx: Context, items: List<Item>) {
        val keep = items.map { "${it.entry.packageName}-${it.entry.versionCode}.apk" }.toSet()
        File(ctx.cacheDir, "ota").listFiles()?.forEach { f ->
            if (f.name.removeSuffix(".part") !in keep) f.delete()
        }
    }

    private fun planItems(ctx: Context, m: OtaManifest, device: String?, blocked: Boolean): List<Item> {
        val prefs = Prefs(ctx)
        // One entry per package: the highest versionCode wins.
        val newest = m.apks.filter { OtaConfig.isUpdatable(it.packageName) }
            .groupBy { it.packageName }
            .mapValues { (_, v) -> v.maxBy { it.versionCode } }
            .values
        val out = mutableListOf<Item>()
        for (e in newest) {
            val installed = ApkVerifier.installedInfo(ctx, e.packageName) ?: continue // not in this image
            if (!ApkVerifier.isSystemApp(installed)) continue
            val ivc = ApkVerifier.longVersion(installed)
            if (e.versionCode <= ivc) continue
            if (m.isRevoked(e.packageName, e.versionCode)) continue
            val (phase, why) = when {
                blocked -> Phase.BLOCKED to "Needs MikuOS ${m.minBuild} first"
                BuildInfo.isOlder(device, e.requiresBuild) -> Phase.BLOCKED to "Needs MikuOS ${e.requiresBuild} first"
                e.minSdk > Build.VERSION.SDK_INT -> Phase.BLOCKED to "Needs a newer Android"
                e.versionCode <= prefs.heldVersion(e.packageName) -> Phase.HELD to "Held back after a rollback"
                else -> Phase.READY to ""
            }
            out += Item(e, OtaConfig.displayName(e.packageName), ivc, installed.versionName ?: "", phase, message = why)
        }
        // Miku Update itself goes last: installing it ends this process.
        return out.sortedWith(compareBy<Item> { it.entry.packageName == ctx.packageName }.thenBy { it.name })
    }

    // ---------------------------------------------------------------- install

    /** Installs every READY item ([includeHeld] also takes HELD ones, for a manual "install all"). */
    suspend fun installAll(ctx: Context, includeHeld: Boolean): List<String> =
        exclusive("Installing updates") {
            val targets = _state.value.items.filter {
                it.phase == Phase.READY || it.phase == Phase.FAILED || (includeHeld && it.phase == Phase.HELD)
            }.map { it.entry.packageName }
            doInstall(ctx, targets)
        } ?: emptyList()

    suspend fun installOne(ctx: Context, pkg: String): List<String> =
        exclusive("Installing ${OtaConfig.displayName(pkg)}") { doInstall(ctx, listOf(pkg)) } ?: emptyList()

    private suspend fun doInstall(ctx: Context, pkgs: List<String>): List<String> {
        val prefs = Prefs(ctx)
        val rollback = RollbackStore(ctx)
        val base = manifestUrl ?: return emptyList()
        val done = mutableListOf<String>()
        val ordered = pkgs.sortedBy { it == ctx.packageName }
        for (pkg in ordered) {
            if (cancel.get()) break
            val item = _state.value.items.firstOrNull { it.entry.packageName == pkg } ?: continue
            if (item.phase == Phase.BLOCKED || item.phase == Phase.DONE) continue
            val e = item.entry
            try {
                val dir = File(ctx.cacheDir, "ota").apply { mkdirs() }
                val apk = File(dir, "${e.packageName}-${e.versionCode}.apk")
                if (!(apk.isFile && apk.length() == e.size && Http.sha256(apk) == e.sha256)) {
                    setItem(pkg) { it.copy(phase = Phase.DOWNLOADING, done = File(apk.path + ".part").length(), message = "") }
                    val sha = Http.download(
                        URL(base, e.url), apk, e.size,
                        onProgress = { d, _ -> setItem(pkg) { it.copy(done = d) } },
                        isCancelled = { cancel.get() },
                    )
                    if (sha != e.sha256) {
                        apk.delete()
                        throw ApkVerifier.Refused("The download did not match its signed hash, so it was thrown away")
                    }
                }
                setItem(pkg) { it.copy(phase = Phase.VERIFYING, done = e.size) }
                ApkVerifier.verify(ctx, apk, e.packageName, e.versionCode)
                val now = ApkVerifier.installedInfo(ctx, pkg)
                if (now != null && ApkVerifier.longVersion(now) >= e.versionCode) {
                    setItem(pkg) { it.copy(phase = Phase.DONE, message = "Already installed") }
                    apk.delete()
                    continue
                }
                rollback.keepCurrent(pkg)
                setItem(pkg) { it.copy(phase = Phase.INSTALLING) }
                val r = Installer.install(ctx, apk, pkg)
                if (r.ok) {
                    apk.delete()
                    if (e.versionCode > prefs.heldVersion(pkg)) prefs.clearHeld(pkg)
                    setItem(pkg) { it.copy(phase = Phase.DONE, message = "Installed") }
                    done += "${item.name} ${e.versionName}".trim()
                } else {
                    setItem(pkg) { it.copy(phase = Phase.FAILED, message = r.message) }
                }
            } catch (ex: Exception) {
                Log.w(TAG, "install $pkg failed", ex)
                val msg = if (ex is ApkVerifier.Refused) ex.message ?: "Refused" else "Failed: ${ex.message ?: ex.javaClass.simpleName}"
                setItem(pkg) { it.copy(phase = Phase.FAILED, message = msg) }
            }
        }
        refreshInstalled(ctx)
        if (done.isNotEmpty()) {
            Notifier.clearAvailable(ctx)
            Notifier.installed(ctx, done)
        }
        return done
    }

    private fun setItem(pkg: String, f: (Item) -> Item) {
        _state.update { s -> s.copy(items = s.items.map { if (it.entry.packageName == pkg) f(it) else it }) }
    }

    // ---------------------------------------------------------------- rollback

    /**
     * [toImage] true: remove the /data update, back to the system image copy.
     * [toImage] false: back to the APK that ran before the last update (uninstall, then install
     * the kept copy if it is newer than the image). Either way the version walked away from is
     * held, so automatic installs do not put it straight back.
     */
    suspend fun rollback(ctx: Context, pkg: String, toImage: Boolean): String =
        exclusive("Rolling back ${OtaConfig.displayName(pkg)}") { doRollback(ctx, pkg, toImage) } ?: "Busy"

    private suspend fun doRollback(ctx: Context, pkg: String, toImage: Boolean): String {
        val prefs = Prefs(ctx)
        val store = RollbackStore(ctx)
        val info = ApkVerifier.installedInfo(ctx, pkg) ?: return "Not installed"
        if (!OtaConfig.isUpdatable(pkg)) return "Not a MikuOS app"
        if (!ApkVerifier.isUpdatedSystemApp(info)) return "Already on the image version"
        val fromVc = ApkVerifier.longVersion(info)
        val kept = if (toImage || pkg == ctx.packageName) null else store.kept(pkg)

        // Check the kept APK before removing anything, so a bad copy never leaves the user worse off.
        if (kept != null) {
            if (Http.sha256(kept.file) != kept.sha256) {
                store.forget(pkg)
                return "The saved copy was damaged. Use \"Back to image version\" instead."
            }
            try {
                ApkVerifier.verify(ctx, kept.file, pkg, kept.versionCode)
            } catch (e: ApkVerifier.Refused) {
                return e.message ?: "The saved copy was refused"
            }
        }

        val r = Installer.uninstallUpdates(ctx, pkg)
        if (!r.ok) return "Could not remove the update: ${r.message}"
        prefs.setHeldVersion(pkg, fromVc)

        var result = "Back on the image version"
        if (kept != null) {
            val image = ApkVerifier.installedInfo(ctx, pkg)
            val imageVc = image?.let { ApkVerifier.longVersion(it) } ?: 0L
            if (kept.versionCode > imageVc) {
                val r2 = Installer.install(ctx, kept.file, pkg)
                result = if (r2.ok) "Back on ${kept.versionName.ifBlank { kept.versionCode.toString() }}"
                else "Back on the image version. The previous update would not reinstall: ${r2.message}"
            }
        }
        store.forget(pkg)
        refreshInstalled(ctx)
        // The list of updates is stale now that versions moved; re-plan against the last manifest.
        _state.value.manifest?.let { m ->
            val blocked = _state.value.blockedByMinBuild
            _state.update { it.copy(items = planItems(ctx, m, BuildInfo.mikuosVersion(), blocked)) }
        }
        return result
    }

    // ---------------------------------------------------------------- installed list

    fun refreshInstalled(ctx: Context) {
        val pm = ctx.packageManager
        val store = RollbackStore(ctx)
        val apps = runCatching {
            @Suppress("DEPRECATION")
            pm.getInstalledPackages(PackageManager.MATCH_SYSTEM_ONLY)
        }.getOrDefault(emptyList())
            .filter { OtaConfig.isUpdatable(it.packageName) && ApkVerifier.isSystemApp(it) }
            .map { p ->
                val updated = ApkVerifier.isUpdatedSystemApp(p)
                val factory = if (updated) ApkVerifier.factoryInfo(ctx, p.packageName) else null
                InstalledApp(
                    pkg = p.packageName,
                    name = OtaConfig.displayName(p.packageName),
                    versionCode = ApkVerifier.longVersion(p),
                    versionName = p.versionName ?: "",
                    isUpdate = updated,
                    imageVersionName = factory?.versionName,
                    imageVersionCode = factory?.let { ApkVerifier.longVersion(it) },
                    kept = if (updated) store.kept(p.packageName) else null,
                )
            }
            .sortedBy { it.name }
        _state.update { it.copy(installed = apps) }
    }

    fun clearNotice() = _state.update { it.copy(notice = null) }
    fun setNotice(text: String) = _state.update { it.copy(notice = text) }

    // ---------------------------------------------------------------- scheduled run

    /** What the worker does: check, then install or notify. Returns false to ask for a retry. */
    suspend fun runScheduled(ctx: Context): Boolean {
        val prefs = Prefs(ctx)
        if (!check(ctx)) return _state.value.error?.startsWith("Could not") != true
        val s = _state.value
        s.systemUpdate?.let { su ->
            if (prefs.notifiedSystemBuild != su.build) {
                Notifier.systemUpdate(ctx, su.build, su.required || s.blockedByMinBuild)
                prefs.notifiedSystemBuild = su.build
            }
        }
        val ready = s.items.filter { it.phase == Phase.READY }
        if (ready.isEmpty()) return true
        if (prefs.autoInstall) {
            installAll(ctx, includeHeld = false)
        } else {
            val key = ready.joinToString(",") { "${it.entry.packageName}:${it.entry.versionCode}" }
            if (prefs.notifiedAvailableKey != key) {
                Notifier.available(ctx, ready.map { "${it.name} ${it.entry.versionName}".trim() })
                prefs.notifiedAvailableKey = key
            }
        }
        return true
    }
}
