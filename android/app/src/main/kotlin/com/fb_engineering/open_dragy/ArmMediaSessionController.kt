package com.fb_engineering.open_dragy

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.view.KeyEvent
import androidx.media.session.MediaButtonReceiver

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
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null

    fun start() {
        if (session != null) return
        audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        requestAudioFocus()
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
        val mediaButtonIntent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            setClass(context, MediaButtonReceiver::class.java)
        }
        val mediaButtonPi = PendingIntent.getBroadcast(
            context,
            0,
            mediaButtonIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        s.setMediaButtonReceiver(mediaButtonPi)
        session = s
        s.isActive = true
        publishState()
    }

    fun stop() {
        abandonAudioFocus()
        session?.isActive = false
        session?.release()
        session = null
    }

    private fun requestAudioFocus() {
        val am = audioManager ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
                // Delayed focus requires a listener or AudioFocusRequest.Builder throws.
                val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(attrs)
                    .setOnAudioFocusChangeListener { /* media buttons only; ignore ducks */ }
                    .setAcceptsDelayedFocusGain(true)
                    .build()
                audioFocusRequest = req
                am.requestAudioFocus(req)
            } else {
                @Suppress("DEPRECATION")
                am.requestAudioFocus(
                    { /* unused */ },
                    AudioManager.STREAM_MUSIC,
                    AudioManager.AUDIOFOCUS_GAIN,
                )
            }
        } catch (_: Exception) {
            // Never crash app startup if audio focus is denied/misconfigured.
        }
    }

    private fun abandonAudioFocus() {
        val am = audioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { am.abandonAudioFocusRequest(it) }
            audioFocusRequest = null
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(null)
        }
    }

    fun publishState() {
        val s = session ?: return
        val state = when {
            CarStateStore.running -> PlaybackStateCompat.STATE_PLAYING
            CarStateStore.armed -> PlaybackStateCompat.STATE_PLAYING
            CarStateStore.enabled -> PlaybackStateCompat.STATE_PAUSED
            else -> PlaybackStateCompat.STATE_STOPPED
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
