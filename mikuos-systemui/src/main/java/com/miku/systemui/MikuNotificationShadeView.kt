package com.miku.systemui

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.os.BatteryManager
import android.provider.Settings
import android.text.format.DateUtils
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.animation.animateContentSize
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.Velocity
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BatteryChargingFull
import androidx.compose.material.icons.filled.BatteryFull
import androidx.compose.material.icons.filled.BrightnessMedium
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CloudSync
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import kotlinx.coroutines.flow.drop
import kotlin.math.roundToInt
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.filled.HeadsetOff
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.PowerSettingsNew
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.key
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.compose.ui.layout.layout
import androidx.compose.ui.unit.Density
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.graphics.drawable.toBitmap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/*
 * MikuOS notification shade — Pixel 11 layout & behaviour, Miku skin.
 *
 *   ┌ header: hearts clock + date ─────────── battery · expand chevron ┐
 *   │ QQS: first 4 tiles of the user's order (QsTileOrder)              │  ← pull further /
 *   │ brightness                                                         │    chevron = full
 *   │ media card (active MediaSession)                                   │    2-column QS grid
 *   │ notifications (swipe to dismiss, tap = open, chevron = expand)     │
 *   │ CLEAR ALL                                                          │
 *   └ footer: listener state ········· edit · settings · power · close ┘
 *
 * Surfaces are MikuGlass (see MikuGlass.kt): glass panel over a SurfaceFlinger blur when the
 * device offers one, glass-button tiles, a liquid brightness slider. The pencil opens
 * MikuQsEditor over the panel; the order it saves drives both the quick row and the grid.
 * 8dp grid, ≥40dp touch targets, ≥11sp text, 360×640dp target.
 */

private val ShadeCorner = 28.dp
private val TileCorner = 24.dp
/** Room left around the QS tiles inside the QS clip, for their glass halo and contact shadow. */
private val QsGlassRoom = 8.dp
/** Notification cards: no contact shadow (a long list of shadows reads as mud), quieter rim when ongoing. */
private val NotifGlass = MikuGlass.Card.copy(shadow = 0.dp, opacity = 0.92f)
private val NotifGlassQuiet = NotifGlass.copy(rim = 0.4f, specular = 0.6f)

