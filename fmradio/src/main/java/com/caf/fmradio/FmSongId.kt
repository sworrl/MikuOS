package com.caf.fmradio

import android.util.Base64
import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.URL
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID
import java.util.zip.CRC32
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.sqrt

/**
 * "What song is this?", from the radio's own audio.
 *
 * WHERE THE AUDIO COMES FROM. The siphon (the RADIO_TUNER capture the engine probes and keeps
 * only when it carries real audio) feeds [offer] continuously; this keeps the last
 * [WINDOW_SECONDS] as 16 kHz mono. Nothing is recorded or kept beyond that ring, and nothing
 * leaves the device until the user asks for an identification.
 *
 * HOW IT IDENTIFIES. The same way the Shazam app does: a spectral-peak fingerprint of the
 * audio (not the audio itself) is sent to Shazam's recognition service. The fingerprint is the
 * algorithm documented by the SongRec and shazamio projects, reimplemented here. That service
 * has no public API contract: it is what Shazam's own clients call, it can change or refuse
 * without notice, and when it does this reports UNAVAILABLE with the reason rather than
 * pretending. It needs a network connection.
 */
object FmSongId {

    private const val TAG = "FmSongId"
    const val WINDOW_SECONDS = 12
    private const val RATE = 16_000
    private const val MIN_SECONDS = 6

    enum class Phase { IDLE, LISTENING, MATCHING, FOUND, NOT_FOUND, UNAVAILABLE }

    data class Match(
        val title: String,
        val artist: String,
        val album: String?,
        val coverUrl: String?,
        /** Shazam's page for the track, for "open in…". */
        val webUrl: String?,
        val atMs: Long,
        /** What the dial was on when it was heard. */
        val freqKHz: Int,
    )

    data class State(
        val phase: Phase = Phase.IDLE,
        val match: Match? = null,
        /** Why it failed, in words, for UNAVAILABLE / NOT_FOUND. */
        val message: String? = null,
        /** Seconds of audio currently buffered (the button can say "listening… 4 s"). */
        val bufferedSeconds: Int = 0,
        /** Newest first, this session. */
        val history: List<Match> = emptyList(),
    )

    val state = MutableStateFlow(State())

    // ---------------------------------------------------------------- the audio ring

    private val ring = ShortArray(RATE * WINDOW_SECONDS)
    private var ringPos = 0
    private var ringFill = 0
    private var acc = 0f
    private var accN = 0
    private var decim = 3
    private val lock = Any()

    /** Interleaved 16-bit PCM from the siphon at [sampleRate]. Cheap: a sum and a store. */
    fun offer(pcm: ShortArray, count: Int, channels: Int, sampleRate: Int) {
        val ch = max(1, channels)
        decim = max(1, sampleRate / RATE)
        synchronized(lock) {
            var i = 0
            while (i + ch - 1 < count) {
                var m = 0f
                for (c in 0 until ch) m += pcm[i + c]
                acc += m / ch; accN++
                if (accN >= decim) {
                    // Boxcar over the decimation factor: a crude low-pass, but the fingerprint
                    // only looks at 250 Hz–5.5 kHz, well inside what survives it.
                    ring[ringPos] = (acc / accN).toInt().coerceIn(-32768, 32767).toShort()
                    ringPos = (ringPos + 1) % ring.size
                    if (ringFill < ring.size) ringFill++
                    acc = 0f; accN = 0
                }
                i += ch
            }
        }
    }

    /** Forget the buffered audio, e.g. on a retune, so a match is never of the last station. */
    fun clear() = synchronized(lock) { ringPos = 0; ringFill = 0; acc = 0f; accN = 0 }

    fun bufferedSeconds(): Int = synchronized(lock) { ringFill / RATE }

    private fun snapshot(): ShortArray = synchronized(lock) {
        val out = ShortArray(ringFill)
        val start = (ringPos - ringFill + ring.size) % ring.size
        for (i in 0 until ringFill) out[i] = ring[(start + i) % ring.size]
        out
    }

    // ---------------------------------------------------------------- identify

