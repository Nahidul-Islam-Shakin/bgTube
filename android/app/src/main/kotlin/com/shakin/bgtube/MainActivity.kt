package com.shakin.bgtube

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "bgtube/player"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestNotificationPermissionIfNeeded()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        // Notification / lock-screen / headset buttons -> Flutter -> JS in the page.
        PlayerBridge.listener = { command ->
            runOnUiThread { channel.invokeMethod("onMediaAction", command) }
        }

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    val title = call.argument<String>("title") ?: "YouTube"
                    val artist = call.argument<String>("artist") ?: ""
                    val playing = call.argument<Boolean>("playing") ?: false
                    val service = PlaybackService.instance
                    if (service != null) {
                        service.updateState(title, artist, playing)
                        result.success(null)
                    } else if (playing) {
                        try {
                            PlaybackService.start(this, title, artist, playing)
                            result.success(null)
                        } catch (e: Exception) {
                            // e.g. start from background not allowed
                            result.error("SERVICE_START_FAILED", e.message, null)
                        }
                    } else {
                        result.success(null)
                    }
                }

                "stop" -> {
                    PlaybackService.instance?.shutdown()
                    result.success(null)
                }

                "moveToBack" -> {
                    moveTaskToBack(true)
                    result.success(null)
                }

                "isBatteryExempt" -> {
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    val exempt = Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
                        pm.isIgnoringBatteryOptimizations(packageName)
                    result.success(exempt)
                }

                "requestBatteryExemption" -> {
                    try {
                        startActivity(
                            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                                .setData(Uri.parse("package:$packageName"))
                        )
                    } catch (e: Exception) {
                        startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    }
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        PlayerBridge.listener = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 100
            )
        }
    }
}