@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable
fun MikuNotificationShadeView(
    onDismiss: () -> Unit,
    onOpenSettings: () -> Unit,
    onOpenPower: () -> Unit = {},
    startExpanded: Boolean = false,
    /** True when the nav service's finger is still driving the panel (see MikuShadeDrag). */
    followFinger: Boolean = false,
    /** Panel translation (px, ≤ 0) supplied by the host while following the finger. */
    panelOffsetPx: () -> Float = { 0f },
    /** 0..1 fraction of the panel revealed — scrim alpha tracks it. */
    revealProgress: () -> Float = { 1f },
    onPanelHeight: (Int) -> Unit = {}
) {
    val ctx = LocalContext.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current

    // ---------------------------------------------------------------- live state
    var tick by remember { mutableIntStateOf(0) }
    var currentTime by remember { mutableStateOf(SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())) }
    var currentDate by remember { mutableStateOf(SimpleDateFormat("MM / dd / yyyy", Locale.getDefault()).format(Date())) }
    // null until the sticky ACTION_BATTERY_CHANGED has been read — never a placeholder 100%.
    var batteryPct by remember { mutableStateOf<Int?>(null) }
    var isCharging by remember { mutableStateOf(false) }
    var media by remember { mutableStateOf<MikuMediaHub.Now?>(null) }
    var tiles by remember { mutableStateOf<List<QsTile>>(emptyList()) }
    val tileOrder by QsTileOrder.active.collectAsState()
    // Built tiles in the user's order. Anything not in the order is simply not shown.
    val ordered = remember(tiles, tileOrder) {
        val byId = tiles.associateBy { it.id }
        tileOrder.mapNotNull { byId[it] }
    }
    var editing by remember { mutableStateOf(false) }
    val editAnim = remember { Animatable(0f) }
    LaunchedEffect(editing) { editAnim.animateTo(if (editing) 1f else 0f, MikuMotion.settle()) }
    val blur by MikuGlass.backdropBlur.collectAsState()
    val notifs by MikuNotificationStore.items.collectAsState()
    // Screen lock privacy: while the PIN is needed the list shows only app names (or nothing),
    // unless the user allowed content. See MikuLockPrivacy.
    val lockMode by MikuLockPrivacy.mode.collectAsState()
    DisposableEffect(Unit) {
        val r = MikuLockPrivacy.watch(ctx)
        onDispose { runCatching { ctx.unregisterReceiver(r) } }
    }
    val listenerOk by MikuNotificationStore.connected.collectAsState()
    // Album accent (Miku Music → Settings.Global miku_np_accent), ≈30% into teal, animated 400ms.
    LaunchedEffect(Unit) {
        MikuAccent.observe(ctx); MikuPowerProfile.observe(ctx); QsTileOrder.observe(ctx)
        MikuUnlocksWatch.observe(ctx); MikuBeatWatch.observe(ctx)
    }
    val negiBattery by MikuUnlocksWatch.negiBattery.collectAsState()
    // A new tempo or play/pause rebuilds the tiles once (the BPM tile's subtitle and pulse rate).
    LaunchedEffect(Unit) { MikuBeatWatch.intervalMs.drop(1).collect { tick++ } }
    // The window host keeps this composition alive between pulls, so tile state read on the last
    // pull would otherwise still be showing. Every open resumes the lifecycle: re-read then.
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { MikuLockPrivacy.refresh(ctx); tick++ }
    val powerProfile by MikuPowerProfile.profile.collectAsState()
    val quiet = powerProfile == "audio_only" || powerProfile == "idle"
    val accentRaw by MikuAccent.accent.collectAsState()
    val osAccent by animateColorAsState(Color(MikuAccent.tealTinted(accentRaw, 0.30f)), tween(400), label = "osAccent")
    val osAccentBright by animateColorAsState(Color(MikuAccent.tealBrightTinted(accentRaw, 0.30f)), tween(400), label = "osAccentBright")

    LaunchedEffect(tick) {
        // Off the main thread: getTiles reads WifiManager/BluetoothAdapter/etc, which is binder IPC,
        // and a LaunchedEffect body runs on Dispatchers.Main. Doing it inline put several round
        // trips on the UI thread during the shade's very first frame.
        val built = withContext(Dispatchers.IO) {
            runCatching { QuickSettingsModel.getTiles(ctx, scope) { tick++ } + extraTiles(ctx) { tick++ } }
                .getOrDefault(emptyList())
        }
        if (built.isNotEmpty() || tiles.isEmpty()) tiles = built
    }
    LaunchedEffect(Unit) {
        MikuNotificationStore.ensureEnabled(ctx)
        while (true) {
            currentTime = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
            currentDate = SimpleDateFormat("MM / dd / yyyy", Locale.getDefault()).format(Date())
            // Battery from the sticky ACTION_BATTERY_CHANGED (level/scale) — BATTERY_PROPERTY_CAPACITY
            // returns 0/wrong for apps on this vendor, which showed a fake % in the shade.
            runCatching {
                val bi = ctx.registerReceiver(null, android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                val lvl = bi?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                val scale = bi?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
                if (lvl >= 0 && scale > 0) batteryPct = lvl * 100 / scale
                val st = bi?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
                isCharging = st == BatteryManager.BATTERY_STATUS_CHARGING || st == BatteryManager.BATTERY_STATUS_FULL
            }
            media = withContext(Dispatchers.IO) { runCatching { MikuMediaHub.now(ctx) }.getOrNull() }
            withContext(Dispatchers.IO) { MikuLockPrivacy.refresh(ctx) }
            delay(MikuPowerProfile.pollMs(1000L))
        }
    }

    // ---------------------------------------------------------------- expansion
    // 0 = quick-quick settings (compact row), 1 = full QS grid; <0 = being pulled up to dismiss.
    val expand = remember { Animatable(if (startExpanded) 1f else 0f) }
    // derivedStateOf, NOT `expand.value > 0.5f`. A raw read here invalidates this whole composable
    // on every animation frame, which is the same jank the qsH/pullUp reads caused.
    val expanded by remember { derivedStateOf { expand.value > 0.5f } }
    val expandRangePx = with(density) { 220.dp.toPx() }
    var dragStartValue by remember { mutableStateOf(0f) }
    val panelIn = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        when {
            followFinger -> panelIn.snapTo(1f)                       // the finger IS the entrance
            MikuPowerProfile.lowPower -> panelIn.animateTo(1f, tween(120))
            else -> panelIn.animateTo(1f, spring(dampingRatio = 0.72f, stiffness = Spring.StiffnessMediumLow))
        }
    }

    fun settle() {
        scope.launch {
            val v = expand.value
            when {
                dragStartValue < 0.5f && v < -0.14f -> onDismiss()
                v >= 0.5f -> expand.animateTo(1f, MikuMotion.settle())
                else -> expand.animateTo(0f, MikuMotion.settle())
            }
        }
    }

    val dragModifier = Modifier.pointerInput(Unit) {
        detectVerticalDragGestures(
            onDragStart = { dragStartValue = expand.value },
            onDragEnd = { settle() },
            onDragCancel = { settle() },
            onVerticalDrag = { change, dy ->
                change.consume()
                val next = (expand.value + dy / expandRangePx).coerceIn(-0.4f, 1.12f)
                scope.launch { expand.snapTo(next) }
            }
        )
    }

    // Pull further than the panel's own height → QS keeps expanding continuously (no two-state jump).
    var panelHpx by remember { mutableIntStateOf(0) }
    if (followFinger) {
        LaunchedEffect(Unit) {
            val serial = MikuShadeDrag.state.value.serial
            var drove = false
            MikuShadeDrag.state.collect { st ->
                if (st.serial != serial) return@collect
                if (st.fingerDown) {
                    val extra = st.dragPx - panelHpx
                    if (panelHpx > 0 && extra > 0f) { drove = true; expand.snapTo((extra / expandRangePx).coerceIn(0f, 1.12f)) }
                } else if (drove) { drove = false; dragStartValue = 1f; settle() }
            }
        }
    }

    // Pixel: dragging the notification list down at its top expands QS; dragging up with nothing
    // left to scroll collapses the panel (and dismisses past the threshold) — same physics as the
    // header drag, so the whole panel feels like one sheet.
    val listState = rememberLazyListState()
    var nestedDragging by remember { mutableStateOf(false) }
    val nested = remember(expandRangePx) {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (source != NestedScrollSource.UserInput || available.y <= 0f) return Offset.Zero
                val atTop = listState.firstVisibleItemIndex == 0 && listState.firstVisibleItemScrollOffset == 0
                if (!atTop || expand.value >= 1.12f) return Offset.Zero
                if (!nestedDragging) { nestedDragging = true; dragStartValue = expand.value.coerceIn(0f, 1f) }
                scope.launch { expand.snapTo((expand.value + available.y / expandRangePx).coerceIn(0f, 1.12f)) }
                return Offset(0f, available.y)
            }
            override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
                if (source != NestedScrollSource.UserInput || available.y >= 0f) return Offset.Zero
                if (!nestedDragging) { nestedDragging = true; dragStartValue = expand.value.coerceIn(0f, 1f) }
                scope.launch { expand.snapTo((expand.value + available.y / expandRangePx).coerceIn(-0.4f, 1.12f)) }
                return Offset(0f, available.y)
            }
            override suspend fun onPreFling(available: Velocity): Velocity {
                if (nestedDragging) { nestedDragging = false; settle() }
                return Velocity.Zero
            }
            override suspend fun onPostFling(consumed: Velocity, available: Velocity): Velocity {
                if (nestedDragging) { nestedDragging = false; settle() }
                return Velocity.Zero
            }
        }
    }

    BackHandler(enabled = true) {
        when {
            editing -> editing = false
            expanded -> scope.launch { expand.animateTo(0f, MikuMotion.settle()) }
            else -> onDismiss()
        }
    }

    val compactH = 56.dp
    val gridRows = (ordered.size + 1) / 2
    val expandedH = (gridRows * 64 + (gridRows - 1).coerceAtLeast(0) * 8).dp
    // PERF (2026-09-17): these used to be `val qsH = ... expand.value ...` read right here in the
    // composition body. `expand` is an Animatable, so every single frame of the pull invalidated
    // and re-ran this whole 847-line composable — 39.7% janky frames, 450ms at the 90th percentile,
    // "Slow UI thread: 21" in gfxinfo. Animated state has to be read in the layout/draw lambda that
    // uses it, never in composition. Nothing here reads expand.value any more; the readers below do.
    val qsHeightPx = { density: Density, e: Float ->
        with(density) { (compactH + (expandedH - compactH) * e.coerceIn(0f, 1f)).roundToPx() }
    }
    // Structural only: which branch of the QS box exists. A boolean flips twice per gesture instead
    // of a float changing every frame, so composition runs twice instead of sixty times a second.
    val showCompact by remember { derivedStateOf { expand.value.coerceIn(0f, 1f) < 0.999f } }
    val showGrid by remember { derivedStateOf { expand.value.coerceIn(0f, 1f) > 0.001f } }

    Box(
        Modifier
            .fillMaxSize()
            .drawBehind { drawRect(Color.Black.copy(alpha = MikuGlass.scrimAlpha(blur) * panelIn.value * revealProgress())) }
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onDismiss() }
    ) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val maxPanelH = maxHeight - 28.dp   // keep clear of the home-pill zone
            Column(
                Modifier
                    .fillMaxWidth()
                    .heightIn(max = maxPanelH)
                    .onSizeChanged { panelHpx = it.height; onPanelHeight(it.height) }
                    .graphicsLayer {
                        val pullUp = (-expand.value).coerceAtLeast(0f)   // 0..0.4 while dragging up to dismiss
                        translationY = panelOffsetPx() - (1f - panelIn.value) * size.height * 0.35f - pullUp * size.height * 0.5f
                        alpha = (0.6f + 0.4f * panelIn.value) * (1f - pullUp * 0.8f) * (1f - editAnim.value)
                    }
                    .mikuGlass(
                        RoundedCornerShape(bottomStart = ShadeCorner, bottomEnd = ShadeCorner),
                        MikuGlass.panelStyle(blur), accent = osAccentBright
                    )
                    .drawBehind {
                        // soft teal + pink plasma glows behind the glass
                        drawCircle(Brush.radialGradient(listOf(MikuTeal.copy(alpha = 0.18f), Color.Transparent), center = androidx.compose.ui.geometry.Offset(size.width * 0.15f, size.height * 0.05f), radius = size.width * 0.6f), radius = size.width * 0.6f, center = androidx.compose.ui.geometry.Offset(size.width * 0.15f, size.height * 0.05f))
                        drawCircle(Brush.radialGradient(listOf(MikuPink.copy(alpha = 0.10f), Color.Transparent), center = androidx.compose.ui.geometry.Offset(size.width * 0.9f, size.height * 0.4f), radius = size.width * 0.5f), radius = size.width * 0.5f, center = androidx.compose.ui.geometry.Offset(size.width * 0.9f, size.height * 0.4f))
                    }
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {}
            ) {
                // ---------------------------------------------------- header (draggable)
                Row(
                    Modifier
                        .fillMaxWidth()
                        .then(dragModifier)
                        .padding(start = 16.dp, end = 8.dp, top = 24.dp)
                        .height(64.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (quiet) QuietClock(currentTime, currentDate) else CyberPlasmaGlowClock(time = currentTime, date = currentDate)
                    Spacer(Modifier.weight(1f))
                    // battery chip
                    Row(
                        Modifier
                            .height(32.dp)
                            .mikuGlass(RoundedCornerShape(16.dp), MikuGlass.Chip, accent = osAccentBright)
                            .padding(horizontal = 10.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        if (negiBattery) {
                            NegiBattery(batteryPct ?: 0, isCharging, Modifier.size(18.dp))
                        } else {
                            Icon(
                                if (isCharging) Icons.Default.BatteryChargingFull else Icons.Default.BatteryFull,
                                null, tint = if (isCharging) Color(0xFF69F0AE) else MikuTealBright, modifier = Modifier.size(16.dp)
                            )
                        }
                        Spacer(Modifier.width(4.dp))
                        Text(batteryPct?.let { "$it%" } ?: "—%", color = MikuWhite, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    }
                    Spacer(Modifier.width(4.dp))
                    // expand / collapse chevron (40dp target)
                    GlassIconButton(
                        if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                        if (expanded) "Collapse quick settings" else "Expand quick settings",
                        MikuTextSecondary, accent = osAccentBright
                    ) { scope.launch { expand.animateTo(if (expanded) 0f else 1f, MikuMotion.settle()) } }
                    Spacer(Modifier.width(4.dp))
                }
                // header underline — carries the album accent
                Box(
                    Modifier.fillMaxWidth().padding(horizontal = 16.dp).height(2.dp)
                        .background(Brush.horizontalGradient(listOf(osAccentBright, osAccent.copy(alpha = 0.35f), Color.Transparent)))
                )

                Spacer(Modifier.height(8.dp))

                // ---------------------------------------------------- quick settings
                Box(
                    Modifier
                        .fillMaxWidth()
                        .then(dragModifier)
                        .padding(horizontal = 16.dp - QsGlassRoom)
                        // Height in the LAYOUT phase. Modifier.height(qsH) would need a new
                        // composition for every pixel of the pull; this re-measures without one.
                        .layout { measurable, constraints ->
                            val h = qsHeightPx(this, expand.value) + 2 * QsGlassRoom.roundToPx()
                            val p = measurable.measure(constraints.copy(minHeight = h, maxHeight = h))
                            layout(p.width, h) { p.place(0, 0) }
                        }
                        // The clip hides the grid while it is taller than the box mid-pull. It sits
                        // QsGlassRoom outside the tiles so their halo and shadow are not shaved off.
                        .clip(RoundedCornerShape(12.dp))
                        .padding(QsGlassRoom)
                ) {
                    // compact row
                    if (showCompact) {
                        val compact = ordered.take(QsTileOrder.QUICK_COUNT)
                        Row(
                            Modifier.fillMaxWidth().height(compactH)
                                .graphicsLayer { alpha = 1f - expand.value.coerceIn(0f, 1f) },
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            compact.forEach { t -> key(t.id) { GlassCompactTile(t, Modifier.weight(1f), osAccentBright, onOpensUi = onDismiss) } }
                            // keep tile widths stable when the user has fewer than four active
                            repeat(QsTileOrder.QUICK_COUNT - compact.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                    // expanded grid
                    if (showGrid) {
                        Column(
                            Modifier.fillMaxWidth().graphicsLayer {
                                val e = expand.value.coerceIn(0f, 1f)
                                alpha = e; translationY = (1f - e) * 24f
                            },
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            ordered.chunked(2).forEach { pair ->
                                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    pair.forEach { t -> key(t.id) { GlassGridTile(t, Modifier.weight(1f), osAccentBright, onOpensUi = onDismiss) } }
                                    if (pair.size == 1) Spacer(Modifier.weight(1f))
                                }
                            }
                        }
                    }
                }

                Spacer(Modifier.height(8.dp))

                // ---------------------------------------------------- brightness
                BrightnessRow(Modifier.fillMaxWidth().then(dragModifier).padding(horizontal = 16.dp))

                Spacer(Modifier.height(8.dp))

                // ---------------------------------------------------- media + notifications
                val visibleNotifs = remember(notifs, media, lockMode) {
                    val l = notifs.filter { !(it.hasMediaSession && media != null && it.pkg == media?.pkg) }
                    when (lockMode) {
                        MikuLockPrivacy.Mode.FULL -> l
                        MikuLockPrivacy.Mode.HIDDEN -> emptyList()
                        // Ongoing media rows keep their own card above, everything else is the app name only.
                        MikuLockPrivacy.Mode.REDACTED -> l.map { MikuLockPrivacy.redact(it) }
                    }
                }
                var openGroups by remember { mutableStateOf(setOf<String>()) }
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxWidth().weight(1f, fill = false).nestedScroll(nested),
                    contentPadding = PaddingValues(horizontal = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    media?.let { m ->
                        item(key = "media") { MediaCard(m, onOpen = { openApp(ctx, m.pkg); onDismiss() }) }
                    }
                    // Grouped by app, newest app first, apps with only ongoing ones last. An app
                    // with one notification is a plain row. More than one gets a header with the
                    // count. Past two rows the group folds until the header is tapped.
                    notifGroups(visibleNotifs).forEach { (pkg, group) ->
                        val openN: (MikuNotif) -> Unit = { n ->
                            if (lockMode != MikuLockPrivacy.Mode.FULL) { onDismiss(); MikuLockPrivacy.requestUnlock(ctx) }
                            else if (MikuNotificationStore.open(ctx, n)) onDismiss()
                        }
                        val replyN: (MikuNotif) -> Unit = { n -> onDismiss(); MikuReplyActivity.start(ctx, n.key) }
                        if (group.size == 1) {
                            val n = group[0]
                            item(key = n.key) {
                                NotifRow(n, modifier = Modifier.animateItem(
                                    fadeInSpec = tween(MikuMotion.ms(150)), fadeOutSpec = tween(MikuMotion.ms(120)),
                                    placementSpec = spring(dampingRatio = MikuMotion.SETTLE_DAMPING, stiffness = MikuMotion.SETTLE_STIFFNESS)
                                ), onOpen = { openN(n) }, onReply = { replyN(n) }, onDismiss = { MikuNotificationStore.dismiss(n.key) })
                            }
                        } else {
                            val open = pkg in openGroups || group.size <= 2
                            item(key = "group:$pkg") {
                                NotifGroupHeader(group, expanded = open, canFold = group.size > 2,
                                    modifier = Modifier.animateItem(fadeInSpec = tween(MikuMotion.ms(150)), fadeOutSpec = tween(MikuMotion.ms(120))),
                                    onToggle = { openGroups = if (pkg in openGroups) openGroups - pkg else openGroups + pkg },
                                    onClearGroup = { group.filter { it.isClearable }.forEach { MikuNotificationStore.dismiss(it.key) } })
                            }
                            val shown = if (open) group else group.take(1)
                            items(shown, key = { it.key }) { n ->
                                NotifRow(n, modifier = Modifier.padding(start = 10.dp).animateItem(
                                    fadeInSpec = tween(MikuMotion.ms(150)), fadeOutSpec = tween(MikuMotion.ms(120)),
                                    placementSpec = spring(dampingRatio = MikuMotion.SETTLE_DAMPING, stiffness = MikuMotion.SETTLE_STIFFNESS)
                                ), onOpen = { openN(n) }, onReply = { replyN(n) }, onDismiss = { MikuNotificationStore.dismiss(n.key) })
                            }
                            if (!open) {
                                item(key = "more:$pkg") {
                                    Text(
                                        "${group.size - 1} more from ${group[0].appLabel}",
                                        color = MikuTextSecondary, fontSize = 11.sp,
                                        modifier = Modifier.fillMaxWidth().padding(start = 22.dp)
                                            .clickable { openGroups = openGroups + pkg }.padding(vertical = 6.dp)
                                    )
                                }
                            }
                        }
                    }
                    if (visibleNotifs.any { it.isClearable }) {
                        item(key = "clear") {
                            Box(Modifier.fillMaxWidth().padding(top = 4.dp, bottom = 4.dp), contentAlignment = Alignment.Center) {
                                GlassChipButton("CLEAR ALL", accent = osAccentBright, height = 40.dp) {
                                    MikuHaptics.pop(view)
                                    MikuNotificationStore.dismissAll()
                                }
                            }
                        }
                    }
                    if (visibleNotifs.isEmpty() && media == null) {
                        item(key = "empty") {
                            Column(
                                Modifier.fillMaxWidth().height(96.dp).clickable(enabled = !listenerOk) { MikuNotificationStore.ensureEnabled(ctx) },
                                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center
                            ) {
                                Text("♥", color = MikuTeal.copy(alpha = 0.55f), fontSize = 28.sp)
                                Text(
                                    if (listenerOk) "No notifications" else "Notification access is off. Tap to turn it on.",
                                    color = MikuTextSecondary, fontSize = 12.sp
                                )
                            }
                        }
                    }
                    item(key = "bottomPad") { Spacer(Modifier.height(4.dp)) }
                }

                // ---------------------------------------------------- footer
                Row(
                    Modifier
                        .fillMaxWidth()
                        .then(dragModifier)                 // swipe up anywhere on the panel collapses it
                        .padding(horizontal = 12.dp, vertical = 4.dp)
                        .height(48.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        "MikuOS", color = MikuTeal.copy(alpha = 0.8f), fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.sp,
                        modifier = Modifier.padding(start = 8.dp)
                    )
                    Spacer(Modifier.weight(1f))
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        GlassIconButton(Icons.Default.Edit, "Edit tiles", osAccentBright) { editing = true }
                        GlassIconButton(Icons.Default.Settings, "Settings", MikuTealBright) { onDismiss(); onOpenSettings() }
                        GlassIconButton(Icons.Default.PowerSettingsNew, "Power", MikuPinkBright) { onDismiss(); onOpenPower() }
                        GlassIconButton(Icons.Default.Close, "Close", MikuTextSecondary) { onDismiss() }
                    }
                }
                // drag handle (swipe up to close)
                Box(
                    Modifier
                        .fillMaxWidth()
                        .then(dragModifier)
                        .height(20.dp),
                    contentAlignment = Alignment.TopCenter
                ) {
                    Box(Modifier.padding(top = 4.dp).width(40.dp).height(4.dp).clip(RoundedCornerShape(2.dp)).background(MikuTeal.copy(alpha = 0.55f)))
                }
            }
            // ---------------------------------------------------- tile editor (pencil)
            val showEditor by remember { derivedStateOf { editing || editAnim.value > 0.001f } }
            if (showEditor) {
                // Full-size catcher above the (faded-out) panel: the panel is invisible while the
                // editor is up but would still take touches below the editor's bottom edge.
                // A tap outside the editor closes it; every drop has already been saved.
                Box(
                    Modifier
                        .fillMaxSize()
                        .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { editing = false }
                ) {
                    MikuQsEditor(
                        onDone = { editing = false },
                        accent = osAccent,
                        accentBright = osAccentBright,
                        modifier = Modifier
                            .heightIn(max = maxPanelH)
                            .graphicsLayer {
                                val e = editAnim.value
                                alpha = e.coerceIn(0f, 1f)
                                translationY = -(1f - e) * 48f
                                scaleX = 0.96f + 0.04f * e; scaleY = scaleX
                            }
                            // eat taps on the editor's own background
                            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {}
                    )
                }
            }
        }
    }
}

/**
 * The launcher's BPM game, by the contract in MikuBpmGameActivity: action OPEN_BPM_GAME, extra
 * "from". An older launcher without that activity gets its main screen with `open_bpm`, the same
 * fallback Miku Music uses.
 */
private fun openBpmGame(ctx: Context) {
    val game = Intent("com.miku.action.OPEN_BPM_GAME")
        .setPackage("com.miku.launcher")
        .putExtra("from", "qs")
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    if (runCatching { ctx.startActivity(game) }.isSuccess) return
    runCatching {
        ctx.packageManager.getLaunchIntentForPackage("com.miku.launcher")?.apply {
            putExtra("open_bpm", true)
            putExtra("from", "qs")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
        }?.let { ctx.startActivity(it) }
    }
}

/**
 * Battery as a leek, held at the leek-spin angle: the white stalk fills with the level (green
 * while charging, pink when low), green leaves on top, teal outline. Same slot as the battery
 * icon in the header chip.
 */
@Composable
private fun NegiBattery(pct: Int, charging: Boolean, modifier: Modifier) {
    androidx.compose.foundation.Canvas(modifier) {
        val u = size.minDimension / 18f
        val len = size.minDimension * 1.3f
        val leafLen = len * 0.36f
        val x0 = -len / 2f
        val xs = len / 2f - leafLen
        val th = 4.6f * u
        val c = Offset(size.width / 2f, size.height / 2f)
        val frac = (pct / 100f).coerceIn(0f, 1f)
        val fillColor = when {
            charging -> Color(0xFF69F0AE)
            pct <= 15 -> MikuPinkBright
            else -> MikuWhite
        }
        rotate(-40f, pivot = c) {
            translate(c.x, c.y) {
                val cr = androidx.compose.ui.geometry.CornerRadius(th / 2f)
                // roots
                for (dy in floatArrayOf(-1.2f, 0f, 1.2f)) {
                    drawLine(MikuTeal.copy(alpha = 0.85f), Offset(x0, dy * u), Offset(x0 - 2.2f * u, dy * 1.8f * u), strokeWidth = 0.9f * u)
                }
                // stalk: empty, then filled to the level
                drawRoundRect(Color.White.copy(alpha = 0.20f), Offset(x0, -th / 2f), androidx.compose.ui.geometry.Size(xs - x0, th), cr)
                val fw = ((xs - x0) * frac).coerceAtLeast(if (pct > 0) th * 0.6f else 0f)
                if (fw > 0f) drawRoundRect(fillColor, Offset(x0, -th / 2f), androidx.compose.ui.geometry.Size(fw, th), cr)
                drawRoundRect(MikuTealBright, Offset(x0, -th / 2f), androidx.compose.ui.geometry.Size(xs - x0, th), cr,
                    style = androidx.compose.ui.graphics.drawscope.Stroke(0.9f * u))
                // pale collar where white turns green
                drawRect(Color(0xFFC5E1A5), Offset(xs - 1.2f * u, -th / 2f + 0.5f * u), androidx.compose.ui.geometry.Size(1.6f * u, th - u))
                // leaves
                val leaves = Brush.linearGradient(listOf(Color(0xFF7CB342), Color(0xFF2E7D32)), start = Offset(xs, 0f), end = Offset(len / 2f, 0f))
                val up = androidx.compose.ui.graphics.Path().apply {
                    moveTo(xs, -th / 2f)
                    quadraticTo(xs + leafLen * 0.55f, -th * 0.9f, len / 2f, -th * 1.25f)
                    quadraticTo(xs + leafLen * 0.5f, -th * 0.15f, xs, th * 0.1f)
                    close()
                }
                val down = androidx.compose.ui.graphics.Path().apply {
                    moveTo(xs, -th * 0.1f)
                    quadraticTo(xs + leafLen * 0.45f, th * 0.25f, len / 2f - u, th * 1.15f)
                    quadraticTo(xs + leafLen * 0.4f, th * 0.95f, xs, th / 2f)
                    close()
                }
                drawPath(down, leaves)
                drawPath(up, leaves)
                drawPath(up, MikuTeal.copy(alpha = 0.7f), style = androidx.compose.ui.graphics.drawscope.Stroke(0.6f * u))
            }
        }
    }
}

private fun openApp(ctx: Context, pkg: String) {
    runCatching {
        ctx.packageManager.getLaunchIntentForPackage(pkg)?.apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }?.let { ctx.startActivity(it) }
    }
}