    /**
     * Blocking; call off the main thread. Uses what is buffered; if less than [MIN_SECONDS]
     * is there, waits for it (up to [WINDOW_SECONDS]) while reporting LISTENING.
     */
    fun identify(freqKHz: Int, siphonLive: () -> Boolean) {
        if (!siphonLive()) {
            state.value = state.value.copy(phase = Phase.UNAVAILABLE,
                message = "The radio's audio is not reaching the app on this output, so there is nothing to listen to. " +
                    "It works when the live spectrum is moving.")
            return
        }
        val deadline = System.currentTimeMillis() + WINDOW_SECONDS * 1000L
        while (bufferedSeconds() < MIN_SECONDS && System.currentTimeMillis() < deadline) {
            state.value = state.value.copy(phase = Phase.LISTENING, bufferedSeconds = bufferedSeconds(), message = null)
            Thread.sleep(250)
        }
        val pcm = snapshot()
        if (pcm.size < RATE * MIN_SECONDS / 2) {
            state.value = state.value.copy(phase = Phase.UNAVAILABLE, message = "Not enough audio arrived to listen to.")
            return
        }
        state.value = state.value.copy(phase = Phase.MATCHING, bufferedSeconds = pcm.size / RATE, message = null)
        val sig = runCatching { Signature.generate(pcm) }.getOrElse {
            Log.w(TAG, "fingerprint failed", it)
            state.value = state.value.copy(phase = Phase.UNAVAILABLE, message = "Could not fingerprint the audio: ${it.message}")
            return
        }
        val result = runCatching { query(sig, pcm.size) }
        result.onFailure {
            Log.w(TAG, "recognition request failed: $it")
            state.value = state.value.copy(phase = Phase.UNAVAILABLE,
                message = "The recognition service did not answer (${it.javaClass.simpleName}: ${it.message}). Check the network.")
        }
        val json = result.getOrNull() ?: return
        val track = json.optJSONObject("track")
        if (track == null) {
            state.value = state.value.copy(phase = Phase.NOT_FOUND,
                message = "No match. Talk, ads and station IDs never match. Try again during a song.")
            return
        }
        var album: String? = null
        track.optJSONArray("sections")?.let { secs ->
            for (i in 0 until secs.length()) {
                val meta = secs.optJSONObject(i)?.optJSONArray("metadata") ?: continue
                for (j in 0 until meta.length()) {
                    val m = meta.optJSONObject(j) ?: continue
                    if (m.optString("title").equals("Album", true)) album = m.optString("text").ifBlank { null }
                }
            }
        }
        val match = Match(
            title = track.optString("title"),
            artist = track.optString("subtitle"),
            album = album,
            coverUrl = track.optJSONObject("images")?.optString("coverarthq")?.ifBlank { null }
                ?: track.optJSONObject("images")?.optString("coverart")?.ifBlank { null },
            webUrl = track.optString("url").ifBlank { null },
            atMs = System.currentTimeMillis(),
            freqKHz = freqKHz,
        )
        Log.i(TAG, "identified on $freqKHz kHz: ${match.artist} - ${match.title}")
        state.value = State(phase = Phase.FOUND, match = match, bufferedSeconds = pcm.size / RATE,
            history = (listOf(match) + state.value.history.filterNot { it.title == match.title && it.artist == match.artist }).take(30))
    }

    fun dismiss() { state.value = state.value.copy(phase = Phase.IDLE, message = null) }

    private fun query(signature: ByteArray, samples: Int): JSONObject {
        val now = System.currentTimeMillis()
        val url = URL("https://amp.shazam.com/discovery/v5/en/US/android/-/tag/" +
            "${UUID.randomUUID().toString().uppercase()}/${UUID.randomUUID()}" +
            "?sync=true&webv3=true&sampling=true&connected=&shazamapiversion=v3&sharehub=true&video=v3")
        val body = JSONObject()
            .put("timezone", java.util.TimeZone.getDefault().id)
            .put("signature", JSONObject()
                .put("uri", "data:audio/vnd.shazam.sig;base64," + Base64.encodeToString(signature, Base64.NO_WRAP))
                .put("samplems", samples * 1000L / RATE))
            .put("timestamp", now)
            .put("context", JSONObject())
            .put("geolocation", JSONObject())
        val r = FmNet.request(
            url.toString(), method = "POST",
            headers = mapOf(
                "Content-Type" to "application/json",
                "Content-Language" to "en_US",
                "User-Agent" to "Dalvik/2.1.0 (Linux; U; Android 14)",
            ),
            body = body.toString().toByteArray(),
        )
        if (r.code !in 200..299) throw java.io.IOException("HTTP ${r.code}")
        return JSONObject(r.text)
    }

