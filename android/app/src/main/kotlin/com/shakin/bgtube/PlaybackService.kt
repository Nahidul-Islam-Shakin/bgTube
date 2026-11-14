package com.shakin.bgtube

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.media.AudioManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.media.app.NotificationCompat.MediaStyle

/**
 * Foreground service (type mediaPlayback) that:
 *  - keeps the app process alive while the screen is off,
 *  - holds a partial wake lock + wifi lock while playing,
 *  - exposes a MediaSession (notification, lock screen, Bluetooth/wired headset buttons),
 *  - pauses when headphones are unplugged / Bluetooth disconnects.
 *
 * The audio itself is played by the WebView inside the Activity.
 */
class PlaybackService : Service() {

    companion object {
        private const val CHANNEL_ID = "bgtube_playback"
        private const val NOTIFICATION_ID = 1001

        private const val ACTION_UPDATE = "com.shakin.bgtube.action.UPDATE"
        private const val ACTION_PLAY = "com.shakin.bgtube.action.PLAY"
        private const val ACTION_PAUSE = "com.shakin.bgtube.action.PAUSE"
        private const val ACTION_NEXT = "com.shakin.bgtube.action.NEXT"
        private const val ACTION_PREVIOUS = "com.shakin.bgtube.action.PREVIOUS"
        private const val ACTION_STOP = "com.shakin.bgtube.action.STOP"

        private const val EXTRA_TITLE = "title"
        private const val EXTRA_ARTIST = "artist"
        private const val EXTRA_PLAYING = "playing"

        /** Release wake/wifi locks this long after pausing (covers track changes). */
        private const val LOCK_RELEASE_DELAY_MS = 90_000L

        /** End the service (and its notification) after this long without playback. */
        private const val IDLE_STOP_DELAY_MS = 10 * 60_000L

        @Volatile
        var instance: PlaybackService? = null
            private set

        fun start(context: Context, title: String, artist: String, playing: Boolean) {
            val intent = Intent(context, PlaybackService::class.java)
                .setAction(ACTION_UPDATE)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_ARTIST, artist)
                .putExtra(EXTRA_PLAYING, playing)
            ContextCompat.startForegroundService(context, intent)
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var session: MediaSessionCompat? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    private var title = "YouTube"
    private var artist = ""
    private var playing = false

    private val releaseLocksRunnable = Runnable { releaseLocks() }
    private val idleStopRunnable = Runnable { shutdown() }

    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                deliver("pause")
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannel()

        session = MediaSessionCompat(this, "BgTubeSession").apply {
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() = deliver("play")
                override fun onPause() = deliver("pause")
                override fun onSkipToNext() = deliver("next")
                override fun onSkipToPrevious() = deliver("previous")
                override fun onStop() = deliver("stop")
            })
            isActive = true
        }

        ContextCompat.registerReceiver(
            this,
            noisyReceiver,
            IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY),
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (val action = intent?.action) {
            ACTION_UPDATE -> {
                title = intent.getStringExtra(EXTRA_TITLE) ?: title
                artist = intent.getStringExtra(EXTRA_ARTIST) ?: ""
                playing = intent.getBooleanExtra(EXTRA_PLAYING, false)
            }

            ACTION_STOP -> {
                PlayerBridge.send("stop")
                shutdown()
                return START_NOT_STICKY
            }

            ACTION_PLAY, ACTION_PAUSE, ACTION_NEXT, ACTION_PREVIOUS -> {
                if (!PlayerBridge.send(commandFor(action))) {
                    shutdown()
                    return START_NOT_STICKY
                }
            }
        }
        // Always (re)enter the foreground quickly after startForegroundService().
        publishState()
        return START_NOT_STICKY
    }

    /** Called from MainActivity while the service is already running. */
    fun updateState(newTitle: String, newArtist: String, isPlaying: Boolean) {
        // Skip redundant notification/session rebuilds.
        if (newTitle == title && newArtist == artist && isPlaying == playing) return
        title = newTitle
        artist = newArtist
        playing = isPlaying
        publishState()
    }

    fun shutdown() {
        handler.removeCallbacksAndMessages(null)
        releaseLocks()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /** Swiping the app away from recents destroys the WebView, so end playback cleanly. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        shutdown()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(noisyReceiver)
        } catch (_: Exception) {
        }
        handler.removeCallbacksAndMessages(null)
        releaseLocks()
        session?.isActive = false
        session?.release()
        session = null
        instance = null
        super.onDestroy()
    }

    // ---- internals ---------------------------------------------------------

    private fun deliver(command: String) {
        if (!PlayerBridge.send(command)) shutdown()
    }

    private fun commandFor(action: String?): String = when (action) {
        ACTION_PLAY -> "play"
        ACTION_PAUSE -> "pause"
        ACTION_NEXT -> "next"
        ACTION_PREVIOUS -> "previous"
        else -> "stop"
    }

    private fun publishState() {
        session?.let { s ->
            s.setMetadata(
                MediaMetadataCompat.Builder()
                    .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
                    .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
                    .build()
            )
            val actions = PlaybackStateCompat.ACTION_PLAY or
                PlaybackStateCompat.ACTION_PAUSE or
                PlaybackStateCompat.ACTION_PLAY_PAUSE or
                PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                PlaybackStateCompat.ACTION_STOP
            s.setPlaybackState(
                PlaybackStateCompat.Builder()
                    .setActions(actions)
                    .setState(
                        if (playing) PlaybackStateCompat.STATE_PLAYING
                        else PlaybackStateCompat.STATE_PAUSED,
                        PlaybackStateCompat.PLAYBACK_POSITION_UNKNOWN,
                        if (playing) 1f else 0f
                    )
                    .build()
            )
        }

        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            buildNotification(),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
        )

        handler.removeCallbacks(releaseLocksRunnable)
        handler.removeCallbacks(idleStopRunnable)
        if (playing) {
            acquireLocks()
        } else {
            handler.postDelayed(releaseLocksRunnable, LOCK_RELEASE_DELAY_MS)
            handler.postDelayed(idleStopRunnable, IDLE_STOP_DELAY_MS)
        }
    }

    private fun buildNotification(): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        val contentIntent = PendingIntent.getActivity(
            this, 0, launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val previous = action(android.R.drawable.ic_media_previous, "Previous", ACTION_PREVIOUS)
        val playPause = if (playing) {
            action(android.R.drawable.ic_media_pause, "Pause", ACTION_PAUSE)
        } else {
            action(android.R.drawable.ic_media_play, "Play", ACTION_PLAY)
        }
        val next = action(android.R.drawable.ic_media_next, "Next", ACTION_NEXT)
        val stop = action(android.R.drawable.ic_menu_close_clear_cancel, "Stop", ACTION_STOP)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText(artist.ifEmpty { "YouTube" })
            .setContentIntent(contentIntent)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setShowWhen(false)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .addAction(previous)
            .addAction(playPause)
            .addAction(next)
            .addAction(stop)
            .setStyle(
                MediaStyle()
                    .setMediaSession(session?.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2)
            )
            .build()
    }

    private fun action(icon: Int, label: String, action: String): NotificationCompat.Action {
        val pi = PendingIntent.getService(
            this,
            action.hashCode(),
            Intent(this, PlaybackService::class.java).setAction(action),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Action.Builder(icon, label, pi).build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Playback", NotificationManager.IMPORTANCE_LOW
            ).apply {
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    @SuppressLint("WakelockTimeout")
    @Suppress("DEPRECATION")
    private fun acquireLocks() {
        if (wakeLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "bgtube:playback")
                .apply { setReferenceCounted(false) }
        }
        if (wakeLock?.isHeld == false) wakeLock?.acquire()

        if (wifiLock == null) {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "bgtube:wifi")
                .apply { setReferenceCounted(false) }
        }
        if (wifiLock?.isHeld == false) wifiLock?.acquire()
    }

    private fun releaseLocks() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wifiLock?.let { if (it.isHeld) it.release() }
    }
}