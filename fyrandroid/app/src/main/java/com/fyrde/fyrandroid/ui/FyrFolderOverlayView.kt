package com.fyrde.fyrandroid.ui

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.InputType
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.KeyEvent
import android.view.View
import android.view.animation.DecelerateInterpolator
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.GridLayout
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.ScrollView
import android.widget.TextView
import com.fyrde.fyrandroid.model.AppEntry
import com.fyrde.fyrandroid.model.AppRepository
import com.fyrde.fyrandroid.model.HomeItem
import com.fyrde.fyrandroid.theme.FyrThemeManager
import kotlin.math.max

/**
 * Frosted-glass Fyr Folder overlay opened when tapping a grouped folder on the home screen.
 * Supports inline folder renaming, launching apps, reordering inside the folder,
 * and removing apps back to the home screen.
 */
@SuppressLint("ViewConstructor")
class FyrFolderOverlayView(
    context: Context,
    private val repo: AppRepository,
    private val onLaunchApp: (AppEntry) -> Unit,
    private val onAppActionMenu: (View, AppEntry) -> Unit,
    private val onVisibilityChanged: (Boolean) -> Unit = {}
) : FrameLayout(context) {

    private val density = resources.displayMetrics.density
    private fun dp(v: Float): Int = (v * density).toInt()

    private val cardSurface = LinearLayout(context)
    private val cardBg = GradientDrawable()
    private val titleInput = EditText(context)
    private val ungroupBtn = TextView(context)
    private val appsGrid = GridLayout(context)

    private var activeFolderId: String? = null

    var isOpen: Boolean = false
        private set

    init {
        visibility = View.GONE
        isClickable = true
        setBackgroundColor(0x5A000000)
        setOnClickListener { close() }

        cardSurface.apply {
            orientation = LinearLayout.VERTICAL
            isClickable = true
            setPadding(dp(20f), dp(18f), dp(20f), dp(20f))
            background = cardBg
            elevation = dp(18f).toFloat()
        }

        val headerRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(4f), 0, dp(4f), dp(12f))
        }

        titleInput.apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
            setSingleLine(true)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_WORDS
            imeOptions = EditorInfo.IME_ACTION_DONE
            background = null
            hint = "Folder"
            setOnEditorActionListener { _, actionId, event ->
                if (actionId == EditorInfo.IME_ACTION_DONE ||
                    (event?.keyCode == KeyEvent.KEYCODE_ENTER && event.action == KeyEvent.ACTION_DOWN)
                ) {
                    commitRename()
                    true
                } else {
                    false
                }
            }
            setOnFocusChangeListener { _, hasFocus ->
                if (!hasFocus) commitRename()
            }
        }

        ungroupBtn.apply {
            text = "Ungroup"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f)
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            setPadding(dp(10f), dp(5f), dp(10f), dp(5f))
            setOnClickListener {
                val id = activeFolderId ?: return@setOnClickListener
                close()
                repo.ungroupFolder(id)
            }
        }

        headerRow.addView(
            titleInput,
            LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
        )
        headerRow.addView(ungroupBtn)
        cardSurface.addView(headerRow)

        appsGrid.apply {
            columnCount = 3
        }
        val scroll = ScrollView(context).apply {
            isVerticalScrollBarEnabled = false
            addView(
                appsGrid,
                LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
            )
        }
        cardSurface.addView(
            scroll,
            LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
        )

        val cardParams = LayoutParams(
            LayoutParams.MATCH_PARENT,
            LayoutParams.WRAP_CONTENT,
            Gravity.CENTER
        ).apply {
            setMargins(dp(26f), dp(48f), dp(26f), dp(48f))
        }
        addView(cardSurface, cardParams)

        applyTheme()
    }

    fun applyTheme() {
        cardBg.apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(24f).toFloat()
            setColor(FyrThemeManager.panelBgColor)
            setStroke(max(1, dp(1f)), FyrThemeManager.dividerColor)
        }
        titleInput.setTextColor(FyrThemeManager.textColor)
        titleInput.setHintTextColor(FyrThemeManager.textColorMuted)
        ungroupBtn.setTextColor(FyrThemeManager.textColorMuted)
        ungroupBtn.background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(10f).toFloat()
            setColor(FyrThemeManager.cardColor)
        }
        refreshIfOpen()
    }

    fun open(folder: HomeItem.Folder) {
        activeFolderId = folder.id
        isOpen = true
        onVisibilityChanged(true)
        renderFolder(folder)
        visibility = View.VISIBLE
        animate().cancel()
        cardSurface.animate().cancel()
        alpha = 0f
        cardSurface.scaleX = 0.90f
        cardSurface.scaleY = 0.90f
        animate().alpha(1f).setDuration(150L).start()
        cardSurface.animate()
            .scaleX(1f)
            .scaleY(1f)
            .setDuration(175L)
            .setInterpolator(DecelerateInterpolator(1.6f))
            .start()
    }

    fun refreshIfOpen() {
        if (!isOpen) return
        val id = activeFolderId ?: return
        val updated = repo.getFolderById(id)
        if (updated == null) {
            close()
        } else {
            renderFolder(updated)
        }
    }

    fun close() {
        if (!isOpen) return
        commitRename()
        isOpen = false
        activeFolderId = null
        onVisibilityChanged(false)
        val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
        imm?.hideSoftInputFromWindow(titleInput.windowToken, 0)
        animate().cancel()
        cardSurface.animate().cancel()
        cardSurface.animate()
            .scaleX(0.92f)
            .scaleY(0.92f)
            .setDuration(130L)
            .start()
        animate()
            .alpha(0f)
            .setDuration(130L)
            .withEndAction { visibility = View.GONE }
            .start()
    }

    private fun commitRename() {
        val id = activeFolderId ?: return
        val text = titleInput.text?.toString()?.trim().orEmpty()
        if (text.isNotEmpty()) {
            repo.renameFolder(id, text)
        }
    }

    private fun renderFolder(folder: HomeItem.Folder) {
        if (titleInput.text?.toString() != folder.name && !titleInput.hasFocus()) {
            titleInput.setText(folder.name)
        }
        appsGrid.removeAllViews()
        folder.apps.forEachIndexed { idx, app ->
            val cell = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPadding(dp(6f), dp(10f), dp(6f), dp(10f))
            }
            val icon = SquircleIconView(context, app, repo)
            val label = TextView(context).apply {
                text = app.label
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f)
                setTextColor(FyrThemeManager.textColor)
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                gravity = Gravity.CENTER
                setPadding(dp(2f), dp(6f), dp(2f), 0)
            }
            cell.addView(icon, LinearLayout.LayoutParams(dp(56f), dp(56f)))
            cell.addView(
                label,
                LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
            )
            cell.setOnClickListener {
                close()
                onLaunchApp(app)
            }
            cell.setOnLongClickListener { v ->
                v.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                showFolderAppMenu(v, folder, idx, app)
                true
            }
            val lp = GridLayout.LayoutParams(
                GridLayout.spec(idx / 3),
                GridLayout.spec(idx % 3, 1f)
            ).apply {
                width = 0
                height = LayoutParams.WRAP_CONTENT
            }
            appsGrid.addView(cell, lp)
        }
    }

    private fun showFolderAppMenu(anchor: View, folder: HomeItem.Folder, idx: Int, app: AppEntry) {
        val popup = PopupMenu(context, anchor)
        popup.menu.add(0, 1, 0, "Remove from Folder")
        if (idx > 0) popup.menu.add(0, 2, 1, "Move Left")
        if (idx < folder.apps.lastIndex) popup.menu.add(0, 3, 2, "Move Right")
        popup.menu.add(0, 4, 3, "More Options...")

        popup.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                1 -> {
                    repo.removeAppFromFolder(folder.id, app.componentKey)
                    refreshIfOpen()
                    true
                }
                2 -> {
                    repo.moveAppInFolder(folder.id, idx, idx - 1)
                    refreshIfOpen()
                    true
                }
                3 -> {
                    repo.moveAppInFolder(folder.id, idx, idx + 1)
                    refreshIfOpen()
                    true
                }
                4 -> {
                    close()
                    onAppActionMenu(anchor, app)
                    true
                }
                else -> false
            }
        }
        popup.show()
    }
}
