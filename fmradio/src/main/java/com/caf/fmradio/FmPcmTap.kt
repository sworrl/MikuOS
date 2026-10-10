package com.caf.fmradio

import java.util.concurrent.CopyOnWriteArrayList

/**
 * The radio's decoded PCM, for anything that wants to visualise it (the projectM background).
 *
 * The engine calls [offer] from the capture thread with each mono 16-bit block the siphon
 * delivers, the same samples the FFT and song ID see. Listeners run on that thread, so they must
 * be quick: copy what they need and return. Nothing flows when the siphon is off (wired outputs
 * where the capture is silent, or the tuner off), and listeners should draw idle in that case.
 */
object FmPcmTap {
    fun interface Listener { fun onPcm(mono: ShortArray, count: Int, sampleRate: Int) }

    private val listeners = CopyOnWriteArrayList<Listener>()

    fun add(l: Listener) { listeners.addIfAbsent(l) }
    fun remove(l: Listener) { listeners.remove(l) }
    val active: Boolean get() = listeners.isNotEmpty()

    fun offer(mono: ShortArray, count: Int, sampleRate: Int) {
        for (l in listeners) l.onPcm(mono, count, sampleRate)
    }
}