    // ---------------------------------------------------------------- the fingerprint

    /**
     * Spectral-peak signature, 16 kHz mono, in the binary layout the service reads.
     *
     * 2048-sample Hann FFT every 128 samples; peaks are spread in frequency and time, then a
     * bin is kept when it beats its neighbours across a fixed set of earlier and later frames.
     * Kept peaks are bucketed into four bands (250–520, 520–1450, 1450–3500, 3500–5500 Hz) with
     * a log magnitude and a sub-bin frequency, and written as per-band streams of
     * (frame delta, magnitude, frequency).
     */
    private object Signature {
        private const val N = 2048
        private const val RING = 256
        private class Peak(val pass: Int, val magnitude: Int, val bin: Int)

        fun generate(pcm: ShortArray): ByteArray {
            val window = DoubleArray(N) { i -> 0.5 - 0.5 * cos(2 * PI * (i + 1) / (N + 1)) }   // numpy hanning(2050)[1:-1]
            val samples = DoubleArray(N)
            var sPos = 0
            val ffts = Array(RING) { DoubleArray(1025) }
            val spread = Array(RING) { DoubleArray(1025) }
            var fftPos = 0
            var spreadPos = 0
            var spreadWritten = 0
            val bands = sortedMapOf<Int, MutableList<Peak>>()
            val re = DoubleArray(N)
            val im = DoubleArray(N)

            var chunk = 0
            while (chunk < pcm.size) {
                val end = minOf(chunk + 128, pcm.size)
                for (i in chunk until end) { samples[sPos] = pcm[i].toDouble(); sPos = (sPos + 1) % N }
                chunk = end
                // FFT of the ring, oldest first.
                for (i in 0 until N) { re[i] = samples[(sPos + i) % N] * window[i]; im[i] = 0.0 }
                fft(re, im)
                val out = ffts[fftPos]
                for (k in 0..1024) out[k] = max((re[k] * re[k] + im[k] * im[k]) / (1 shl 17), 1e-10)
                fftPos = (fftPos + 1) % RING

                // Spread the newest frame in frequency, then into frames -1, -3, -6.
                val last = ffts[(fftPos - 1 + RING) % RING]
                val sp = last.copyOf()
                for (p in 0 until 1023) sp[p] = maxOf(sp[p], sp[p + 1], sp[p + 2])
                for (p in 0..1024) {
                    var m = sp[p]
                    for (former in intArrayOf(-1, -3, -6)) {
                        val f = spread[((spreadPos + former) % RING + RING) % RING]
                        m = max(f[p], m); f[p] = m
                    }
                }
                System.arraycopy(sp, 0, spread[spreadPos], 0, 1025)
                spreadPos = (spreadPos + 1) % RING
                spreadWritten++

                if (spreadWritten >= 46) recognise(ffts, spread, fftPos, spreadPos, spreadWritten, bands)
            }
            return encode(bands, pcm.size)
        }

        private val NEIGHBOURS = intArrayOf(-10, -7, -4, -3, 1, 2, 5, 8)
        private val OTHER_FRAMES = intArrayOf(-53, -45) + (165 until 201 step 7).toList() + (214 until 250 step 7).toList()

