package com.fyrde.fyrandroid.ui

import android.annotation.SuppressLint
import android.app.NotificationManager
import android.bluetooth.BluetoothAdapter
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import com.fyrde.fyrandroid.theme.FyrThemeManager
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Fyr Quick Settings panel modeled directly on `fyrtaskbar/lib/ui/quick_settings.dart`:
 * - Clean translucent glass panel (no title header, no Settings button)
 * - 2x4 grid of 58dp circular icon-only `QuickToggle` buttons
 *   (Wi-Fi, Bluetooth, Airplane, Flashlight / Auto-Rotate, DND, Dark Mode, Hotspot)
 * - Compact frosted `QuickSettingsMediaCard` shown when audio playback is active
 * - Slim `FyrSliderBar` brightness and volume rows matching `slider_row.dart`
 */
@SuppressLint("ViewConstructor")
class FyrQuickSettingsSheet(
    context: Context,
    private val onThemeChanged: () -> Unit,
    private val onAdjustWindowBrightness: (Float) -> Unit,
    private val onVisibilityChanged: (Boolean) -> Unit = {}
) : FrameLayout(context) {

    private val density = resources.displayMetrics.density
    private fun dp(v: Float): Int = (v * density).toInt()

    private val cardSurface = LinearLayout(context)
    private val cardBg = GradientDrawable()
    private val mediaCard = LinearLayout(context)
    private val mediaCardBg = GradientDrawable()
    private val mediaArtBadgeBg = GradientDrawable()
    private val playCircleBg = GradientDrawable()

    private val togglesRow1 = LinearLayout(context)
    private val togglesRow2 = LinearLayout(context)
    private val mediaTitle = TextView(context)
    private val mediaSubtitle = TextView(context)
    private val mediaNoteIcon = FyrIconView(context, FyrIcon.MUSIC_NOTE, FyrThemeManager.accentColor)
    private val prevIcon = FyrIconView(context, FyrIcon.PREV, FyrThemeManager.textColor)
    private val playPauseIcon = FyrIconView(context, FyrIcon.PAUSE, Color.WHITE)
    private val nextIcon = FyrIconView(context, FyrIcon.NEXT, FyrThemeManager.textColor)

    private val brightnessIcon = FyrIconView(context, FyrIcon.SUN, FyrThemeManager.textColorMuted)
    private val volumeIcon = FyrIconView(context, FyrIcon.VOLUME, FyrThemeManager.textColorMuted)
    private val volumeChevron = FyrIconView(context, FyrIcon.CHEVRON_RIGHT, FyrThemeManager.textColor)
    private lateinit var brightnessSlider: FyrSliderBar
    private lateinit var volumeSlider: FyrSliderBar

    private val cameraManager =
        context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
    private val audioManager =
        context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
    private val notificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
    private val wifiManager =
        context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager

    private var torchCameraId: String? = null
    private var isTorchOn: Boolean = false

    var isOpen: Boolean = false
        private set

    private val torchCallback = object : CameraManager.TorchCallback() {
        override fun onTorchModeChanged(cameraId: String, enabled: Boolean) {
            if (cameraId == torchCameraId) {
                isTorchOn = enabled
                rebuildToggleRows()
            }
        }
    }

    init {
        visibility = View.GONE
        isClickable = true
        setBackgroundColor(0x52000000)
        setOnClickListener { close() }

        initTorchCamera()

        cardSurface.apply {
            orientation = LinearLayout.VERTICAL
            isClickable = true
            setPadding(dp(24f), dp(24f), dp(24f), dp(24f))
            background = cardBg
            elevation = dp(18f).toFloat()
        }

        // 2x4 Circular Icon-Only Quick Toggles (identical to `QuickToggle` in `fyrtaskbar`)
        togglesRow1.apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        togglesRow2.apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, dp(16f), 0, 0)
        }
        cardSurface.addView(togglesRow1)
        cardSurface.addView(togglesRow2)

        // Optional Media Controls Card (`QuickSettingsMediaCard` in `fyrtaskbar`)
        mediaCard.apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12f), dp(12f), dp(12f), dp(12f))
            background = mediaCardBg
            visibility = View.GONE
        }
        val artBox = FrameLayout(context).apply {
            background = mediaArtBadgeBg
        }
        artBox.addView(
            mediaNoteIcon,
            LayoutParams(dp(22f), dp(22f), Gravity.CENTER)
        )
        mediaCard.addView(artBox, LinearLayout.LayoutParams(dp(44f), dp(44f)))

        val mediaTextCol = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12f), 0, dp(8f), 0)
        }
        mediaTitle.apply {
            text = "Now Playing"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
            maxLines = 1
        }
        mediaSubtitle.apply {
            text = "Media Playback"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            maxLines = 1
        }
        mediaTextCol.addView(mediaTitle)
        mediaTextCol.addView(mediaSubtitle)
        mediaCard.addView(
            mediaTextCol,
            LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
        )

        val prevWrap = wrapIconButton(prevIcon, 32f, 18f) {
            dispatchMediaKey(KeyEvent.KEYCODE_MEDIA_PREVIOUS)
        }
        val playCircle = FrameLayout(context).apply {
            background = playCircleBg
            setOnClickListener { dispatchMediaKey(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE) }
        }
        playCircle.addView(playPauseIcon, LayoutParams(dp(18f), dp(18f), Gravity.CENTER))
        val nextWrap = wrapIconButton(nextIcon, 32f, 18f) {
            dispatchMediaKey(KeyEvent.KEYCODE_MEDIA_NEXT)
        }

        mediaCard.addView(prevWrap)
        mediaCard.addView(
            playCircle,
            LinearLayout.LayoutParams(dp(34f), dp(34f)).apply {
                leftMargin = dp(4f)
                rightMargin = dp(4f)
            }
        )
        mediaCard.addView(nextWrap)

        cardSurface.addView(
            mediaCard,
            LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                topMargin = dp(18f)
            }
        )

        // Brightness SliderRow (`SliderRow` in `fyrtaskbar`)
        brightnessSlider = FyrSliderBar(context) { fraction ->
            val clamped = (fraction * 255f).roundToInt().coerceIn(10, 255)
            onAdjustWindowBrightness(clamped / 255f)
            if (Settings.System.canWrite(context)) {
                try {
                    Settings.System.putInt(
                        context.contentResolver,
                        Settings.System.SCREEN_BRIGHTNESS,
                        clamped
                    )
                } catch (_: Exception) {
                }
            }
        }
        cardSurface.addView(
            createSliderRow(brightnessIcon, brightnessSlider, trailing = null),
            LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                topMargin = dp(20f)
            }
        )

        // Volume SliderRow with trailing chevron (`SliderRow` in `fyrtaskbar`)
        volumeSlider = FyrSliderBar(context) { fraction ->
            val maxVol = max(1, audioManager?.getStreamMaxVolume(AudioManager.STREAM_MUSIC) ?: 15)
            val target = (fraction * maxVol).roundToInt().coerceIn(0, maxVol)
            audioManager?.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
        }
        val chevronBtn = wrapIconButton(volumeChevron, 28f, 18f) {
            close()
            val panelIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                Intent(Settings.Panel.ACTION_VOLUME)
            } else {
                Intent(Settings.ACTION_SOUND_SETTINGS)
            }
            context.startActivity(panelIntent.apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK })
        }
        cardSurface.addView(
            createSliderRow(volumeIcon, volumeSlider, trailing = chevronBtn),
            LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                topMargin = dp(14f)
            }
        )

        val cardParams = LayoutParams(
            LayoutParams.MATCH_PARENT,
            LayoutParams.WRAP_CONTENT,
            Gravity.TOP
        ).apply {
            setMargins(dp(14f), dp(42f), dp(14f), dp(14f))
        }
        addView(cardSurface, cardParams)

        applyTheme()
    }

    private fun initTorchCamera() {
        try {
            val cm = cameraManager ?: return
            for (id in cm.cameraIdList) {
                val chars = cm.getCameraCharacteristics(id)
                if (chars.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true) {
                    torchCameraId = id
                    break
                }
            }
            cm.registerTorchCallback(torchCallback, null)
        } catch (_: Exception) {
        }
    }

    fun applyTheme() {
        cardBg.apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(20f).toFloat()
            setColor(FyrThemeManager.panelBgColor)
            setStroke(max(1, dp(1f)), FyrThemeManager.cardColor)
        }
        mediaCardBg.apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(14f).toFloat()
            setColor(FyrThemeManager.cardColor)
            setStroke(max(1, dp(1f)), FyrThemeManager.dividerColor)
        }
        mediaArtBadgeBg.apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(10f).toFloat()
            setColor(FyrThemeManager.accentWithAlpha(0.22f))
        }
        playCircleBg.apply {
            shape = GradientDrawable.OVAL
            setColor(FyrThemeManager.accentColor)
        }

        mediaTitle.setTextColor(FyrThemeManager.textColor)
        mediaSubtitle.setTextColor(FyrThemeManager.textColorMuted)
        mediaNoteIcon.setTint(FyrThemeManager.accentColor)
        prevIcon.setTint(FyrThemeManager.textColor)
        nextIcon.setTint(FyrThemeManager.textColor)

        brightnessIcon.setTint(FyrThemeManager.textColorMuted)
        volumeIcon.setTint(FyrThemeManager.textColorMuted)
        volumeChevron.setTint(FyrThemeManager.textColor)

        val activeTrack = FyrThemeManager.accentWithAlpha(0.50f)
        val inactiveTrack = FyrThemeManager.hoverColor
        brightnessSlider.activeTrackColor = activeTrack
        brightnessSlider.inactiveTrackColor = inactiveTrack
        brightnessSlider.thumbColor = FyrThemeManager.textColor
        volumeSlider.activeTrackColor = activeTrack
        volumeSlider.inactiveTrackColor = inactiveTrack
        volumeSlider.thumbColor = FyrThemeManager.textColor

        rebuildToggleRows()
    }

    fun open() {
        isOpen = true
        onVisibilityChanged(true)
        refreshSystemState()
        applyTheme()
        visibility = View.VISIBLE
        cardSurface.translationY = -dp(360f).toFloat()
        alpha = 0f
        animate().alpha(1f).setDuration(150L).start()
        cardSurface.animate()
            .translationY(0f)
            .setDuration(165L)
            .setInterpolator(DecelerateInterpolator(1.6f))
            .start()
    }

    fun close() {
        if (!isOpen) return
        isOpen = false
        onVisibilityChanged(false)
        cardSurface.animate()
            .translationY(-dp(320f).toFloat())
            .setDuration(140L)
            .start()
        animate()
            .alpha(0f)
            .setDuration(140L)
            .withEndAction { visibility = View.GONE }
            .start()
    }

    private fun refreshSystemState() {
        val curBrightness = try {
            Settings.System.getInt(context.contentResolver, Settings.System.SCREEN_BRIGHTNESS)
        } catch (_: Exception) {
            165
        }
        brightnessSlider.value = (curBrightness / 255f).coerceIn(0f, 1f)

        val maxVol = max(1, audioManager?.getStreamMaxVolume(AudioManager.STREAM_MUSIC) ?: 15)
        val curVol = audioManager?.getStreamVolume(AudioManager.STREAM_MUSIC) ?: (maxVol / 2)
        volumeSlider.value = (curVol.toFloat() / maxVol.toFloat()).coerceIn(0f, 1f)

        val isPlaying = audioManager?.isMusicActive == true
        mediaCard.visibility = if (isPlaying) View.VISIBLE else View.GONE
        playPauseIcon.icon = if (isPlaying) FyrIcon.PAUSE else FyrIcon.PLAY
        playPauseIcon.invalidate()
    }

    private fun rebuildToggleRows() {
        togglesRow1.removeAllViews()
        togglesRow2.removeAllViews()

        val wifiOn = try {
            wifiManager?.isWifiEnabled == true
        } catch (_: Exception) {
            true
        }
        val btOn = try {
            BluetoothAdapter.getDefaultAdapter()?.isEnabled == true
        } catch (_: Exception) {
            false
        }
        val airplaneOn = try {
            Settings.Global.getInt(
                context.contentResolver,
                Settings.Global.AIRPLANE_MODE_ON,
                0
            ) != 0
        } catch (_: Exception) {
            false
        }
        val autoRotateOn = try {
            Settings.System.getInt(
                context.contentResolver,
                Settings.System.ACCELEROMETER_ROTATION,
                1
            ) != 0
        } catch (_: Exception) {
            true
        }
        val dndOn = try {
            val filter = notificationManager?.currentInterruptionFilter
                ?: NotificationManager.INTERRUPTION_FILTER_ALL
            filter != NotificationManager.INTERRUPTION_FILTER_ALL
        } catch (_: Exception) {
            false
        }

        // Row 1: Wi-Fi, Bluetooth, Airplane, Flashlight
        addToggleCell(
            togglesRow1,
            icon = FyrIcon.WIFI,
            description = "Wi-Fi",
            active = wifiOn,
            onTap = { toggleWifi() },
            onLongPress = { openIntent(Settings.ACTION_WIFI_SETTINGS) }
        )
        addToggleCell(
            togglesRow1,
            icon = FyrIcon.BLUETOOTH,
            description = "Bluetooth",
            active = btOn,
            onTap = { openIntent(Settings.ACTION_BLUETOOTH_SETTINGS) },
            onLongPress = { openIntent(Settings.ACTION_BLUETOOTH_SETTINGS) }
        )
        addToggleCell(
            togglesRow1,
            icon = FyrIcon.AIRPLANE,
            description = "Airplane",
            active = airplaneOn,
            onTap = { openIntent(Settings.ACTION_AIRPLANE_MODE_SETTINGS) }
        )
        addToggleCell(
            togglesRow1,
            icon = FyrIcon.FLASHLIGHT,
            description = "Flashlight",
            active = isTorchOn,
            onTap = { toggleTorch() }
        )

        // Row 2: Auto-Rotate, Do Not Disturb, Dark/Light Mode (long-press cycles Fyr accent), Hotspot
        addToggleCell(
            togglesRow2,
            icon = FyrIcon.ROTATE,
            description = "Auto-Rotate",
            active = autoRotateOn,
            onTap = { toggleAutoRotate(autoRotateOn) }
        )
        addToggleCell(
            togglesRow2,
            icon = FyrIcon.DND,
            description = "Do Not Disturb",
            active = dndOn,
            onTap = { toggleDnd(dndOn) }
        )
        addToggleCell(
            togglesRow2,
            icon = if (FyrThemeManager.isDark) FyrIcon.DARK_MODE else FyrIcon.LIGHT_MODE,
            description = if (FyrThemeManager.isDark) "Dark Mode" else "Light Mode",
            active = FyrThemeManager.isDark,
            onTap = {
                FyrThemeManager.toggleThemeMode()
                onThemeChanged()
            },
            onLongPress = { cycleAccentPreset() }
        )
        addToggleCell(
            togglesRow2,
            icon = FyrIcon.HOTSPOT,
            description = "Hotspot",
            active = false,
            onTap = { openIntent(Settings.ACTION_WIRELESS_SETTINGS) },
            onLongPress = { openIntent(Settings.ACTION_ACCESSIBILITY_SETTINGS) }
        )
    }

    private fun addToggleCell(
        row: LinearLayout,
        icon: FyrIcon,
        description: String,
        active: Boolean,
        onTap: () -> Unit,
        onLongPress: (() -> Unit)? = null
    ) {
        val wrapper = FrameLayout(context)
        val circle = FrameLayout(context).apply {
            contentDescription = description
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(
                    if (active) FyrThemeManager.accentWithAlpha(0.30f)
                    else FyrThemeManager.cardColor
                )
            }
            setOnClickListener { onTap() }
            if (onLongPress != null) {
                setOnLongClickListener {
                    onLongPress()
                    true
                }
            }
        }
        val iconView = FyrIconView(
            context = context,
            icon = icon,
            tint = if (active) FyrThemeManager.textColor else FyrThemeManager.textColorMuted
        )
        circle.addView(iconView, LayoutParams(dp(24f), dp(24f), Gravity.CENTER))
        wrapper.addView(circle, LayoutParams(dp(58f), dp(58f), Gravity.CENTER))
        row.addView(wrapper, LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
    }

    private fun wrapIconButton(
        iconView: FyrIconView,
        boxDp: Float,
        iconDp: Float,
        onTap: () -> Unit
    ): View {
        return FrameLayout(context).apply {
            setOnClickListener { onTap() }
            addView(iconView, LayoutParams(dp(iconDp), dp(iconDp), Gravity.CENTER))
            layoutParams = LinearLayout.LayoutParams(dp(boxDp), dp(boxDp))
        }
    }

    private fun createSliderRow(
        iconView: FyrIconView,
        slider: FyrSliderBar,
        trailing: View?
    ): View {
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        row.addView(
            iconView,
            LinearLayout.LayoutParams(dp(20f), dp(20f)).apply {
                rightMargin = dp(14f)
            }
        )
        row.addView(
            slider,
            LinearLayout.LayoutParams(0, dp(32f), 1f)
        )
        if (trailing != null) {
            row.addView(
                trailing,
                LinearLayout.LayoutParams(dp(28f), dp(28f)).apply {
                    leftMargin = dp(6f)
                }
            )
        }
        return row
    }

    private fun cycleAccentPreset() {
        val presets = FyrThemeManager.ACCENT_PRESETS
        val curIdx = presets.indexOfFirst { it.color == FyrThemeManager.accentColor }
        val next = presets[(curIdx + 1) % presets.size]
        FyrThemeManager.setAccent(next.color)
        onThemeChanged()
        Toast.makeText(context, "Accent: ${next.name}", Toast.LENGTH_SHORT).show()
    }

    private fun toggleWifi() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            close()
            context.startActivity(
                Intent(Settings.Panel.ACTION_WIFI).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
            )
        } else {
            @Suppress("DEPRECATION")
            wifiManager?.isWifiEnabled = !(wifiManager?.isWifiEnabled ?: false)
            rebuildToggleRows()
        }
    }

    private fun toggleTorch() {
        val id = torchCameraId
        if (id == null) {
            Toast.makeText(context, "No flashlight available", Toast.LENGTH_SHORT).show()
            return
        }
        try {
            isTorchOn = !isTorchOn
            cameraManager?.setTorchMode(id, isTorchOn)
            rebuildToggleRows()
        } catch (_: Exception) {
        }
    }

    private fun toggleAutoRotate(currentlyOn: Boolean) {
        if (Settings.System.canWrite(context)) {
            Settings.System.putInt(
                context.contentResolver,
                Settings.System.ACCELEROMETER_ROTATION,
                if (currentlyOn) 0 else 1
            )
            rebuildToggleRows()
        } else {
            close()
            context.startActivity(
                Intent(
                    Settings.ACTION_MANAGE_WRITE_SETTINGS,
                    Uri.parse("package:${context.packageName}")
                ).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
            )
        }
    }

    private fun toggleDnd(currentlyOn: Boolean) {
        val nm = notificationManager ?: return
        if (nm.isNotificationPolicyAccessGranted) {
            nm.setInterruptionFilter(
                if (currentlyOn) NotificationManager.INTERRUPTION_FILTER_ALL
                else NotificationManager.INTERRUPTION_FILTER_NONE
            )
            rebuildToggleRows()
        } else {
            close()
            context.startActivity(
                Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
            )
        }
    }

    private fun dispatchMediaKey(keyCode: Int) {
        val am = audioManager ?: return
        val now = SystemClock.uptimeMillis()
        am.dispatchMediaKeyEvent(KeyEvent(now, now, KeyEvent.ACTION_DOWN, keyCode, 0))
        am.dispatchMediaKeyEvent(KeyEvent(now, now, KeyEvent.ACTION_UP, keyCode, 0))
    }

    private fun openIntent(action: String) {
        close()
        try {
            context.startActivity(Intent(action).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK })
        } catch (_: Exception) {
        }
    }
}
