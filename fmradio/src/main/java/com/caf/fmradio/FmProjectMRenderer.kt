package com.caf.fmradio

import android.content.Context
import android.graphics.PixelFormat
import android.opengl.GLES30
import android.opengl.GLSurfaceView
import android.os.Process
import android.util.Log
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.PI
import kotlin.math.sin

/**
 * The radio's PCM, buffered for the GL thread.
 *
 * [FmPcmTap] calls back on the capture thread; that thread also feeds the FFT, song ID and the
 * recorder, so the listener only copies into a ring and returns. The GL thread takes the newest
 * [CAP] samples once per frame. Old audio is simply overwritten: projectM only looks at the most
 * recent window anyway.
 */
internal class FmPcmRing : FmPcmTap.Listener {
    private val ring = ShortArray(CAP)
    private var write = 0
    private var filled = 0
    /** When the radio last delivered something above the noise floor. */
    @Volatile var lastLoudNanos = 0L
        private set

    override fun onPcm(mono: ShortArray, count: Int, sampleRate: Int) {
        val n = minOf(count, mono.size)
        if (n <= 0) return
        var peak = 0
        synchronized(this) {
            for (i in 0 until n) {
                val s = mono[i]
                ring[write] = s
                write = if (write + 1 == CAP) 0 else write + 1
                val a = if (s < 0) -s else s.toInt()
                if (a > peak) peak = a
            }
            filled = minOf(CAP, filled + n)
        }
        // Muted or between stations the siphon still delivers blocks of near-silence; that is idle.
        if (peak > 96) lastLoudNanos = System.nanoTime()
    }

    /** Newest samples since the last drain into [out], oldest first. Returns the count. */
    fun drain(out: ShortArray): Int = synchronized(this) {
        val n = minOf(filled, out.size)
        var r = write - n
        if (r < 0) r += CAP
        for (i in 0 until n) {
            out[i] = ring[r]
            r = if (r + 1 == CAP) 0 else r + 1
        }
        filled = 0
        n
    }

    companion object { const val CAP = 2048 }
}

/**
 * Full-screen projectM surface for the FM background. A [GLSurfaceView] sits BELOW the window
 * (its own hardware layer, composited by SurfaceFlinger), so the Compose UI on top is not redrawn
 * when it renders: the background costs the UI thread nothing per frame. A TextureView would have
 * forced the whole window to recomposite at the visualiser's frame rate.
 *
 * Budget, in order of how much they save:
 *  - Renders at [FmProjectMPerf.SCALES] of the view (0.6 by default, down to 0.4 if the device
 *    struggles) and lets the compositor upscale. Milkdrop output is soft; under the scrim the
 *    difference is invisible.
 *  - 30 fps cap while audio flows, 15 fps with the clock at 0.35x while it does not (tuner off,
 *    muted, or a wired output where the capture is silent).
 *  - Mesh 24x18 (the player's setting), no depth or stencil buffer, opaque RGBX surface.
 *  - Stops entirely when paused ([onPause] releases the EGL context and its memory too).
 *
 * The dim scrim is drawn here, on the GL thread at the reduced resolution, rather than as a
 * full-screen translucent Compose layer: one tiny pass on this thread instead of a full-screen
 * blend on the UI's RenderThread every time the UI redraws.
 */
class FmProjectMSurfaceView(context: Context, dim: Float) : GLSurfaceView(context) {
    private val renderer = Renderer(context.applicationContext, dim)
    private var lastW = 0
    private var lastH = 0
    @Volatile private var paused = true

    init {
        setEGLContextClientVersion(3)
        setEGLConfigChooser(8, 8, 8, 0, 0, 0)
        holder.setFormat(PixelFormat.RGBX_8888)
        // Released on pause (see onPause): a backgrounded tuner should not keep projectM's
        // textures resident. Coming back costs one re-init on the GL thread, never on the UI
        // thread, and the playlist position survives it.
        preserveEGLContextOnPause = false
        setRenderer(renderer)
        renderMode = RENDERMODE_CONTINUOUSLY
        renderer.onScaleChange = { step -> post { applyScale(step) } }
        super.onPause()   // nothing renders until the lifecycle says RESUMED
    }

