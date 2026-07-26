package com.fb_engineering.open_dragy

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.view.KeyEvent

/**
 * Active MediaSession so Cardo / AA media Next/Previous reach OpenDragy
 * instead of Spotify while headset ARM is enabled.
 */
class ArmMediaSessionController(
    private val context: Context,
    private val onNext: () -> Unit,
    private val onPrevious: () -> Unit,
) {
    private var session: MediaSessionCompat? = null

    fun start() {
        if (session != null) return
        val s = MediaSessionCompat(context, "OpenDragyArm")
        s.setFlags(
            MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS,
        )
        s.setCallback(object : MediaSessionCompat.Callback() {
            override fun onMediaButtonEvent(mediaButtonEvent: Intent?): Boolean {
                @Suppress("DEPRECATION")
                val key = mediaButtonEvent?.getParcelableExtra(Intent.EXTRA_KEY_EVENT) as KeyEvent?
                    ?: return super.onMediaButtonEvent(mediaButtonEvent)
                if (key.action != KeyEvent.ACTION_DOWN) {
                    return true
                }
                when (key.keyCode) {
                    KeyEvent.KEYCODE_MEDIA_NEXT,
                    KeyEvent.KEYCODE_MEDIA_FAST_FORWARD,
                    -> {
                        onNext()
                        return true
                    }
                    KeyEvent.KEYCODE_MEDIA_PREVIOUS,
                    KeyEvent.KEYCODE_MEDIA_REWIND,
                    -> {
                        onPrevious()
                        return true
                    }
                    KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
                    KeyEvent.KEYCODE_HEADSETHOOK,
                    -> {
                        onNext()
                        return true
                    }
                }
                return super.onMediaButtonEvent(mediaButtonEvent)
            }

            override fun onSkipToNext() {
                onNext()
            }

            override fun onSkipToPrevious() {
                onPrevious()
            }

            override fun onPlay() {
                // Treat play as ARM toggle when media controls only expose play.
                onNext()
            }

            override fun onPause() {
                onPrevious()
            }

            override fun onCustomAction(action: String?, extras: Bundle?) {
                when (action) {
                    ACTION_ARM -> onNext()
                    ACTION_DISARM -> onPrevious()
                }
            }
        })
        session = s
        s.isActive = true
        publishState()
    }

    fun stop() {
        session?.isActive = false
        session?.release()
        session = null
    }

    fun publishState() {
        val s = session ?: return
        val state = when {
            CarStateStore.running -> PlaybackStateCompat.STATE_PLAYING
            CarStateStore.armed -> PlaybackStateCompat.STATE_BUFFERING
            else -> PlaybackStateCompat.STATE_PAUSED
        }
        val actions = (
            PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                PlaybackStateCompat.ACTION_PLAY or
                PlaybackStateCompat.ACTION_PAUSE or
                PlaybackStateCompat.ACTION_PLAY_PAUSE
            )
        s.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(actions)
                .setState(state, PlaybackStateCompat.PLAYBACK_POSITION_UNKNOWN, 1.0f)
                .addCustomAction(ACTION_ARM, "ARM", android.R.drawable.ic_media_play)
                .addCustomAction(ACTION_DISARM, "DISARM", android.R.drawable.ic_media_pause)
                .build(),
        )
        s.setMetadata(
            MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, CarStateStore.titleLine())
                .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, CarStateStore.subtitleLine())
                .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, CarStateStore.targetLabel)
                .build(),
        )
    }

    companion object {
        const val ACTION_ARM = "opendragy.ARM"
        const val ACTION_DISARM = "opendragy.DISARM"
    }
}
