package com.miku.player

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.material.icons.filled.Lock
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.animation.core.animateFloat
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.miku.player.CyberDarkBg
import com.miku.player.CyberGlassBorder
import com.miku.player.MikuCyan
import com.miku.player.MikuNeonPink
import com.miku.player.MikuTextSecondary
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Miku Music's playback settings: listening profiles, the direct route, car audio and the
 * external USB DAC output. These are the player's own options.
 *
 * The DAC itself (filter, gain, DRE, high power, output, USB DAC mode) is set on the Hardware
 * app's page, the only DAC page on MikuOS. The first row here opens it (DacSettingsLink).
 * Listening profiles still apply their DAC settings through HibyDacBridge on their own.
 */
class HardwareSettingsActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        CrashSentinel.install(this)
        super.onCreate(savedInstanceState)
        setContent {
            HardwareSettingsScreen(onBack = { finish() })
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HardwareSettingsScreen(onBack: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()

    // DTA (bit-perfect DIRECT-to-DAC) live status + playback behavior prefs
    var dtaStatus by remember { mutableStateOf<MikuDirectAudio.DirectStatus?>(null) }
    var pauseOnUnplug by remember { mutableStateOf(PlayerPreferences.loadPauseOnUnplug(ctx)) }

    // Poll the HAL's direct flags while this screen is open so the readout is live truth,
    // not a stale snapshot. Start or stop playback and watch it flip.
    LaunchedEffect(Unit) {
        while (true) {
            withContext(Dispatchers.IO) { dtaStatus = MikuDirectAudio.status(ctx) }
            kotlinx.coroutines.delay(2000)
        }
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(CyberDarkBg)
    ) {
        Image(
            painter = painterResource(id = R.drawable.miku_audiophile_art),
            contentDescription = "Miku artwork",
            modifier = Modifier.fillMaxSize(),
            contentScale = ContentScale.Crop
        )
        Box(
            Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        listOf(
                            Color(0xEE04161A),
                            Color(0x99000000),
                            Color(0xF8040D12)
                        )
                    )
                )
        )

        Column(
            Modifier
                .fillMaxSize()
                .systemBarsPadding()
        ) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                com.miku.player.ui.MikuBackButton(onClick = onBack)
                Text(
                    "PLAYBACK SETTINGS",
                    color = MikuCyan,
                    fontSize = 13.5.sp,
                    fontWeight = FontWeight.Black,
                    fontFamily = AudiowideFont,
                    letterSpacing = 1.sp
                )
                Spacer(Modifier.width(40.dp))
            }

            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 14.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                // ============================================================
                // DAC SETTINGS: the Hardware app's page
                // ============================================================
                item {
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(16.dp))
                            .background(Color(0xDD0A1E26))
                            .border(1.dp, MikuCyan, RoundedCornerShape(16.dp))
                            .clickable { DacSettingsLink.open(ctx) }
                            .padding(14.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text("DAC SETTINGS", color = MikuCyan, fontSize = 11.sp, fontWeight = FontWeight.Bold, fontFamily = AudiowideFont)
                            Text("Filter, gain, DRE, high power, output and USB DAC mode. Opens the Hardware app.", color = MikuTextSecondary, fontSize = 10.5.sp)
                        }
                        Text("OPEN", color = MikuCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold, fontFamily = AudiowideFont)
                    }
                }

                // ============================================================
                // LISTENING PROFILES ENTRY (per-headphone EQ + DAC settings)
                // ============================================================

                item {
                    remember { com.miku.player.profiles.ListeningProfileStore.load(ctx) }
                    val current by com.miku.player.profiles.ListeningProfileStore.currentId.collectAsState()
                    val currentName = remember(current) {
                        com.miku.player.profiles.ListeningProfileStore.get(ctx, current)?.name
                    }
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(16.dp))
                            .background(Color(0xDD0A1E26))
                            .border(1.dp, MikuNeonPink, RoundedCornerShape(16.dp))
                            .clickable {
                                ctx.startActivity(android.content.Intent(ctx, com.miku.player.profiles.ListeningProfilesActivity::class.java))
                            }
                            .padding(14.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text("LISTENING PROFILES", color = MikuNeonPink, fontSize = 11.sp, fontWeight = FontWeight.Bold, fontFamily = AudiowideFont)
                            Text(
                                currentName?.let { "Current: $it" } ?: "Pick your headphones: EQ and DAC settings that follow them",
                                color = MikuTextSecondary, fontSize = 10.5.sp
                            )
                        }
                        Text("OPEN", color = MikuNeonPink, fontSize = 10.sp, fontWeight = FontWeight.Bold, fontFamily = AudiowideFont)
                    }
                }

                // ============================================================
                // SECTION 1.3: CAR & ANDROID AUTO HI-RES AUDIO POLICY
                // ============================================================
                item {
                    var allowUsbAudio by remember { mutableStateOf(PlayerPreferences.loadAllowUsbAudio(ctx)) }
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(16.dp))
                            .background(Color(0xDD0A1E26))
                            .border(1.dp, if (allowUsbAudio) Color(0xFFFF9100) else MikuCyan, RoundedCornerShape(16.dp))
                            .padding(14.dp)
                    ) {
                        Row(
                            Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text("CAR AND ANDROID AUTO", color = MikuCyan, fontSize = 12.sp, fontWeight = FontWeight.Bold, fontFamily = AudiowideFont)
                                Text("Keeps audio on the 3.5mm/4.4mm AUX output in car mode instead of USB.", color = MikuTextSecondary, fontSize = 10.sp)
                            }
                        }

                        Spacer(Modifier.height(10.dp))

                        Row(
                            Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text("Block USB Audio in Car / Android Auto", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                Text(
                                    if (!allowUsbAudio) "On: audio stays on the 3.5mm/4.4mm AUX jack (recommended)."
                                    else "Off: audio goes to the car head unit over USB.",
                                    color = if (!allowUsbAudio) MikuCyan else Color(0xFFFF9100),
                                    fontSize = 10.sp
                                )
                            }
                            Switch(
                                checked = !allowUsbAudio,
                                onCheckedChange = { blockUsb ->
                                    val allow = !blockUsb
                                    allowUsbAudio = allow
                                    PlayerPreferences.saveAllowUsbAudio(ctx, allow)
                                    MikuCarAudioRouter.ensureAnalogIfCar(ctx, "settings-toggle")
                                },
                                colors = SwitchDefaults.colors(checkedThumbColor = MikuCyan, checkedTrackColor = Color(0xFF00695C))
                            )
                        }
                    }
                }

                // ============================================================
                // SECTION 1.5: DTA — DIRECT TRANSPORT AUDIO (BIT-PERFECT PIPELINE)
                // ============================================================
                item {
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(16.dp))
                            .background(Color(0xCC07131A))
                            .border(1.dp, MikuCyan.copy(alpha = 0.35f), RoundedCornerShape(16.dp))
                            .padding(16.dp)
                    ) {
                        Text("DIRECT TRANSPORT AUDIO (DTA)", color = MikuCyan, fontSize = 13.sp, fontWeight = FontWeight.Black, fontFamily = AudiowideFont)
                        Text(
                            "Bit-perfect route: the native sample rate goes straight to the dual CS43198 DACs and skips the Android 48 kHz mixer. The state below is read back live from the audio HAL.",
                            color = MikuTextSecondary, fontSize = 10.sp
                        )
                        Spacer(Modifier.height(10.dp))
                        val st = dtaStatus
                        val direct = st?.weHoldDirect == true
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(
                                Modifier.size(10.dp).clip(CircleShape)
                                    .background(if (direct) Color(0xFF00E676) else if (st?.directFlagEnabled == true) Color(0xFFFFD600) else Color(0xFFFF1744))
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(
                                when {
                                    st == null -> "Reading HAL…"
                                    direct -> "DIRECT ● bit-perfect to DAC (this app holds the route)"
                                    st.directFlagEnabled -> "DIRECT held by: ${st.holderProcess.ifBlank { "unknown" }}"
                                    else -> "MIXED: Android 48 kHz pipeline (no direct route active)"
                                },
                                color = if (direct) Color(0xFF00E676) else Color.White,
                                fontSize = 11.sp, fontWeight = FontWeight.Bold
                            )
                        }
                        Spacer(Modifier.height(4.dp))
                        Text(
                            "Allow-list: " + if (st?.allowListed == true) "com.miku.player granted ✓" else "NOT in direct_support_app_list ✗",
                            color = if (st?.allowListed == true) MikuCyan else Color(0xFFFF1744),
                            fontSize = 9.5.sp
                        )
                        Text(
                            "Direct engages while music is PLAYING on a wired output (never A2DP/speaker).",
                            color = MikuTextSecondary, fontSize = 9.sp
                        )
                        if (st?.allowListed != true) {
                            Spacer(Modifier.height(8.dp))
                            Button(
                                onClick = {
                                    scope.launch(Dispatchers.IO) {
                                        MikuDirectAudio.ensureAllowListed(ctx)
                                        dtaStatus = MikuDirectAudio.status(ctx)
                                    }
                                },
                                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF00A86B)),
                                modifier = Modifier.fillMaxWidth()
                            ) { Text("GRANT DIRECT ROUTE", fontWeight = FontWeight.Black, fontFamily = AudiowideFont, fontSize = 10.sp) }
                        }

                        Spacer(Modifier.height(14.dp))
                        HorizontalDivider(color = Color.White.copy(alpha = 0.1f))
                        Spacer(Modifier.height(14.dp))

                        // Playback behavior — granular, lives here + quick settings (NOT volume modal)
                        Row(
                            Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text("Pause on headphone unplug", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                Text("Stock HiBy behavior: pulling the jack pauses playback instead of switching to the speaker.", color = MikuTextSecondary, fontSize = 10.sp)
                            }
                            Switch(
                                checked = pauseOnUnplug,
                                onCheckedChange = {
                                    pauseOnUnplug = it
                                    PlayerHolder.applyPauseOnUnplug(ctx, it)
                                },
                                colors = SwitchDefaults.colors(checkedThumbColor = MikuCyan, checkedTrackColor = Color(0xFF00695C))
                            )
                        }
                    }
                }

                // ============================================================
                // SECTION 1.6: AUDIO PLAYBACK ENGINE ("SWAPPABLE BONE")
                // ============================================================
                item {
                    // The playback core is NOT swappable any more. The old "LibVLC (OpenSL ES + SoX)"
                    // alternative was a 16-bit, resampled pipeline — a silent audio downgrade one
                    // accidental tap away. Only the bit-perfect DirectPCM DTA sink exists now, and
                    // PlayerHolder re-asserts it on every player creation.
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(16.dp))
                            .background(Color(0xDD0A1E26))
                            .border(1.dp, CyberGlassBorder, RoundedCornerShape(16.dp))
                            .padding(14.dp)
                    ) {
                        Text(
                            "PLAYBACK ENGINE",
                            color = MikuCyan,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            fontFamily = AudiowideFont
                        )
                        Spacer(Modifier.height(6.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.Lock, contentDescription = null, tint = MikuCyan, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(8.dp))
                            Column {
                                Text("DirectPCM Bit-Perfect DTA (ExoPlayer)", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                Text(
                                    "Plays straight to the dual CS43198 DACs: 24/32-bit integer passthrough, float to 24-bit, no resampling, and the DTA direct route when granted. There is no fallback engine.",
                                    color = MikuTextSecondary, fontSize = 10.sp, lineHeight = 13.5.sp
                                )
                            }
                        }
                    }
                }

                // ---------------- USB DAC OUTPUT (M500 → external USB DAC) ----------------
                item {
                    LaunchedEffect(Unit) { MikuUsbDacOutput.init(ctx) }
                    val dac = MikuUsbDacOutput.device
                    val routed = MikuUsbDacOutput.routed
                    val accent = if (routed) MikuCyan else MikuTextSecondary
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(16.dp))
                            .background(Color(0xDD0A1E26))
                            .border(1.dp, if (routed) MikuCyan.copy(alpha = 0.6f) else CyberGlassBorder, RoundedCornerShape(16.dp))
                            .padding(14.dp)
                    ) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text("USB DAC OUTPUT", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                Text(
                                    if (dac == null) "Plug a USB DAC / dongle into the M500 (OTG). Playback follows it bit-perfect at the DAC's native rate."
                                    else MikuUsbDacOutput.statusLine(),
                                    color = accent, fontSize = 10.sp
                                )
                            }
                            Text(if (routed) "● LIVE" else if (dac != null) "○ IDLE" else "—", color = accent, fontSize = 11.sp, fontWeight = FontWeight.Black, fontFamily = AudiowideFont)
                        }
                        if (dac != null) {
                            Spacer(Modifier.height(8.dp))
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text("Device", color = MikuTextSecondary, fontSize = 10.5.sp)
                                Text(dac.name, color = Color.White, fontSize = 10.5.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                            }
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text("Supported", color = MikuTextSecondary, fontSize = 10.5.sp)
                                Text("${dac.bitsLabel} · ${dac.ratesLabel}" + (if (dac.sampleRates.isNotEmpty()) " (${dac.sampleRates.sorted().joinToString("/") { if (it % 1000 == 0) "${it / 1000}" else "%.1f".format(it / 1000f) }} kHz)" else ""), color = MikuCyan, fontSize = 10.5.sp, fontWeight = FontWeight.Bold, maxLines = 2)
                            }
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text("Mixer", color = MikuTextSecondary, fontSize = 10.5.sp)
                                Text(MikuUsbDacOutput.mixerMode.ifBlank { "not routed" }, color = if (MikuUsbDacOutput.mixerMode == "BIT-PERFECT") MikuCyan else MikuTextSecondary, fontSize = 10.5.sp, fontWeight = FontWeight.Bold)
                            }
                        }
                        Spacer(Modifier.height(6.dp))
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text("Prefer USB DAC (exclusive, bit-perfect)", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                Text("Route playback to the USB DAC when attached; native rate / 24-32-bit, no resampling", color = MikuTextSecondary, fontSize = 9.5.sp)
                            }
                            Switch(checked = MikuUsbDacOutput.preferUsb, onCheckedChange = { MikuUsbDacOutput.setPreferUsb(ctx, it) },
                                colors = SwitchDefaults.colors(checkedThumbColor = MikuCyan, checkedTrackColor = Color(0xFF00695C)))
                        }
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text("Volume passthrough", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                Text("Hold media volume at 100% and let the DAC's own control set loudness", color = MikuTextSecondary, fontSize = 9.5.sp)
                            }
                            Switch(checked = MikuUsbDacOutput.volumePassthrough, onCheckedChange = { MikuUsbDacOutput.setVolumePassthrough(ctx, it) },
                                colors = SwitchDefaults.colors(checkedThumbColor = MikuCyan, checkedTrackColor = Color(0xFF00695C)))
                        }
                    }
                }

                item {
                    Spacer(Modifier.height(24.dp))
                }
            }
        }
    }
}
