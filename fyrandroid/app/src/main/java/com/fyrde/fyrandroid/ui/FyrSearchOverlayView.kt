package com.fyrde.fyrandroid.ui

import android.annotation.SuppressLint
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.text.Editable
import android.text.InputType
import android.text.TextUtils
import android.text.TextWatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.animation.DecelerateInterpolator
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.BaseAdapter
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.GridView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import com.fyrde.fyrandroid.model.AppEntry
import com.fyrde.fyrandroid.model.AppRepository
import com.fyrde.fyrandroid.search.FyrSearchEvaluator
import com.fyrde.fyrandroid.theme.FyrThemeManager
import kotlin.math.max

/**
 * Custom Search & App Drawer modeled directly on desktop `fyrsearch/lib/main.dart`:
 * - Translucent frosted backdrop letting the blurred wallpaper glow through
 * - Floating pill search bar (`50dp` radius, subtle `dividerColor` hairline border,
 *   clean vector magnifying glass icon, `"Type to search..."` placeholder)
 * - Clean floating app icon grid directly over the blurred wallpaper (no card boxes)
 * - Inline calculator math & Fyr theme commands (`:dark`, `:light`, `:accent cyan`)
 */
@SuppressLint("ViewConstructor")
class FyrSearchOverlayView(
    context: Context,
    private val repo: AppRepository,
    private val onLaunchApp: (AppEntry) -> Unit,
    private val onAppLongPress: (View, AppEntry) -> Unit,
    private val onThemeChanged: () -> Unit,
    private val onVisibilityChanged: (Boolean) -> Unit = {}
) : FrameLayout(context) {

    private val density = resources.displayMetrics.density
    private fun dp(v: Float): Int = (v * density).toInt()

    private val searchPillBg = GradientDrawable()
    private val inlineCardBg = GradientDrawable()
    private val searchIcon = FyrIconView(context, FyrIcon.SEARCH, FyrThemeManager.textColor)
    private val clearIcon = FyrIconView(context, FyrIcon.CLOSE, FyrThemeManager.textColorMuted)
    private val clearBtn: FrameLayout
    private val searchInput: EditText
    private val inlineCard: LinearLayout
    private val inlineTitle: TextView
    private val inlineSubtitle: TextView
    private val appGridView: GridView
    private val emptyWebSearchBtn: TextView

    private var allApps: List<AppEntry> = emptyList()
    private var filteredApps: List<AppEntry> = emptyList()
    private var currentInlineAnswer: FyrSearchEvaluator.InlineAnswer? = null
    private val gridAdapter = AppDrawerGridAdapter()

    var isOpen: Boolean = false
        private set

    init {
        visibility = View.GONE
        isClickable = true
        setOnClickListener { close() }

        val contentColumn = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(22f), dp(72f), dp(22f), dp(20f))
        }

        // Frosted floating pill search bar matching `fyrsearch/lib/main.dart` (`BorderRadius.circular(50)`)
        val searchRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(20f), dp(6f), dp(14f), dp(6f))
            background = searchPillBg
            elevation = dp(12f).toFloat()
        }

        searchInput = EditText(context).apply {
            hint = "Type to search..."
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            setSingleLine(true)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            imeOptions = EditorInfo.IME_ACTION_GO
            background = null
            setPadding(0, dp(12f), 0, dp(12f))
            setOnEditorActionListener { _, actionId, event ->
                if (actionId == EditorInfo.IME_ACTION_GO ||
                    actionId == EditorInfo.IME_ACTION_DONE ||
                    (event?.keyCode == KeyEvent.KEYCODE_ENTER && event.action == KeyEvent.ACTION_DOWN)
                ) {
                    launchTopMatchOrAnswer()
                    true
                } else {
                    false
                }
            }
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                    updateFilter(s?.toString() ?: "")
                }
                override fun afterTextChanged(s: Editable?) {}
            })
        }

        clearBtn = FrameLayout(context).apply {
            visibility = View.GONE
            setOnClickListener {
                searchInput.setText("")
                searchInput.requestFocus()
            }
            addView(clearIcon, LayoutParams(dp(16f), dp(16f), Gravity.CENTER))
        }

        searchRow.addView(
            searchIcon,
            LinearLayout.LayoutParams(dp(22f), dp(22f)).apply {
                rightMargin = dp(14f)
            }
        )
        searchRow.addView(
            searchInput,
            LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
        )
        searchRow.addView(clearBtn, LinearLayout.LayoutParams(dp(32f), dp(32f)))

        contentColumn.addView(
            searchRow,
            LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                bottomMargin = dp(24f)
            }
        )

        // Subtle frosted inline calculator / Fyr command answer pill (only visible when typing math/commands)
        inlineCard = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(20f), dp(12f), dp(20f), dp(12f))
            background = inlineCardBg
            visibility = View.GONE
            setOnClickListener {
                val ans = currentInlineAnswer ?: return@setOnClickListener
                handleInlineAnswerTap(ans)
            }
        }
        inlineTitle = TextView(context).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
        }
        inlineSubtitle = TextView(context).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            gravity = Gravity.END
        }
        inlineCard.addView(
            inlineTitle,
            LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
        )
        inlineCard.addView(inlineSubtitle)
        contentColumn.addView(
            inlineCard,
            LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                bottomMargin = dp(18f)
            }
        )

        // Clean floating app icon grid directly over blurred wallpaper (matching `screenshots/search.png`)
        appGridView = GridView(context).apply {
            numColumns = 4
            verticalSpacing = dp(20f)
            horizontalSpacing = dp(10f)
            stretchMode = GridView.STRETCH_COLUMN_WIDTH
            clipToPadding = false
            setPadding(0, dp(4f), 0, dp(24f))
            adapter = gridAdapter
        }
        contentColumn.addView(
            appGridView,
            LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f)
        )

        // Web search fallback when query has no local app matches
        emptyWebSearchBtn = TextView(context).apply {
            gravity = Gravity.CENTER
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setPadding(dp(20f), dp(12f), dp(20f), dp(12f))
            visibility = View.GONE
            setOnClickListener {
                val q = searchInput.text?.toString()?.trim().orEmpty()
                if (q.isNotEmpty()) {
                    val uri = Uri.parse("https://www.google.com/search?q=${Uri.encode(q)}")
                    context.startActivity(
                        Intent(Intent.ACTION_VIEW, uri).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                    )
                    close()
                }
            }
        }
        contentColumn.addView(emptyWebSearchBtn)

        addView(
            contentColumn,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
        )

        applyTheme()
    }

    fun applyTheme() {
        // Translucent frosted scrim letting blurred wallpaper show through like desktop `fyrSearch`
        setBackgroundColor(if (FyrThemeManager.isDark) 0x5C121018 else 0x88F4F4F8.toInt())
        searchPillBg.apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(50f).toFloat()
            setColor(if (FyrThemeManager.isDark) 0x6E181620 else 0xCCF4F4F8.toInt())
            setStroke(max(1, dp(1f)), FyrThemeManager.dividerColor)
        }
        inlineCardBg.apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(24f).toFloat()
            setColor(if (FyrThemeManager.isDark) 0x7A1E1B28 else 0xCCF4F4F8.toInt())
            setStroke(max(1, dp(1f)), FyrThemeManager.dividerColor)
        }
        searchIcon.setTint(FyrThemeManager.textColor)
        clearIcon.setTint(FyrThemeManager.textColorMuted)
        searchInput.setTextColor(FyrThemeManager.textColor)
        searchInput.setHintTextColor(FyrThemeManager.textColorMuted)
        inlineTitle.setTextColor(FyrThemeManager.textColor)
        inlineSubtitle.setTextColor(FyrThemeManager.textColorMuted)
        emptyWebSearchBtn.setTextColor(FyrThemeManager.textColor)
        gridAdapter.notifyDataSetChanged()
    }

    fun bindApps(apps: List<AppEntry>) {
        allApps = apps
        updateFilter(searchInput.text?.toString() ?: "")
    }

    fun openAndFocus() {
        isOpen = true
        onVisibilityChanged(true)
        applyTheme()
        searchInput.setText("")
        updateFilter("")
        visibility = View.VISIBLE
        alpha = 0f
        translationY = dp(40f).toFloat()
        animate()
            .alpha(1f)
            .translationY(0f)
            .setDuration(165L)
            .setInterpolator(DecelerateInterpolator(1.6f))
            .start()

        searchInput.requestFocus()
        post {
            searchInput.requestFocus()
            val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            imm?.showSoftInput(searchInput, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    fun close() {
        if (!isOpen) return
        isOpen = false
        onVisibilityChanged(false)
        val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
        imm?.hideSoftInputFromWindow(searchInput.windowToken, 0)
        animate()
            .alpha(0f)
            .translationY(dp(32f).toFloat())
            .setDuration(140L)
            .withEndAction {
                visibility = View.GONE
            }
            .start()
    }

    private fun updateFilter(query: String) {
        clearBtn.visibility = if (query.isNotEmpty()) View.VISIBLE else View.GONE
        currentInlineAnswer = FyrSearchEvaluator.evaluateInlineQuery(query)
        val ans = currentInlineAnswer
        if (ans != null) {
            inlineTitle.text = ans.title
            inlineSubtitle.text = ans.subtitle
            inlineCard.visibility = View.VISIBLE
        } else {
            inlineCard.visibility = View.GONE
        }

        filteredApps = FyrSearchEvaluator.filterApps(allApps, query)
        gridAdapter.notifyDataSetChanged()

        if (filteredApps.isEmpty() && query.isNotBlank()) {
            emptyWebSearchBtn.text = "Search the web for \"${query.trim()}\"  →"
            emptyWebSearchBtn.visibility = View.VISIBLE
        } else {
            emptyWebSearchBtn.visibility = View.GONE
        }
    }

    private fun handleInlineAnswerTap(ans: FyrSearchEvaluator.InlineAnswer) {
        val cmd = ans.commandAction
        if (cmd != null) {
            when {
                cmd == "theme:dark" -> FyrThemeManager.setDarkMode(true)
                cmd == "theme:light" -> FyrThemeManager.setDarkMode(false)
                cmd.startsWith("accent:") -> {
                    val name = cmd.removePrefix("accent:")
                    val match = FyrThemeManager.ACCENT_PRESETS.firstOrNull {
                        it.name.lowercase().contains(name)
                    }
                    if (match != null) FyrThemeManager.setAccent(match.color)
                }
            }
            onThemeChanged()
            close()
            return
        }
        val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        cm?.setPrimaryClip(ClipData.newPlainText("fyrsearch", ans.copyValue))
        Toast.makeText(context, "Copied ${ans.copyValue}", Toast.LENGTH_SHORT).show()
    }

    private fun launchTopMatchOrAnswer() {
        val ans = currentInlineAnswer
        if (ans != null && ans.commandAction != null) {
            handleInlineAnswerTap(ans)
            return
        }
        val topApp = filteredApps.firstOrNull()
        if (topApp != null) {
            close()
            onLaunchApp(topApp)
            return
        }
        if (ans != null) {
            handleInlineAnswerTap(ans)
        }
    }

    private inner class AppDrawerGridAdapter : BaseAdapter() {
        override fun getCount(): Int = filteredApps.size
        override fun getItem(position: Int): AppEntry = filteredApps[position]
        override fun getItemId(position: Int): Long = position.toLong()

        override fun getView(position: Int, convertView: View?, parent: ViewGroup?): View {
            val app = filteredApps[position]
            val cell = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPadding(dp(4f), dp(6f), dp(4f), dp(6f))
            }
            val icon = SquircleIconView(context, app, repo)
            val label = TextView(context).apply {
                text = app.label
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                setTextColor(FyrThemeManager.textColor)
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                gravity = Gravity.CENTER
                setPadding(dp(2f), dp(7f), dp(2f), 0)
                setShadowLayer(4f, 0f, 1f, 0x88000000.toInt())
            }
            cell.addView(icon, LinearLayout.LayoutParams(dp(56f), dp(56f)))
            cell.addView(
                label,
                LinearLayout.LayoutParams(
                    LayoutParams.MATCH_PARENT,
                    LayoutParams.WRAP_CONTENT
                )
            )
            cell.setOnClickListener {
                close()
                onLaunchApp(app)
            }
            cell.setOnLongClickListener { v ->
                onAppLongPress(v, app)
                true
            }
            return cell
        }
    }
}
