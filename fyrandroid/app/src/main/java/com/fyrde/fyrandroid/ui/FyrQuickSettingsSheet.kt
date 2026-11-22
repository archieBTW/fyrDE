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
import android.os.BatteryManager
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
import android.widget.SeekBar
import android.widget.TextView
import android.widget.Toast
import com.fyrde.fyrandroid.theme.FyrThemeManager
import kotlin.math.max

/**
 * Custom Fyr Quick Settings menu modeled directly on `fyrtaskbar/lib/ui/quick_settings.dart`:
 * - Slides down from the top on downward swipes
 * - 2x4 grid of 58dp circular `QuickToggle` buttons (Wi-Fi, Bluetooth, Airplane, Flashlight,
 *   Auto-Rotate, Do Not Disturb, Dark/Light Mode, Hotspot/Night Display)
 * - Fyr Media Controls Card (Previous, Play/Pause, Next)
 * - Brightness & Volume `SliderRow` bars
 * - Live Light/Dark Mode & Fyr Accent Color customizer + Top-Edge Interceptor toggle
 */
@SuppressLint("ViewConstructor")
class FyrQuickSettingsSheet(
    context: Context,
    private val onThemeChanged: () -> Unit,
    private val onAdjustWindowBrightness: (Float) -> Unit
) : FrameLayout(context) {

    private val density = resources.displayMetrics.density
    private fun dp(v: Float): Int = (v * density).toInt()

    private val cardSurface = LinearLayout(context)
    private val cardBg = GradientDrawable()
    private val mediaCardBg = GradientDrawable()
    private val settingsPillBg = GradientDrawable()

    private val batteryLabel = TextView(context)
    private val settingsBtn = TextView(context)
    private val togglesRow1 = LinearLayout(context)
    private val togglesRow2 = LinearLayout(context)
    private val mediaTitle = TextView(context)
    private val brightnessSlider = SeekBar(context)
    private val volumeSlider = SeekBar(context)
    private val accentSwatchesRow = LinearLayout(context)

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
        setBackgroundColor(0x66000000)
        setOnClickListener { close() }

        initTorchCamera()

        cardSurface.apply {
            orientation = LinearLayout.VERTICAL
            isClickable = true
            setPadding(dp(20f), dp(18f), dp(20f), dp(20f))
            background = cardBg
        }

        // Top Bar: Battery status + Top-Edge Service button + System Settings pill
        val topHeader = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 0, 0, dp(16f))
        }

        batteryLabel.apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f)
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
        }

        val topEdgeBtn = TextView(context).apply {
            text = "Top-Swipe"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            setPadding(dp(10f), dp(6f), dp(10f), dp(6f))
            setOnClickListener {
                close()
                context.startActivity(
                    Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                )
                Toast.makeText(
                    context,
                    "Enable 'Fyr Top-Edge Quick Settings Interceptor' to intercept top-bar swipes",
                    Toast.LENGTH_LONG
                ).show()
            }
        }

        settingsBtn.apply {
            text = "⚙ Settings"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(dp(12f), dp(6f), dp(12f), dp(6f))
            background = settingsPillBg
            setOnClickListener {
                close()
                context.startActivity(
                    Intent(Settings.ACTION_SETTINGS).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                )
            }
        }

        topHeader.addView(
            batteryLabel,
            LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
        )
        topHeader.addView(topEdgeBtn)
        topHeader.addView(
            settingsBtn,
            LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                leftMargin = dp(8f)
            }
        )
        cardSurface.addView(topHeader)

        // 2x4 Circular Quick Toggles (`QuickToggle` in `fyrtaskbar`)
        togglesRow1.apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        togglesRow2.apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, dp(14f), 0, 0)
        }
        cardSurface.addView(togglesRow1)
        cardSurface.addView(togglesRow2)

        // Media Controls Card (`QuickSettingsMediaCard` in `fyrtaskbar`)
        val mediaCard = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(14f), dp(12f), dp(14f), dp(12f))
            background = mediaCardBg
        }
        mediaTitle.apply {
            text = "♫  Media Playback"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f)
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        }
        val prevBtn = createMediaControlBtn("⏮") {
            dispatchMediaKey(KeyEvent.KEYCODE_MEDIA_PREVIOUS)
        }
        val playPauseBtn = createMediaControlBtn("⏯") {
            dispatchMediaKey(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
        }
        val nextBtn = createMediaControlBtn("⏭") {
            dispatchMediaKey(KeyEvent.KEYCODE_MEDIA_NEXT)
        }
        mediaCard.addView(
            mediaTitle,
            LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
        )
        mediaCard.addView(prevBtn)
        mediaCard.addView(playPauseBtn)
        mediaCard.addView(nextBtn)
        cardSurface.addView(
            mediaCard,
            LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                topMargin = dp(16f)
                bottomMargin = dp(16f)
            }
        )

        // Brightness SliderRow
        cardSurface.addView(
            createSliderRow("☀", brightnessSlider, trailingText = null)
        )
        brightnessSlider.max = 255
        brightnessSlider.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                if (!fromUser) return
                val clamped = progress.coerceIn(10, 255)
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
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {}
        })

        // Volume SliderRow
        cardSurface.addView(
            createSliderRow(
                "🔊",
                volumeSlider,
                trailingText = "›",
                onTrailingClick = {
                    close()
                    val panelIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        Intent(Settings.Panel.ACTION_VOLUME)
                    } else {
                        Intent(Settings.ACTION_SOUND_SETTINGS)
                    }
                    context.startActivity(panelIntent.apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK })
                }
            ),
            LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                topMargin = dp(10f)
            }
        )
        val maxVol = audioManager?.getStreamMaxVolume(AudioManager.STREAM_MUSIC) ?: 15
        volumeSlider.max = max(1, maxVol)
        volumeSlider.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                if (!fromUser) return
                audioManager?.setStreamVolume(AudioManager.STREAM_MUSIC, progress, 0)
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {}
        })

        // Fyr Accent Color Customizer Row
        val accentHeader = TextView(context).apply {
            text = "FYR ACCENT COLOR"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, dp(16f), 0, dp(8f))
            letterSpacing = 0.08f
        }
        cardSurface.addView(accentHeader)

        accentSwatchesRow.apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        cardSurface.addView(accentSwatchesRow)

        val cardParams = LayoutParams(
            LayoutParams.MATCH_PARENT,
            LayoutParams.WRAP_CONTENT,
            Gravity.TOP
        ).apply {
            setMargins(dp(14f), dp(36f), dp(14f), dp(14f))
        }
        addView(cardSurface, cardParams)

        applyTheme()
    }

    private fun initTorchCamera() {
        try {
            val cm = cameraManager ?: return
            for (id in cm.cameraIdList) {
                val chars = cm.getCameraCharacteristics(id)
                val hasFlash = chars.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
                if (hasFlash) {
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
            cornerRadius = dp(24f).toFloat()
            setColor(FyrThemeManager.panelBgColor)
            setStroke(max(1, dp(1f)), FyrThemeManager.dividerColor)
        }
        mediaCardBg.apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(16f).toFloat()
            setColor(FyrThemeManager.cardColor)
            setStroke(max(1, dp(1f)), FyrThemeManager.dividerColor)
        }
        settingsPillBg.apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(10f).toFloat()
            setColor(FyrThemeManager.cardColor)
        }
        batteryLabel.setTextColor(FyrThemeManager.textColor)
        settingsBtn.setTextColor(FyrThemeManager.textColor)
        mediaTitle.setTextColor(FyrThemeManager.textColor)

        rebuildToggleRows()
        rebuildAccentSwatches()
    }

    fun open() {
        isOpen = true
        refreshSystemState()
        applyTheme()
        visibility = View.VISIBLE
        cardSurface.translationY = -dp(420f).toFloat()
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
        cardSurface.animate()
            .translationY(-dp(380f).toFloat())
            .setDuration(140L)
            .start()
        animate()
            .alpha(0f)
            .setDuration(140L)
            .withEndAction { visibility = View.GONE }
            .start()
    }

    private fun refreshSystemState() {
        val bm = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        val pct = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: 100
        batteryLabel.text = "⚡ $pct%  •  Fyr Quick Settings"

        val curBrightness = try {
            Settings.System.getInt(context.contentResolver, Settings.System.SCREEN_BRIGHTNESS)
        } catch (_: Exception) {
            140
        }
        brightnessSlider.progress = curBrightness.coerceIn(0, 255)

        val curVol = audioManager?.getStreamVolume(AudioManager.STREAM_MUSIC) ?: 7
        volumeSlider.progress = curVol
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
        togglesRow1.addView(
            createQuickToggle(
                iconText = "🛜",
                label = "Wi-Fi",
                active = wifiOn,
                onTap = { toggleWifi() },
                onLongPress = { openIntent(Settings.ACTION_WIFI_SETTINGS) }
            ),
            LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
        )
        togglesRow1.addView(
            createQuickToggle(
                iconText = "ᛒ",
                label = "Bluetooth",
                active = btOn,
                onTap = { openIntent(Settings.ACTION_BLUETOOTH_SETTINGS) },
                onLongPress = { openIntent(Settings.ACTION_BLUETOOTH_SETTINGS) }
            ),
            LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
        )
        togglesRow1.addView(
            createQuickToggle(
                iconText = "✈",
                label = "Airplane",
                active = airplaneOn,
                onTap = { openIntent(Settings.ACTION_AIRPLANE_MODE_SETTINGS) }
            ),
            LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
        )
        togglesRow1.addView(
            createQuickToggle(
                iconText = "🔦",
                label = "Flashlight",
                active = isTorchOn,
                onTap = { toggleTorch() }
            ),
            LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
        )

        // Row 2: Auto-Rotate, Do Not Disturb, Dark/Light Mode, Hotspot/Night
        togglesRow2.addView(
            createQuickToggle(
                iconText = "⟳",
                label = "Auto-Rotate",
                active = autoRotateOn,
                onTap = { toggleAutoRotate(autoRotateOn) }
            ),
            LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
        )
        togglesRow2.addView(
            createQuickToggle(
                iconText = "🌙",
                label = "DND",
                active = dndOn,
                onTap = { toggleDnd(dndOn) }
            ),
            LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
        )
        togglesRow2.addView(
            createQuickToggle(
                iconText = if (FyrThemeManager.isDark) "◑" else "☀",
                label = if (FyrThemeManager.isDark) "Dark Mode" else "Light Mode",
                active = FyrThemeManager.isDark,
                onTap = {
                    FyrThemeManager.toggleThemeMode()
                    onThemeChanged()
                }
            ),
            LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
        )
        togglesRow2.addView(
            createQuickToggle(
                iconText = "📡",
                label = "Hotspot",
                active = false,
                onTap = { openIntent(Settings.ACTION_WIRELESS_SETTINGS) }
            ),
            LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
        )
    }

    private fun createQuickToggle(
        iconText: String,
        label: String,
        active: Boolean,
        onTap: () -> Unit,
        onLongPress: (() -> Unit)? = null
    ): View {
        val col = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
        }

        val circle = TextView(context).apply {
            text = iconText
            gravity = Gravity.CENTER
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 19f)
            setTextColor(
                if (active) FyrThemeManager.textColor else FyrThemeManager.textColorMuted
            )
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(
                    if (active) FyrThemeManager.accentWithAlpha(0.32f)
                    else FyrThemeManager.cardColor
                )
                setStroke(
                    max(1, dp(1f)),
                    if (active) FyrThemeManager.accentWithAlpha(0.65f)
                    else FyrThemeManager.dividerColor
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

        val lbl = TextView(context).apply {
            text = label
            gravity = Gravity.CENTER
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10.5f)
            setTextColor(
                if (active) FyrThemeManager.textColor else FyrThemeManager.textColorMuted
            )
            setPadding(0, dp(5f), 0, 0)
            maxLines = 1
        }

        col.addView(circle, LinearLayout.LayoutParams(dp(56f), dp(56f)))
        col.addView(lbl)
        return col
    }

    private fun createMediaControlBtn(symbol: String, onTap: () -> Unit): View {
        return TextView(context).apply {
            text = symbol
            gravity = Gravity.CENTER
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setTextColor(FyrThemeManager.textColor)
            setPadding(dp(10f), dp(4f), dp(10f), dp(4f))
            setOnClickListener { onTap() }
        }
    }

    private fun createSliderRow(
        iconSymbol: String,
        slider: SeekBar,
        trailingText: String?,
        onTrailingClick: (() -> Unit)? = null
    ): View {
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val icon = TextView(context).apply {
            text = iconSymbol
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setTextColor(FyrThemeManager.textColorMuted)
            setPadding(0, 0, dp(10f), 0)
        }
        row.addView(icon)
        row.addView(
            slider,
            LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
        )
        if (trailingText != null) {
            val trail = TextView(context).apply {
                text = trailingText
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
                setTextColor(FyrThemeManager.textColor)
                setPadding(dp(10f), dp(2f), dp(4f), dp(2f))
                setOnClickListener { onTrailingClick?.invoke() }
            }
            row.addView(trail)
        }
        return row
    }

    private fun rebuildAccentSwatches() {
        accentSwatchesRow.removeAllViews()
        for (preset in FyrThemeManager.ACCENT_PRESETS) {
            val selected = preset.color == FyrThemeManager.accentColor
            val swatch = View(context).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(preset.color)
                    setStroke(
                        if (selected) dp(2.5f) else dp(1f),
                        if (selected) Color.WHITE else 0x44FFFFFF
                    )
                }
                setOnClickListener {
                    FyrThemeManager.setAccent(preset.color)
                    onThemeChanged()
                }
            }
            val lp = LinearLayout.LayoutParams(dp(26f), dp(26f)).apply {
                rightMargin = dp(10f)
            }
            accentSwatchesRow.addView(swatch, lp)
        }
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