/** Device-specific extras that are not in QuickSettingsModel: ingest engine, pause-on-unplug, track HUD. */
private fun extraTiles(ctx: Context, onRefresh: () -> Unit): List<QsTile> {
    val cr = ctx.contentResolver
    val ingest = Settings.Global.getInt(cr, "miku_ingest_enabled", 0) == 1
    val pause = Settings.Global.getInt(cr, "miku_pause_on_unplug", 1) == 1
    val hud = Settings.Global.getInt(cr, "miku_track_hud_enabled", 1) == 1
    val dacBadge = MikuDacBadge.isEnabled(ctx)
    // Idle dim ladder (MikuIdleDim.kt): on/off here, timings cycled by long-press. Every value is
    // a Settings.Global key too, so `settings put global miku_idle_dim_active_sec 45` retunes it
    // live without a rebuild - same idiom as the rest of the MikuOS toggles.
    val idleDimOn = Settings.Global.getInt(cr, MikuIdleDimSettings.KEY_ENABLED, 1) == 1
    val idleActiveSec = MikuIdleDimSettings.activeSec(ctx)
    val idleDimSec = MikuIdleDimSettings.dimSec(ctx)
    val idleAmbientSec = MikuIdleDimSettings.ambientSec(ctx)
    fun putGlobal(k: String, v: Int) {
        runCatching { Settings.Global.putInt(cr, k, v) }.onFailure { RootShell.execFast("settings put global $k $v") }
    }
    return listOf(
        QsTile("ingest", "Network sync", if (ingest) "Rsync on" else "SD card only", Icons.Default.CloudSync, ingest,
            onClick = {
                putGlobal("miku_ingest_enabled", if (ingest) 0 else 1)
                ctx.sendBroadcast(Intent("com.miku.launcher.action.INGEST_ENABLED").setPackage("com.miku.launcher").putExtra("enabled", !ingest))
                onRefresh()
            },
            onLongClick = { runCatching { ctx.startActivity(Intent().setClassName("com.miku.launcher", "com.miku.launcher.MikuLauncherActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } }),
        QsTile("pause_unplug", "Pause on unplug", if (pause) "Pauses when unplugged" else "Keeps playing", Icons.Default.HeadsetOff, pause,
            onClick = {
                putGlobal("miku_pause_on_unplug", if (pause) 0 else 1)
                ctx.sendBroadcast(Intent("com.miku.player.SET_PAUSE_ON_UNPLUG").setPackage("com.miku.player").putExtra("enabled", !pause))
                onRefresh()
            }),
        QsTile("track_hud", "Track HUD", if (hud) "Pops over apps" else "Off", Icons.Default.MusicNote, hud,
            onClick = { putGlobal("miku_track_hud_enabled", if (hud) 0 else 1); onRefresh() }),
        // The DAC badge in the status bar (MikuDacBadge). It observes the key, so this applies live.
        QsTile("dac_badge", "DAC badge", if (dacBadge) "Shown in the status bar" else "Off", Icons.Default.GraphicEq, dacBadge,
            accent = dacTheme(MikuDacBadge.readState(ctx)).primary,
            onClick = { putGlobal(MikuDacBadge.KEY_ENABLED, if (dacBadge) 0 else 1); onRefresh() }),
        QsTile(
            "idle_dim", "Idle Dim",
            if (idleDimOn) MikuIdleDimSettings.presetName(idleActiveSec, idleDimSec, idleAmbientSec) +
                " \u00b7 dim " + idleActiveSec + "s \u00b7 sleep " + (idleActiveSec + idleDimSec + idleAmbientSec) + "s"
            else "Off, screen goes straight to black",
            Icons.Default.BrightnessMedium, idleDimOn,
            longPressOpensUi = false,
            onClick = {
                putGlobal(MikuIdleDimSettings.KEY_ENABLED, if (idleDimOn) 0 else 1)
                onRefresh()
            },
            onLongClick = {
                // Cycle Quick -> Normal -> Relaxed. A custom (shell-set) ladder lands on Quick.
                val cur = Triple(idleActiveSec, idleDimSec, idleAmbientSec)
                val idx = MikuIdleDimSettings.PRESETS.indexOf(cur)
                MikuIdleDimSettings.applyPreset(ctx, MikuIdleDimSettings.PRESETS[(idx + 1) % MikuIdleDimSettings.PRESETS.size])
                onRefresh()
            }),
        // Opt-in tile (not in the default set; added from the editor). Opens the launcher's BPM
        // game; the icon pulses at the playing track's tempo.
        MikuBeatWatch.intervalMs.value.let { beat ->
            QsTile(
                "bpm_game", "BPM Game",
                if (beat > 0) "${(60000f / beat).roundToInt()} BPM \u00b7 tap to play" else "Tap along to the beat",
                Icons.Default.Favorite, false,
                clickOpensUi = true,
                beatMs = beat,
                onClick = { openBpmGame(ctx) }
            )
        }
    )
}

// ------------------------------------------------------------------------------------ brightness

/**
 * Own composable so a drag recomposes this row only. The brightness used to be state in the
 * shade's body, which re-ran the whole shade on every slider step.
 */
@Composable
private fun BrightnessRow(modifier: Modifier) {
    val ctx = LocalContext.current
    val cr = ctx.contentResolver
    var brightness by remember {
        mutableIntStateOf(runCatching { Settings.System.getInt(cr, Settings.System.SCREEN_BRIGHTNESS) }.getOrDefault(128))
    }
    // Re-read on every open (the window host keeps this composition alive between pulls).
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        runCatching { brightness = Settings.System.getInt(cr, Settings.System.SCREEN_BRIGHTNESS) }
    }
    MikuGlassSlider(
        value = brightness.toFloat(),
        onValueChange = { v ->
            val next = v.toInt()
            if (next == brightness) return@MikuGlassSlider
            brightness = next
            runCatching {
                Settings.System.putInt(cr, Settings.System.SCREEN_BRIGHTNESS_MODE, Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL)
                Settings.System.putInt(cr, Settings.System.SCREEN_BRIGHTNESS, next)
            }
        },
        valueRange = 8f..255f,
        // Warm amber to warm white with a sun, the same identity as the brightness HUD
        // (MikuBrightnessHud), so brightness never looks like the teal/pink volume controls.
        icon = Icons.Default.WbSunny,
        contentDescription = "Brightness",
        accent = Color(0xFFFF8F00),
        accentBright = Color(0xFFFFE082),
        accent2 = Color(0xFFFFF8E1),
        modifier = modifier
    )
}

// ------------------------------------------------------------------------------------ media card

@Composable
private fun MediaCard(m: MikuMediaHub.Now, onOpen: () -> Unit) {
    val view = LocalView.current
    val accent = remember(m.art) { Color(MikuMediaHub.dominantColor(m.art)) }
    val progress = if (m.durationMs > 0) (m.positionMs.toFloat() / m.durationMs).coerceIn(0f, 1f) else 0f
    Column(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp)
            .mikuGlass(RoundedCornerShape(TileCorner), MikuGlass.Card, accent = accent)
            // the art's colour bleeds in from the left, as before, now under the glass sheen
            .background(Brush.horizontalGradient(listOf(accent.copy(alpha = 0.30f), Color.Transparent)))
            .clickable { onOpen() }
    ) {
        Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(56.dp).clip(RoundedCornerShape(14.dp)).background(MikuSurface2), contentAlignment = Alignment.Center) {
                val art = m.art
                if (art != null) Image(art.asImageBitmap(), null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                else Icon(Icons.Default.MusicNote, null, tint = accent, modifier = Modifier.size(26.dp))
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    m.appIcon?.let { d ->
                        val bmp = remember(m.pkg) { runCatching { d.toBitmap(32, 32).asImageBitmap() }.getOrNull() }
                        if (bmp != null) Image(bmp, null, modifier = Modifier.size(12.dp).clip(RoundedCornerShape(3.dp)))
                        Spacer(Modifier.width(4.dp))
                    }
                    Text(m.appLabel.uppercase(), color = accent, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.sp, maxLines = 1)
                }
                Text(m.title.ifBlank { "Now playing" }, color = MikuWhite, fontSize = 14.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(m.artist.ifBlank { m.album }, color = MikuTextSecondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Spacer(Modifier.width(4.dp))
            Box(Modifier.size(40.dp).clip(CircleShape).clickable { MikuHaptics.confirm(view); m.controller.transportControls.skipToPrevious() }, contentAlignment = Alignment.Center) {
                Icon(Icons.Default.SkipPrevious, "Previous", tint = MikuWhite, modifier = Modifier.size(22.dp))
            }
            PlayPauseButton(m.isPlaying, accent) {
                MikuHaptics.confirm(view)
                if (m.isPlaying) m.controller.transportControls.pause() else m.controller.transportControls.play()
            }
            Box(Modifier.size(40.dp).clip(CircleShape).clickable { MikuHaptics.confirm(view); m.controller.transportControls.skipToNext() }, contentAlignment = Alignment.Center) {
                Icon(Icons.Default.SkipNext, "Next", tint = MikuWhite, modifier = Modifier.size(22.dp))
            }
        }
        // progress hairline
        Box(Modifier.fillMaxWidth().height(3.dp).background(MikuSurface2)) {
            Box(Modifier.fillMaxWidth(progress).fillMaxHeight().background(Brush.horizontalGradient(listOf(accent, MikuPinkBright))))
        }
    }
}

// ------------------------------------------------------------------------------------ notification row

/** Notifications grouped by app: newest app first, apps whose notifications are all ongoing last. */
private fun notifGroups(list: List<MikuNotif>): List<Pair<String, List<MikuNotif>>> {
    val by = LinkedHashMap<String, MutableList<MikuNotif>>()
    list.forEach { by.getOrPut(it.pkg) { ArrayList() }.add(it) }
    return by.entries
        .map { (pkg, l) -> pkg to l.sortedWith(compareBy<MikuNotif> { it.isOngoing }.thenByDescending { it.postTime }) }
        .sortedWith(compareBy<Pair<String, List<MikuNotif>>> { (_, l) -> l.all { it.isOngoing } }
            .thenByDescending { (_, l) -> l.maxOf { it.postTime } })
}

/** Header over an app's notifications: icon, app name, count, fold chevron, clear-group. */
@Composable
private fun NotifGroupHeader(
    group: List<MikuNotif>,
    expanded: Boolean,
    canFold: Boolean,
    modifier: Modifier = Modifier,
    onToggle: () -> Unit,
    onClearGroup: () -> Unit
) {
    val first = group[0]
    val appIconBmp = remember(first.pkg) { runCatching { first.appIcon?.toBitmap(48, 48)?.asImageBitmap() }.getOrNull() }
    val accent = if (first.accent != 0) Color(first.accent) else MikuTeal
    Row(
        modifier.fillMaxWidth().height(32.dp).clip(RoundedCornerShape(12.dp))
            .clickable(enabled = canFold) { onToggle() }
            .padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (appIconBmp != null) Image(appIconBmp, null, modifier = Modifier.size(18.dp).clip(RoundedCornerShape(5.dp)))
        else Box(Modifier.size(18.dp).clip(CircleShape).background(accent.copy(alpha = 0.6f)))
        Spacer(Modifier.width(8.dp))
        Text(first.appLabel, color = accent, fontSize = 12.sp, fontWeight = FontWeight.Bold, maxLines = 1,
            overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
        Text("  ${group.size}", color = MikuMuted, fontSize = 12.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.weight(1f))
        if (group.any { it.isClearable }) {
            Text("Clear", color = MikuTextSecondary, fontSize = 11.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable { onClearGroup() }.padding(horizontal = 8.dp, vertical = 6.dp))
        }
        if (canFold) Icon(if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore, null, tint = MikuTextSecondary, modifier = Modifier.size(18.dp))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NotifRow(n: MikuNotif, onOpen: () -> Unit, onReply: () -> Unit, onDismiss: () -> Unit, modifier: Modifier = Modifier) {
    val ctx = LocalContext.current
    val view = LocalView.current
    var expanded by remember(n.key) { mutableStateOf(false) }
    val state = rememberSwipeToDismissBoxState(
        confirmValueChange = { v ->
            if (v != SwipeToDismissBoxValue.Settled) {
                if (n.isClearable) { MikuHaptics.confirm(view); onDismiss(); true } else false
            } else true
        },
        positionalThreshold = { it * 0.4f }
    )
    val appIconBmp = remember(n.pkg) { runCatching { n.appIcon?.toBitmap(48, 48)?.asImageBitmap() }.getOrNull() }
    val accent = if (n.accent != 0) Color(n.accent) else MikuTeal
    val timeLabel = remember(n.postTime) {
        DateUtils.getRelativeTimeSpanString(n.postTime, System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS, DateUtils.FORMAT_ABBREV_RELATIVE).toString()
    }
    // Something to show when expanded: longer text, a chat history, actions, or a title that was cut.
    val canExpand = n.actions.isNotEmpty() || n.bigText != null || n.messages.size > 1 ||
        n.text.length > 60 || n.title.length > 32
    SwipeToDismissBox(
        state = state,
        modifier = modifier,
        enableDismissFromStartToEnd = n.isClearable,
        enableDismissFromEndToStart = n.isClearable,
        backgroundContent = {
            // Only while a swipe is under way: the glass card is see-through, so a background that
            // is always there shows "Dismiss" through every card at rest.
            if (state.dismissDirection != SwipeToDismissBoxValue.Settled) {
                Box(Modifier.fillMaxSize().clip(RoundedCornerShape(20.dp)).background(MikuPink.copy(alpha = 0.25f)), contentAlignment = Alignment.Center) {
                    Text("Dismiss", color = MikuPinkBright, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .graphicsLayer {
                    // the row fades as it follows the finger out (Pixel swipe-dismiss)
                    val p = runCatching { state.progress }.getOrDefault(0f)
                    alpha = if (state.targetValue == SwipeToDismissBoxValue.Settled) 1f else 1f - 0.7f * p.coerceIn(0f, 1f)
                }
                .animateContentSize(MikuMotion.settle())
                .mikuGlass(
                    RoundedCornerShape(20.dp),
                    if (n.isOngoing) NotifGlassQuiet else NotifGlass,
                    accent = accent
                )
                .clickable { MikuHaptics.confirm(view); if (n.contentIntent != null) onOpen() else expanded = !expanded }
                .padding(start = 12.dp, end = 4.dp, top = 8.dp, bottom = 8.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (appIconBmp != null) Image(appIconBmp, null, modifier = Modifier.size(16.dp).clip(RoundedCornerShape(4.dp)))
                else Box(Modifier.size(16.dp).clip(CircleShape).background(accent.copy(alpha = 0.6f)))
                Spacer(Modifier.width(6.dp))
                Text(n.appLabel, color = accent, fontSize = 11.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                Text("  ·  $timeLabel", color = MikuMuted, fontSize = 11.sp, maxLines = 1)
                if (n.isOngoing) Text("  ·  ongoing", color = MikuMuted, fontSize = 11.sp, maxLines = 1)
                Spacer(Modifier.weight(1f))
                if (canExpand) {
                    Box(
                        Modifier.size(40.dp).clip(CircleShape).clickable { expanded = !expanded },
                        contentAlignment = Alignment.Center
                    ) { Icon(if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore, if (expanded) "Collapse" else "Expand", tint = MikuTextSecondary, modifier = Modifier.size(20.dp)) }
                } else Spacer(Modifier.size(width = 8.dp, height = 40.dp))
            }
            Row(Modifier.padding(end = 8.dp), verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f)) {
                    Text(n.title, color = MikuWhite, fontSize = 13.sp, fontWeight = FontWeight.Bold, maxLines = if (expanded) 3 else 1, overflow = TextOverflow.Ellipsis)
                    if (expanded && n.messages.size > 1) {
                        // Chat history, the way a messaging notification expands on a phone.
                        n.messages.forEach { m ->
                            Text((m.sender?.let { "$it: " } ?: "") + m.text, color = MikuTextSecondary, fontSize = 12.sp, maxLines = 4, overflow = TextOverflow.Ellipsis)
                        }
                    } else {
                        val body = if (expanded) (n.bigText ?: n.text) else n.text
                        if (body.isNotBlank()) Text(body, color = MikuTextSecondary, fontSize = 12.sp, maxLines = if (expanded) 12 else 2, overflow = TextOverflow.Ellipsis)
                    }
                    n.subText?.takeIf { expanded && it.isNotBlank() }?.let { Text(it, color = MikuMuted, fontSize = 11.sp, maxLines = 1) }
                }
                n.largeIcon?.let { bmp ->
                    Spacer(Modifier.width(8.dp))
                    Image(bmp.asImageBitmap(), null, contentScale = ContentScale.Crop, modifier = Modifier.size(40.dp).clip(RoundedCornerShape(10.dp)))
                }
            }
            n.progressMax?.let { max ->
                Spacer(Modifier.height(6.dp))
                Box(Modifier.fillMaxWidth().padding(end = 8.dp).height(3.dp).clip(RoundedCornerShape(2.dp)).background(MikuSurface2)) {
                    Box(Modifier.fillMaxWidth(((n.progress ?: 0).toFloat() / max).coerceIn(0f, 1f)).fillMaxHeight().background(accent))
                }
            }
            AnimatedVisibility(visible = expanded && n.actions.isNotEmpty(), enter = expandVertically() + fadeIn(), exit = shrinkVertically() + fadeOut()) {
                Row(Modifier.padding(top = 6.dp, end = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    n.actions.take(3).forEach { a ->
                        val label = a.title.ifBlank { if (a.isReply) "Reply" else "Open" }.uppercase()
                        GlassChipButton(label, accent = accent, filled = a.isReply) {
                            if (a.isReply) onReply()
                            else if (MikuNotificationStore.send(ctx, a.intent) && n.autoCancel && n.isClearable) MikuNotificationStore.dismiss(n.key)
                        }
                    }
                }
            }
        }
    }
}


/** Lit glass play/pause: the art's accent as the glass colour, press physics like the tiles. */
@Composable
private fun PlayPauseButton(isPlaying: Boolean, accent: Color, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val press = rememberMikuPress(interaction)
    Box(
        Modifier
            .size(44.dp)
            .mikuPressScale(press, depth = 0.1f)
            .mikuGlass(CircleShape, MikuGlass.Chip, accent = accent, active = { 1f }, pressed = press)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick),
        contentAlignment = Alignment.Center
    ) { Icon(if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow, if (isPlaying) "Pause" else "Play", tint = MikuDarkBg, modifier = Modifier.size(24.dp)) }
}

/** Static hearts clock for audio_only / idle power profiles — no infinite plasma transitions. */
@Composable
private fun QuietClock(time: String, date: String) {
    val parts = time.split(":")
    Column {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(parts.getOrNull(0) ?: time, color = MikuTextPrimary, fontSize = 36.sp, fontWeight = FontWeight.Black, fontFamily = AudiowideFont, letterSpacing = 1.sp)
            KawaiiHeartColon(color = MikuPinkBright, scale = 1f)
            Text(parts.getOrNull(1) ?: "", color = MikuTextPrimary, fontSize = 36.sp, fontWeight = FontWeight.Black, fontFamily = AudiowideFont, letterSpacing = 1.sp)
        }
        Text(date, color = MikuTextSecondary, fontSize = 13.sp, fontWeight = FontWeight.Bold, fontFamily = AudiowideFont)
    }
}
