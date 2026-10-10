package com.caf.fmradio

import android.media.browse.MediaBrowser
import android.os.Bundle
import android.service.media.MediaBrowserService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/**
 * What Android Auto binds to. It lists the radio's stations and hands over the token of
 * [FmMediaSession]. It does not touch the tuner itself.
 *
 * Tree:
 *   Now playing      the station the tuner is on
 *   Presets          the user's starred frequencies
 *   Nearby stations  the catalogue's stations for where the device is
 */
class FmMediaBrowserService : MediaBrowserService() {

    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    override fun onCreate() {
        super.onCreate()
        sessionToken = FmMediaSession.attachBrowser(this).sessionToken

        // Tell connected browsers when a list they may be showing has changed.
        scope.launch {
            FmRadioManager.state
                .map { st -> Triple(st.frequencyKHz, st.stationName, st.tunedStation?.call) }
                .distinctUntilChanged().drop(1)
                .collect { notifyChildrenChanged(FmMediaSession.NOW) }
        }
        scope.launch {
            FmRadioManager.state
                .map { st -> st.nearbyStations.map { Triple(it.call, it.khz, it.genre ?: it.format) } }
                .distinctUntilChanged().drop(1)
                .collect {
                    notifyChildrenChanged(FmMediaSession.NEARBY)
                    notifyChildrenChanged(FmMediaSession.PRESETS)
                }
        }
        scope.launch {
            FmRadioManager.state
                .map { st -> Triple(st.favorites, st.frequencyKHz, st.stationName) }
                .distinctUntilChanged().drop(1)
                .collect { notifyChildrenChanged(FmMediaSession.PRESETS) }
        }
    }

    override fun onDestroy() {
        scope.cancel()
        FmMediaSession.detachBrowser()
        super.onDestroy()
    }

    override fun onGetRoot(clientPackageName: String, clientUid: Int, rootHints: Bundle?): MediaBrowserService.BrowserRoot? {
        // The "recent" root is for resuming playback after a reboot. The radio has nothing to
        // resume from a cold start that the tuner screen does not already do, so decline it.
        if (rootHints?.getBoolean(MediaBrowserService.BrowserRoot.EXTRA_RECENT) == true) return null
        return MediaBrowserService.BrowserRoot(FmMediaSession.ROOT, FmMediaSession.rootExtras())
    }

    override fun onLoadChildren(parentId: String, result: MediaBrowserService.Result<MutableList<MediaBrowser.MediaItem>>) {
        result.sendResult(FmMediaSession.children(parentId))
    }
}
