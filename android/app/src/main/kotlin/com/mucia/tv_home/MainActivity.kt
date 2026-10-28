package com.mucia.tv_home

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.ComponentName
import android.content.ContentUris
import android.content.Intent
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.Drawable
import android.media.AudioManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.MediaStore
import android.provider.Settings
import android.util.DisplayMetrics
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val executor = Executors.newSingleThreadExecutor()
    private var channel: MethodChannel? = null
    private var stopped = true

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tv_home/apps").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "list" -> background(result) { listApps() }
                    "top" -> background(result) { topApps() }
                    "images" -> background(result) { deviceImages() }
                    "image" -> background(result) {
                        readImage(Uri.parse(call.argument<String>("uri")!!), call.argument<Int>("size")!!)
                    }
                    "launch" -> result.success(launch(call.argument<String>("package")!!))
                    "settings" -> result.success(openSetting(call.argument<String>("page") ?: "all"))
                    "status" -> result.success(status())
                    "volume" -> result.success(volume(call.argument<Int>("delta") ?: 0))
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onStart() {
        super.onStart()
        stopped = false
    }

    override fun onStop() {
        super.onStop()
        stopped = true
    }

    // Home pressed. inFront tells Flutter whether the launcher was already showing
    // (open Controls) or the user is coming back from another app.
    override fun onNewIntent(intent: Intent) {
        // Translucent screens (like Play Store's update dialog) don't stop this activity,
        // but they do take window focus.
        val inFront = !stopped && hasWindowFocus()
        super.onNewIntent(intent)
        channel?.invokeMethod("home", inFront)
    }

    private fun openSetting(page: String): Boolean {
        val tv = "com.android.tv.settings"
        val intent = when (page) {
            "wifi" -> Intent(Settings.ACTION_WIFI_SETTINGS)
            // TV Settings doesn't export its Remotes & Accessories screen, so offer to turn
            // Bluetooth on, or else open Settings where it's listed.
            "bluetooth" ->
                if (getSystemService(BluetoothManager::class.java)?.adapter?.isEnabled == false) {
                    Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
                } else {
                    Intent(Settings.ACTION_SETTINGS)
                }
            "display" -> Intent(Settings.ACTION_DISPLAY_SETTINGS)
            "sound" -> Intent(Settings.ACTION_SOUND_SETTINGS)
            "apps" -> Intent().setComponent(ComponentName(tv, "$tv.device.apps.AppsActivity"))
            "accessibility" -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            "date" -> Intent(Settings.ACTION_DATE_SETTINGS)
            "keyboard" -> Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)
            "energy" -> Intent().setComponent(ComponentName(tv, "$tv.device.eco.EnergyModesActivity"))
            else -> Intent(Settings.ACTION_SETTINGS)
        }.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            startActivity(intent)
            true
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            false
        }
    }

    private fun status(): Map<String, Any?> {
        val cm = getSystemService(ConnectivityManager::class.java)
        val caps = cm.getNetworkCapabilities(cm.activeNetwork)
        val network = when {
            caps == null -> "none"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            else -> "other"
        }
        val audio = getSystemService(AudioManager::class.java)
        return mapOf(
            "network" to network,
            "online" to (caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true),
            "wifiEnabled" to getSystemService(WifiManager::class.java).isWifiEnabled,
            "bluetooth" to (getSystemService(BluetoothManager::class.java)?.adapter?.isEnabled == true),
            "volume" to audio.getStreamVolume(AudioManager.STREAM_MUSIC),
            "maxVolume" to audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
            "muted" to audio.isStreamMute(AudioManager.STREAM_MUSIC),
        )
    }

    // Steps media volume by delta and returns the new level.
    private fun volume(delta: Int): Int {
        val audio = getSystemService(AudioManager::class.java)
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val level = (audio.getStreamVolume(AudioManager.STREAM_MUSIC) + delta).coerceIn(0, max)
        audio.setStreamVolume(AudioManager.STREAM_MUSIC, level, 0)
        return level
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        executor.execute {
            val value = try {
                work()
            } catch (e: Exception) {
                null
            }
            runOnUiThread { result.success(value) }
        }
    }

    private fun listApps(): List<Map<String, Any?>> {
        val pm = packageManager
        val seen = LinkedHashMap<String, Map<String, Any?>>()
        for (category in listOf(Intent.CATEGORY_LEANBACK_LAUNCHER, Intent.CATEGORY_LAUNCHER)) {
            val intent = Intent(Intent.ACTION_MAIN).addCategory(category)
            for (info in pm.queryIntentActivities(intent, 0)) {
                val ai = info.activityInfo
                if (ai.packageName == packageName || seen.containsKey(ai.packageName)) continue
                seen[ai.packageName] = mapOf(
                    "package" to ai.packageName,
                    "label" to info.loadLabel(pm).toString(),
                    "icon" to toPng(highResIcon(info), 192),
                )
            }
        }
        return seen.values.sortedBy { (it["label"] as String).lowercase() }
    }

    // Packages ordered by foreground time over the last 30 days, most used first.
    // Returns null when usage access hasn't been granted.
    private fun topApps(): List<String>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val ops = getSystemService(AppOpsManager::class.java)
        val mode = ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        if (mode != AppOpsManager.MODE_ALLOWED) return null

        val homes = packageManager
            .queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME), 0)
            .map { it.activityInfo.packageName }
            .toSet()
        val usm = getSystemService(UsageStatsManager::class.java)
        val end = System.currentTimeMillis()
        return usm.queryAndAggregateUsageStats(end - 30L * 24 * 60 * 60 * 1000, end).values
            .filter { it.packageName !in homes && it.totalTimeInForeground > 0 }
            .sortedByDescending { it.totalTimeInForeground }
            .map { it.packageName }
    }

    private fun deviceImages(): List<String> {
        val uris = mutableListOf<String>()
        val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        contentResolver.query(
            collection, arrayOf(MediaStore.Images.Media._ID), null, null,
            "${MediaStore.Images.Media.DATE_ADDED} DESC",
        )?.use { cursor ->
            while (cursor.moveToNext() && uris.size < 40) {
                uris += ContentUris.withAppendedId(collection, cursor.getLong(0)).toString()
            }
        }
        return uris
    }

    private fun readImage(uri: Uri, size: Int): ByteArray? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= size) sample *= 2
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        val bitmap = contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) }
            ?: return null
        return ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
            out.toByteArray()
        }
    }

    private fun launch(pkg: String): Boolean {
        val pm = packageManager
        val intent = pm.getLeanbackLaunchIntentForPackage(pkg) ?: pm.getLaunchIntentForPackage(pkg)
            ?: return false
        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        return true
    }

    // TV densities are low, so ask for the xxxhdpi icon to keep it sharp at large sizes.
    private fun highResIcon(info: ResolveInfo): Drawable {
        val ai = info.activityInfo
        val res = ai.iconResource.takeIf { it != 0 } ?: ai.applicationInfo.icon
        if (res != 0) {
            try {
                packageManager.getResourcesForApplication(ai.applicationInfo)
                    .getDrawableForDensity(res, DisplayMetrics.DENSITY_XXXHIGH, null)
                    ?.let { return it }
            } catch (e: Exception) {
            }
        }
        return info.loadIcon(packageManager)
    }

    private fun toPng(d: Drawable, size: Int): ByteArray {
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && d is AdaptiveIconDrawable) {
            // Draw the layers unmasked so the icon fills the square; Flutter rounds the corners.
            // Adaptive layers are 108dp with a 72dp visible area, hence the quarter-size bleed.
            val bleed = size / 4
            for (layer in listOf(d.background, d.foreground)) {
                layer?.setBounds(-bleed, -bleed, size + bleed, size + bleed)
                layer?.draw(canvas)
            }
        } else {
            d.setBounds(0, 0, size, size)
            d.draw(canvas)
        }
        return ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            out.toByteArray()
        }
    }
}