        private fun recognise(
            ffts: Array<DoubleArray>, spread: Array<DoubleArray>, fftPos: Int, spreadPos: Int,
            written: Int, bands: MutableMap<Int, MutableList<Peak>>,
        ) {
            val f46 = ffts[((fftPos - 46) % RING + RING) % RING]
            val s49 = spread[((spreadPos - 49) % RING + RING) % RING]
            for (bin in 10 until 1015) {
                if (f46[bin] < 1.0 / 64 || f46[bin] < s49[bin - 1]) continue
                var maxN = 0.0
                for (o in NEIGHBOURS) maxN = max(s49[bin + o], maxN)
                if (f46[bin] <= maxN) continue
                var maxOther = maxN
                for (o in OTHER_FRAMES) maxOther = max(spread[((spreadPos + o) % RING + RING) % RING][bin - 1], maxOther)
                if (f46[bin] <= maxOther) continue
                val pass = written - 46
                fun mag(v: Double) = ln(max(1.0 / 64, v)) * 1477.3 + 6144
                val m = mag(f46[bin]); val before = mag(f46[bin - 1]); val after = mag(f46[bin + 1])
                val v1 = m * 2 - before - after
                if (v1 <= 0) continue
                val v2 = (after - before) * 32 / v1
                val corrected = bin * 64 + v2
                val hz = corrected * (RATE / 2.0 / 1024 / 64)
                val band = when {
                    hz < 250 -> continue
                    hz < 520 -> 0
                    hz < 1450 -> 1
                    hz < 3500 -> 2
                    hz <= 5500 -> 3
                    else -> continue
                }
                bands.getOrPut(band) { ArrayList() }.add(Peak(pass, m.toInt(), corrected.toInt()))
            }
        }

        private fun encode(bands: Map<Int, List<Peak>>, samples: Int): ByteArray {
            val contents = ByteArrayOutputStream()
            fun u32(o: ByteArrayOutputStream, v: Long) {
                o.write(ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(v.toInt()).array())
            }
            for ((band, peaks) in bands) {
                val pb = ByteArrayOutputStream()
                var pass = 0
                for (p in peaks) {
                    if (p.pass - pass >= 255) { pb.write(0xFF); u32(pb, p.pass.toLong()); pass = p.pass }
                    pb.write(p.pass - pass)
                    pb.write(p.magnitude and 0xFF); pb.write((p.magnitude shr 8) and 0xFF)
                    pb.write(p.bin and 0xFF); pb.write((p.bin shr 8) and 0xFF)
                    pass = p.pass
                }
                val bytes = pb.toByteArray()
                u32(contents, 0x60030040L + band)
                u32(contents, bytes.size.toLong())
                contents.write(bytes)
                repeat((4 - bytes.size % 4) % 4) { contents.write(0) }
            }
            val sizeMinusHeader = contents.size() + 8
            val buf = ByteBuffer.allocate(48 + 8 + contents.size()).order(ByteOrder.LITTLE_ENDIAN)
            buf.putInt(0xCAFE2580.toInt())          // magic 1
            buf.putInt(0)                            // crc32, filled below
            buf.putInt(sizeMinusHeader)
            buf.putInt(0x94119C00.toInt())          // magic 2
            buf.putInt(0); buf.putInt(0); buf.putInt(0)
            buf.putInt(3 shl 27)                     // sample rate id: 3 = 16 kHz
            buf.putInt(0); buf.putInt(0)
            buf.putInt((samples + RATE * 0.24).toInt())
            buf.putInt((15 shl 19) + 0x40000)
            buf.putInt(0x40000000)
            buf.putInt(sizeMinusHeader)
            buf.put(contents.toByteArray())
            val arr = buf.array()
            val crc = CRC32().apply { update(arr, 8, arr.size - 8) }.value
            ByteBuffer.wrap(arr).order(ByteOrder.LITTLE_ENDIAN).putInt(4, crc.toInt())
            return arr
        }

        /** In-place radix-2 complex FFT. N is fixed at 2048 here. */
        private fun fft(re: DoubleArray, im: DoubleArray) {
            val n = re.size
            var j = 0
            for (i in 1 until n) {
                var bit = n shr 1
                while (j and bit != 0) { j = j xor bit; bit = bit shr 1 }
                j = j xor bit
                if (i < j) { var t = re[i]; re[i] = re[j]; re[j] = t; t = im[i]; im[i] = im[j]; im[j] = t }
            }
            var len = 2
            while (len <= n) {
                val ang = -2 * PI / len
                val wr = cos(ang); val wi = kotlin.math.sin(ang)
                var i = 0
                while (i < n) {
                    var cr = 1.0; var ci = 0.0
                    for (k in 0 until len / 2) {
                        val a = i + k; val b = a + len / 2
                        val xr = re[b] * cr - im[b] * ci
                        val xi = re[b] * ci + im[b] * cr
                        re[b] = re[a] - xr; im[b] = im[a] - xi
                        re[a] += xr; im[a] += xi
                        val ncr = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = ncr
                    }
                    i += len
                }
                len = len shl 1
            }
        }
    }

}