    fun setDim(d: Float) { renderer.dim = d.coerceIn(0f, 0.95f) }

    override fun onResume() {
        if (!paused) return
        paused = false
        FmPcmTap.add(renderer.pcm)
        super.onResume()
    }

    /**
     * Stops rendering and frees projectM. The free is queued to the GL thread and waited for
     * (bounded) BEFORE the pause, because the pause releases the EGL context and projectM's
     * textures and shaders can only be deleted while that context is current. The GL thread runs
     * queued events ahead of a pause request, so this is at most one frame of waiting.
     */
    override fun onPause() {
        if (paused) return
        paused = true
        FmPcmTap.remove(renderer.pcm)
        val done = CountDownLatch(1)
        queueEvent { renderer.release(); done.countDown() }
        runCatching { done.await(300, TimeUnit.MILLISECONDS) }
        super.onPause()
    }

    private fun applyScale(step: Int) {
        renderer.scaleStep = step
        if (lastW <= 0 || lastH <= 0) return
        val s = FmProjectMPerf.SCALES[step.coerceIn(0, FmProjectMPerf.SCALES.size - 1)]
        holder.setFixedSize((lastW * s).toInt().coerceAtLeast(1), (lastH * s).toInt().coerceAtLeast(1))
    }

    override fun onSizeChanged(w: Int, h: Int, ow: Int, oh: Int) {
        super.onSizeChanged(w, h, ow, oh)
        if (w <= 0 || h <= 0) return
        lastW = w; lastH = h
        applyScale(renderer.scaleStep)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        // A re-attach builds a fresh GL thread that starts running; hold it until resumed.
        if (paused) super.onPause()
    }

    override fun onDetachedFromWindow() {
        onPause()   // frees projectM while its context is still current
        super.onDetachedFromWindow()
    }

    private class Renderer(private val app: Context, @Volatile var dim: Float) : GLSurfaceView.Renderer {
        val pcm = FmPcmRing()
        @Volatile var scaleStep = FmProjectMPerf.startScale(app)
        var onScaleChange: ((Int) -> Unit)? = null

        private var ready = false
        private var width = 0
        private var height = 0
        private val pcmBuf = ShortArray(FmPcmRing.CAP)
        private val ambient = ShortArray(AMBIENT_SAMPLES)

        // Our clock, handed to projectM each frame: real time while audio flows, slowed when idle.
        private var clock = 0.0
        private var lastNs = 0L
        private var nextFrameNs = 0L

        private var frames = 0
        private var fpsWindowStart = 0L
        private var activeSeconds = 0

        fun release() {
            if (ready) FmProjectMNative.destroy()
            ready = false
            scrim.release()
        }

        override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
            // A new context: everything GL-side is gone, projectM included.
            ready = false
            scrim.release()
            // Give way to the UI thread; the background is the least important thing on screen.
            runCatching { Process.setThreadPriority(Process.THREAD_PRIORITY_DEFAULT + 2) }
        }

        override fun onSurfaceChanged(gl: GL10?, w: Int, h: Int) {
            width = w; height = h
            if (ready) FmProjectMNative.resize(w, h)
        }

        private var initFailures = 0

        private fun ensureReady(): Boolean {
            if (ready) return true
            // A context projectM cannot use will not get better by retrying 15 times a second.
            if (initFailures >= 3) return false
            if (!FmProjectMNative.init(ACTIVE_FPS, 24, 18, 40f)) { initFailures++; return false }
            val dir = FmProjectMNative.ensurePresets(app)
            val n = if (dir != null) FmProjectMNative.loadPresets(dir) else 0
            FmProjectMPerf.librarySize = n
            if (width > 0 && height > 0) FmProjectMNative.resize(width, height)
            Log.i(TAG, "${FmProjectMNative.version}: $n presets, ${width}x$height (scale ${FmProjectMPerf.SCALES[scaleStep]})")
            ready = true
            // A fresh instance starts its own timeline at 0 (nativeInit set it so).
            clock = 0.0
            lastNs = 0L; nextFrameNs = 0L; fpsWindowStart = 0L; frames = 0; activeSeconds = 0
            return true
        }

