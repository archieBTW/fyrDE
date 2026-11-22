package com.fyrde.fyrandroid.model

import android.content.BroadcastReceiver
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Low-memory, CPU-friendly repository for installed apps, dock pins, and squircle icon bitmaps.
 *
 * - Uses a single background worker thread for PackageManager queries and icon rasterization.
 * - Caches pre-clipped squircle Bitmaps in a strict memory-bounded [LruCache].
 * - Responds to system [onTrimMemory] signals to shed cached bitmaps immediately under pressure.
 */
class AppRepository(private val context: Context) {
    private val prefs = context.getSharedPreferences("fyr_apps_prefs", Context.MODE_PRIVATE)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor { r ->
        Thread(r, "fyr-app-loader").apply { priority = Thread.NORM_PRIORITY - 1 }
    }

    private val iconSizePx: Int =
        (56f * context.resources.displayMetrics.density).toInt().coerceIn(72, 168)

    private val iconCache: LruCache<String, Bitmap> = object : LruCache<String, Bitmap>(
        ((Runtime.getRuntime().maxMemory() / 1024L) / 16L).toInt().coerceIn(2048, 12288)
    ) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount / 1024
    }

    @Volatile
    var allApps: List<AppEntry> = emptyList()
        private set

    @Volatile
    var dockApps: List<AppEntry> = emptyList()
        private set

    private var onAppsUpdated: ((List<AppEntry>, List<AppEntry>) -> Unit)? = null
    private var receiverRegistered = false

    private val packageReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            reloadAppsAsync()
        }
    }

    fun start(listener: (List<AppEntry>, List<AppEntry>) -> Unit) {
        onAppsUpdated = listener
        if (!receiverRegistered) {
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_PACKAGE_ADDED)
                addAction(Intent.ACTION_PACKAGE_REMOVED)
                addAction(Intent.ACTION_PACKAGE_CHANGED)
                addDataScheme("package")
            }
            context.registerReceiver(packageReceiver, filter)
            receiverRegistered = true
        }
        reloadAppsAsync()
    }

    fun stop() {
        onAppsUpdated = null
        if (receiverRegistered) {
            try {
                context.unregisterReceiver(packageReceiver)
            } catch (_: Exception) {
            }
            receiverRegistered = false
        }
    }

    fun reloadAppsAsync() {
        worker.execute {
            val pm = context.packageManager
            val queryIntent = Intent(Intent.ACTION_MAIN, null).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
            }
            val resolveInfos = pm.queryIntentActivities(queryIntent, 0)
            val selfPkg = context.packageName
            val entries = ArrayList<AppEntry>(resolveInfos.size)

            for (ri in resolveInfos) {
                val ai = ri.activityInfo ?: continue
                if (ai.packageName == selfPkg) continue
                val label = ri.loadLabel(pm)?.toString()?.trim().takeUnless { it.isNullOrEmpty() }
                    ?: ai.packageName
                val isSys = (ai.applicationInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
                val key = "${ai.packageName}/${ai.name}"
                val count = prefs.getInt("launches_$key", 0)
                entries.add(
                    AppEntry(
                        label = label,
                        packageName = ai.packageName,
                        activityName = ai.name,
                        isSystemApp = isSys,
                        launchCount = count
                    )
                )
            }

            entries.sortWith(compareBy { it.label.lowercase(Locale.getDefault()) })
            allApps = entries
            dockApps = resolveDockApps(entries)

            mainHandler.post {
                onAppsUpdated?.invoke(allApps, dockApps)
            }
        }
    }

    private fun resolveDockApps(apps: List<AppEntry>): List<AppEntry> {
        if (apps.isEmpty()) return emptyList()
        val savedRaw = prefs.getString("dock_pins", null)
        if (!savedRaw.isNullOrBlank()) {
            val byKey = apps.associateBy { it.componentKey }
            val pinned = savedRaw.split("|").mapNotNull { byKey[it] }
            if (pinned.isNotEmpty()) return pinned.take(4)
        }

        // Default bottom dock: Phone, Messages, Browser, Settings/Camera
        val keywords = listOf(
            listOf("phone", "dialer", "call"),
            listOf("messages", "messaging", "sms", "chat"),
            listOf("browser", "chrome", "firefox", "brave", "web"),
            listOf("camera", "photos", "settings")
        )
        val chosen = mutableListOf<AppEntry>()
        for (group in keywords) {
            val match = apps.firstOrNull { app ->
                app !in chosen && group.any { kw ->
                    app.label.lowercase(Locale.getDefault()).contains(kw) ||
                        app.packageName.lowercase(Locale.getDefault()).contains(kw)
                }
            }
            if (match != null) chosen.add(match)
        }
        for (fallback in apps) {
            if (chosen.size >= 4) break
            if (fallback !in chosen) chosen.add(fallback)
        }
        return chosen.take(4)
    }

    fun isPinnedToDock(app: AppEntry): Boolean =
        dockApps.any { it.componentKey == app.componentKey }

    fun toggleDockPin(app: AppEntry): Boolean {
        val current = dockApps.map { it.componentKey }.toMutableList()
        val added: Boolean
        if (current.contains(app.componentKey)) {
            current.remove(app.componentKey)
            added = false
        } else {
            if (current.size >= 4) current.removeAt(current.lastIndex)
            current.add(app.componentKey)
            added = true
        }
        prefs.edit().putString("dock_pins", current.joinToString("|")).apply()
        dockApps = resolveDockApps(allApps)
        onAppsUpdated?.invoke(allApps, dockApps)
        return added
    }

    fun recordLaunch(app: AppEntry) {
        val key = "launches_${app.componentKey}"
        val next = prefs.getInt(key, 0) + 1
        prefs.edit().putInt(key, next).apply()
    }

    fun getCachedIcon(app: AppEntry): Bitmap? = iconCache.get(app.componentKey)

    fun loadIconAsync(app: AppEntry, onLoaded: (Bitmap) -> Unit) {
        val cached = iconCache.get(app.componentKey)
        if (cached != null) {
            onLoaded(cached)
            return
        }
        worker.execute {
            val again = iconCache.get(app.componentKey)
            if (again != null) {
                mainHandler.post { onLoaded(again) }
                return@execute
            }
            val bmp = rasterizeSquircleIcon(app)
            if (bmp != null) {
                iconCache.put(app.componentKey, bmp)
                mainHandler.post { onLoaded(bmp) }
            }
        }
    }

    private fun rasterizeSquircleIcon(app: AppEntry): Bitmap? {
        return try {
            val pm = context.packageManager
            val drawable: Drawable = pm.getActivityIcon(
                android.content.ComponentName(app.packageName, app.activityName)
            )
            val size = iconSizePx
            val raw = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val rawCanvas = Canvas(raw)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(rawCanvas)

            val output = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(output)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            val radius = size * 0.225f
            val rect = RectF(0f, 0f, size.toFloat(), size.toFloat())
            val clipPath = Path().apply {
                addRoundRect(rect, radius, radius, Path.Direction.CW)
            }
            canvas.drawPath(clipPath, paint)
            paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
            canvas.drawBitmap(raw, 0f, 0f, paint)
            raw.recycle()
            output
        } catch (_: Exception) {
            null
        }
    }

    fun trimMemory(level: Int) {
        when {
            level >= ComponentCallbacks2.TRIM_MEMORY_MODERATE ||
                level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL -> {
                iconCache.evictAll()
            }
            level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW -> {
                iconCache.trimToSize(iconCache.maxSize() / 2)
            }
        }
    }
}
