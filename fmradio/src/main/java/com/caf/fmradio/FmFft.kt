package com.caf.fmradio

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * The live audio spectrum, by FFT.
 *
 * It replaced 48 Goertzel filters over a 1024-frame window, which gave ~47 Hz of resolution,
 * smeared the bass into a few wide bins and drew a plot that looked busy and said little. This
 * is a 4096-point Hann-windowed FFT with 75% overlap: 11.7 Hz per FFT bin at 48 kHz, so bass
 * notes separate, and ~47 new frames a second.
 *
 * Display bins are log-spaced from [lowHz] to the top. Where a display bin spans several FFT
 * bins it takes the strongest (peaks are what the eye follows); where it is narrower than one,
 * which happens in the bass, it interpolates between the two nearest in dB rather than
 * repeating the same value as a staircase.
 *
 * Levels are dBFS, calibrated so a full-scale sine reads 0 dB (Hann coherent gain 0.5), then
 * mapped [floorDb]..0 to 0..1. Ballistics like a hardware analyser: instant attack, a
 * [releaseDbPerSec] fall, and peak markers that hold for [peakHoldMs] and then drop.
 *
 * Allocation-free once constructed. Everything here runs on the capture thread.
 */
class FmFft(
    val sampleRateHz: Int,
    private val size: Int = 4096,
    val bins: Int = 256,
    private val lowHz: Double = 25.0,
    topHz: Double = 16_000.0,
    private val floorDb: Double = -90.0,
    private val releaseDbPerSec: Double = 36.0,
    private val peakHoldMs: Long = 900L,
) {
    init { require(size and (size - 1) == 0) { "FFT size must be a power of two" } }

    private val hop = size / 4
    val topHz: Double = min(topHz, sampleRateHz / 2.0 * 0.98)

    private val window = FloatArray(size) { i -> (0.5 - 0.5 * cos(2 * PI * i / size)).toFloat() }
    private val ring = FloatArray(size)
    private var ringPos = 0
    private var sinceLast = 0
    private val re = FloatArray(size)
    private val im = FloatArray(size)
    private val cosT = FloatArray(size / 2) { cos(2 * PI * it / size).toFloat() }
    private val sinT = FloatArray(size / 2) { -sin(2 * PI * it / size).toFloat() }
    private val rev = IntArray(size).also { r ->
        val bits = Integer.numberOfTrailingZeros(size)
        for (i in 0 until size) r[i] = Integer.reverse(i) ushr (32 - bits)
    }
    private val db = FloatArray(size / 2 + 1)

    /** Centre frequency of each display bin, Hz. */
    val binHz = FloatArray(bins) { i -> (lowHz * (this.topHz / lowHz).pow(i / (bins - 1.0))).toFloat() }
    private val edgeLo = FloatArray(bins)
    private val edgeHi = FloatArray(bins)

    /** Smoothed level per display bin, 0..1. */
    val level = FloatArray(bins)
    /** Peak-hold level per display bin, 0..1. */
    val peak = FloatArray(bins)
    private val peakAt = LongArray(bins)
    private var lastFrameMs = 0L

    init {
        val ratio = (this.topHz / lowHz).pow(1.0 / (bins - 1))
        val half = sqrt(ratio)
        val hzPerBin = sampleRateHz.toDouble() / size
        for (i in 0 until bins) {
            edgeLo[i] = (binHz[i] / half / hzPerBin).toFloat()
            edgeHi[i] = (binHz[i] * half / hzPerBin).toFloat()
        }
    }

    /**
     * Feed interleaved 16-bit PCM. Returns true when at least one new spectrum frame was
     * computed, i.e. when [level] and [peak] changed.
     */
    fun feed(pcm: ShortArray, count: Int, channels: Int, nowMs: Long): Boolean {
        var produced = false
        var i = 0
        val ch = max(1, channels)
        while (i + ch - 1 < count) {
            var m = 0f
            for (c in 0 until ch) m += pcm[i + c]
            ring[ringPos] = m / (32768f * ch)
            ringPos = (ringPos + 1) and (size - 1)
            i += ch
            if (++sinceLast >= hop) {
                sinceLast = 0
                transform(nowMs)
                produced = true
            }
        }
        return produced
    }

    private fun transform(nowMs: Long) {
        // Oldest sample first, windowed, in bit-reversed order for the in-place radix-2.
        for (k in 0 until size) {
            val j = rev[k]
            re[j] = ring[(ringPos + k) and (size - 1)] * window[k]
            im[j] = 0f
        }
        var len = 2
        while (len <= size) {
            val halfLen = len / 2
            val step = size / len
            var startIdx = 0
            while (startIdx < size) {
                var t = 0
                for (k in startIdx until startIdx + halfLen) {
                    val wr = cosT[t]; val wi = sinT[t]
                    val l = k + halfLen
                    val xr = re[l] * wr - im[l] * wi
                    val xi = re[l] * wi + im[l] * wr
                    re[l] = re[k] - xr; im[l] = im[k] - xi
                    re[k] += xr; im[k] += xi
                    t += step
                }
                startIdx += len
            }
            len = len shl 1
        }
        // |X| * 4 / N is the amplitude of a sine through a Hann window (coherent gain 0.5).
        val scale = 4.0 / size
        for (k in 0..size / 2) {
            val a = sqrt((re[k] * re[k] + im[k] * im[k]).toDouble()) * scale
            db[k] = (20 * log10(max(a, 1e-9))).toFloat()
        }
        val dt = if (lastFrameMs == 0L) 0.0 else (nowMs - lastFrameMs).coerceIn(0, 200) / 1000.0
        lastFrameMs = nowMs
        val fall = (releaseDbPerSec * dt / -floorDb).toFloat()
        val last = size / 2
        for (b in 0 until bins) {
            val lo = edgeLo[b]; val hi = edgeHi[b]
            val v: Float = if (hi - lo < 1f) {
                val c = (lo + hi) / 2
                val k0 = c.toInt().coerceIn(0, last - 1)
                val f = c - k0
                db[k0] + (db[k0 + 1] - db[k0]) * f
            } else {
                var m = -200f
                for (k in lo.toInt().coerceIn(0, last)..hi.toInt().coerceIn(0, last)) if (db[k] > m) m = db[k]
                m
            }
            val n = ((v - floorDb) / -floorDb).toFloat().coerceIn(0f, 1f)
            level[b] = if (n >= level[b]) n else max(n, level[b] - fall)
            if (level[b] >= peak[b]) { peak[b] = level[b]; peakAt[b] = nowMs }
            else if (nowMs - peakAt[b] > peakHoldMs) peak[b] = max(level[b], peak[b] - fall * 0.6f)
        }
    }

    fun reset() {
        ring.fill(0f); level.fill(0f); peak.fill(0f); lastFrameMs = 0L; sinceLast = 0
    }
}