        override fun onDrawFrame(gl: GL10?) {
            val now = System.nanoTime()
            val audible = pcm.lastLoudNanos != 0L && now - pcm.lastLoudNanos < IDLE_AFTER_NS
            val fps = if (audible) ACTIVE_FPS else IDLE_FPS

            // Frame cap, deadline based so vsync waits in the swap do not pile on top of it.
            val budget = 1_000_000_000L / fps
            if (nextFrameNs != 0L) {
                val wait = nextFrameNs - now
                if (wait > 1_000_000L) runCatching { Thread.sleep(wait / 1_000_000L, (wait % 1_000_000L).toInt()) }
            }
            val start = System.nanoTime()
            nextFrameNs = if (nextFrameNs == 0L || start - nextFrameNs > budget) start + budget else nextFrameNs + budget

            if (!ensureReady()) {
                GLES30.glClearColor(0.016f, 0.05f, 0.07f, 1f)
                GLES30.glClear(GLES30.GL_COLOR_BUFFER_BIT)
                return
            }

            val dt = if (lastNs == 0L) 0.0 else ((start - lastNs) / 1e9).coerceIn(0.0, 0.25)
            lastNs = start
            clock += if (audible) dt else dt * IDLE_SPEED

            if (audible) {
                val n = pcm.drain(pcmBuf)
                FmProjectMNative.feedPcm(pcmBuf, n)
            } else {
                // Discard whatever trickled in and give projectM a quiet, slowly breathing tone so
                // the waves and per-frame equations still have something to move with.
                pcm.drain(pcmBuf)
                FmProjectMNative.feedPcm(ambient, fillAmbient(clock))
            }
            FmProjectMNative.render(clock)
            scrim.draw(width, height, dim)

            // Once a second: fps into the ledger, which may move the render scale.
            frames++
            if (fpsWindowStart == 0L) fpsWindowStart = start
            val span = start - fpsWindowStart
            if (span >= 1_000_000_000L) {
                val measured = (frames * 1_000_000_000L / span).toInt()
                frames = 0; fpsWindowStart = start
                if (audible) {
                    activeSeconds++
                    // The first seconds after a (re)init include the shader compile; not a verdict.
                    if (activeSeconds > 3) {
                        val step = FmProjectMPerf.tick(app, FmProjectMNative.presetName(), measured, ACTIVE_FPS, scaleStep)
                        if (step != scaleStep) { scaleStep = step; onScaleChange?.invoke(step) }
                    }
                } else activeSeconds = 0
            }
        }

        private var ambientPhase = 0.0
        private fun fillAmbient(t: Double): Int {
            val n = AMBIENT_SAMPLES
            val swell = 0.55 + 0.45 * sin(t * 0.21)
            val amp = 2200.0 * swell
            val step = 2.0 * PI / AMBIENT_RATE
            var p = ambientPhase
            for (i in 0 until n) {
                val v = sin(p * 55.0) + 0.35 * sin(p * 110.0 + sin(t * 0.13) * 2.0) + 0.15 * sin(p * 330.0)
                ambient[i] = (v * amp).toInt().coerceIn(-32767, 32767).toShort()
                p += step
            }
            ambientPhase = p % (2.0 * PI * 1000.0)
            return n
        }

        private val scrim = Scrim()
    }

    /**
     * Darkens the visualiser so the UI over it stays readable: a uniform dim plus a little extra
     * at the top and bottom, where the header and transport sit. One quad, one tiny shader.
     */
    private class Scrim {
        private var program = 0
        private var aPos = -1
        private var uDim = -1
        private val quad: FloatBuffer = ByteBuffer.allocateDirect(8 * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
            .apply { put(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f)); position(0) }

        fun release() { program = 0 }   // the context that owned it is gone or going

        private fun build(): Boolean {
            val vs = compile(GLES30.GL_VERTEX_SHADER, """
                attribute vec2 a_pos;
                varying float v_y;
                void main() { v_y = a_pos.y; gl_Position = vec4(a_pos, 0.0, 1.0); }
            """.trimIndent())
            val fs = compile(GLES30.GL_FRAGMENT_SHADER, """
                precision mediump float;
                varying float v_y;
                uniform float u_dim;
                void main() {
                    float edge = smoothstep(0.55, 1.0, abs(v_y)) * 0.25;
                    gl_FragColor = vec4(0.0, 0.0, 0.0, clamp(u_dim + edge, 0.0, 0.95));
                }
            """.trimIndent())
            if (vs == 0 || fs == 0) return false
            val p = GLES30.glCreateProgram()
            GLES30.glAttachShader(p, vs); GLES30.glAttachShader(p, fs)
            GLES30.glLinkProgram(p)
            GLES30.glDeleteShader(vs); GLES30.glDeleteShader(fs)
            val ok = IntArray(1)
            GLES30.glGetProgramiv(p, GLES30.GL_LINK_STATUS, ok, 0)
            if (ok[0] == 0) { GLES30.glDeleteProgram(p); return false }
            program = p
            aPos = GLES30.glGetAttribLocation(p, "a_pos")
            uDim = GLES30.glGetUniformLocation(p, "u_dim")
            return true
        }

        private fun compile(type: Int, src: String): Int {
            val s = GLES30.glCreateShader(type)
            GLES30.glShaderSource(s, src)
            GLES30.glCompileShader(s)
            val ok = IntArray(1)
            GLES30.glGetShaderiv(s, GLES30.GL_COMPILE_STATUS, ok, 0)
            if (ok[0] == 0) { Log.w(TAG, "scrim shader: ${GLES30.glGetShaderInfoLog(s)}"); GLES30.glDeleteShader(s); return 0 }
            return s
        }

        fun draw(w: Int, h: Int, dim: Float) {
            if (dim <= 0.01f || w <= 0 || h <= 0) return
            if (program == 0 && !build()) return
            // projectM leaves its own state bound; set everything this pass relies on.
            GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, 0)
            GLES30.glViewport(0, 0, w, h)
            GLES30.glBindVertexArray(0)
            GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, 0)
            GLES30.glDisable(GLES30.GL_DEPTH_TEST)
            GLES30.glDisable(GLES30.GL_SCISSOR_TEST)
            GLES30.glEnable(GLES30.GL_BLEND)
            GLES30.glBlendFuncSeparate(GLES30.GL_SRC_ALPHA, GLES30.GL_ONE_MINUS_SRC_ALPHA, GLES30.GL_ZERO, GLES30.GL_ONE)
            GLES30.glUseProgram(program)
            GLES30.glUniform1f(uDim, dim)
            GLES30.glEnableVertexAttribArray(aPos)
            GLES30.glVertexAttribPointer(aPos, 2, GLES30.GL_FLOAT, false, 0, quad)
            GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4)
            GLES30.glDisableVertexAttribArray(aPos)
            GLES30.glUseProgram(0)
            GLES30.glDisable(GLES30.GL_BLEND)
        }
    }

    private companion object {
        const val TAG = "FmProjectM"
        const val ACTIVE_FPS = 30
        const val IDLE_FPS = 15
        const val IDLE_SPEED = 0.35
        const val IDLE_AFTER_NS = 600_000_000L
        const val AMBIENT_RATE = 44_100.0
        /** One frame's worth at the idle rate (44.1 kHz / 15 fps). */
        const val AMBIENT_SAMPLES = 2940
    }
}
