package com.fyrde.fyrandroid.search

import com.fyrde.fyrandroid.model.AppEntry
import java.util.Locale
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.roundToLong
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Pure Kotlin search engine & inline calculator mirroring `fyrsearch`:
 * - Fuzzy & prefix scoring for app drawer filtering
 * - Inline math calculator (`24 * 7`, `1920 / 16 * 9`, `sqrt(144)`)
 * - Quick Fyr theme commands (`:dark`, `:light`, `:accent cyan`)
 */
object FyrSearchEvaluator {

    data class InlineAnswer(
        val title: String,
        val subtitle: String,
        val copyValue: String,
        val commandAction: String? = null
    )

    fun filterApps(apps: List<AppEntry>, rawQuery: String): List<AppEntry> {
        val q = rawQuery.trim().lowercase(Locale.getDefault())
        if (q.isEmpty() || q.startsWith(":") || q.startsWith("=")) return apps

        val scored = ArrayList<Pair<AppEntry, Int>>()
        for (app in apps) {
            val s = scoreAppMatch(app, q)
            if (s > 0) {
                scored.add(app to s)
            }
        }
        scored.sortWith(
            compareByDescending<Pair<AppEntry, Int>> { it.second }
                .thenByDescending { it.first.launchCount }
                .thenBy { it.first.label.lowercase(Locale.getDefault()) }
        )
        return scored.map { it.first }
    }

    fun scoreAppMatch(app: AppEntry, queryLower: String): Int {
        if (queryLower.isEmpty()) return 1
        val label = app.label.lowercase(Locale.getDefault())
        val pkg = app.packageName.lowercase(Locale.getDefault())

        if (label == queryLower) return 1000
        if (label.startsWith(queryLower)) return 800 - (label.length - queryLower.length).coerceAtMost(50)

        // Word-boundary or camel-case initials match
        val words = label.split(Regex("[\\s._-]+")).filter { it.isNotEmpty() }
        if (words.any { it.startsWith(queryLower) }) return 650
        val initials = words.map { it.first() }.joinToString("")
        if (initials.startsWith(queryLower)) return 600

        val containsIdx = label.indexOf(queryLower)
        if (containsIdx >= 0) return 500 - containsIdx.coerceAtMost(40)

        if (pkg.contains(queryLower)) return 250

        // Subsequence fuzzy match
        var qi = 0
        for (ch in label) {
            if (qi < queryLower.length && ch == queryLower[qi]) {
                qi++
            }
        }
        return if (qi == queryLower.length) 120 else 0
    }

    fun evaluateInlineQuery(rawQuery: String): InlineAnswer? {
        val trimmed = rawQuery.trim()
        if (trimmed.isEmpty()) return null

        // Check quick Fyr launcher theme commands
        val lower = trimmed.lowercase(Locale.getDefault())
        if (lower == ":dark" || lower == "!dark") {
            return InlineAnswer("Switch to Dark Mode", "Fyr Theme Command", "dark", "theme:dark")
        }
        if (lower == ":light" || lower == "!light") {
            return InlineAnswer("Switch to Light Mode", "Fyr Theme Command", "light", "theme:light")
        }
        if (lower.startsWith(":accent ") || lower.startsWith("!accent ")) {
            val arg = lower.substringAfter(" ").trim()
            return InlineAnswer(
                "Set Fyr Accent: ${arg.replaceFirstChar { it.uppercase() }}",
                "Fyr Theme Command",
                arg,
                "accent:$arg"
            )
        }

        // Math expression evaluation
        val mathCandidate = if (trimmed.startsWith("=")) trimmed.substring(1).trim() else trimmed
        if (looksLikeMath(mathCandidate)) {
            val result = evaluateMath(mathCandidate)
            if (result != null && result.isFinite()) {
                val formatted = formatNumber(result)
                return InlineAnswer(
                    title = "= $formatted",
                    subtitle = "$mathCandidate • Tap to copy result",
                    copyValue = formatted
                )
            }
        }
        return null
    }

    private fun looksLikeMath(expr: String): Boolean {
        if (expr.isEmpty()) return false
        val hasDigit = expr.any { it.isDigit() }
        val hasOp = expr.any { it in charArrayOf('+', '-', '*', '/', '%', '^', '(') } ||
            expr.startsWith("sqrt(") || expr.startsWith("sin(") || expr.startsWith("cos(")
        if (!hasDigit || !hasOp) return false
        return expr.all {
            it.isDigit() || it.isWhitespace() ||
                it in charArrayOf('+', '-', '*', '/', '%', '^', '(', ')', '.') ||
                it.lowercaseChar() in 'a'..'z'
        }
    }

    private fun formatNumber(value: Double): String {
        val rounded = value.roundToLong()
        return if (kotlin.math.abs(value - rounded.toDouble()) < 1e-9) {
            rounded.toString()
        } else {
            String.format(Locale.US, "%.6f", value).trimEnd('0').trimEnd('.')
        }
    }

    /**
     * Recursive-descent arithmetic parser supporting +, -, *, /, %, ^, parentheses, and functions.
     */
    fun evaluateMath(expression: String): Double? {
        return try {
            val parser = MathParser(expression.replace(" ", "").lowercase(Locale.US))
            val res = parser.parseExpression()
            if (parser.pos < parser.input.length) null else res
        } catch (_: Exception) {
            null
        }
    }

    private class MathParser(val input: String) {
        var pos: Int = 0

        private fun peek(): Char = if (pos < input.length) input[pos] else '\u0000'

        private fun eat(ch: Char): Boolean {
            if (peek() == ch) {
                pos++
                return true
            }
            return false
        }

        fun parseExpression(): Double {
            var x = parseTerm()
            while (true) {
                when {
                    eat('+') -> x += parseTerm()
                    eat('-') -> x -= parseTerm()
                    else -> return x
                }
            }
        }

        private fun parseTerm(): Double {
            var x = parsePower()
            while (true) {
                when {
                    eat('*') -> x *= parsePower()
                    eat('/') -> {
                        val denom = parsePower()
                        if (denom == 0.0) throw ArithmeticException("Division by zero")
                        x /= denom
                    }
                    eat('%') -> x %= parsePower()
                    else -> return x
                }
            }
        }

        private fun parsePower(): Double {
            var x = parseFactor()
            if (eat('^')) {
                x = x.pow(parsePower())
            }
            return x
        }

        private fun parseFactor(): Double {
            if (eat('+')) return parseFactor()
            if (eat('-')) return -parseFactor()

            val start = pos
            var x: Double
            if (eat('(')) {
                x = parseExpression()
                if (!eat(')')) throw IllegalArgumentException("Missing closing parenthesis")
                return x
            }

            if (peek().isDigit() || peek() == '.') {
                while (peek().isDigit() || peek() == '.') pos++
                return input.substring(start, pos).toDouble()
            }

            if (peek().isLetter()) {
                while (peek().isLetter()) pos++
                val fn = input.substring(start, pos)
                if (fn == "pi") return Math.PI
                if (fn == "e") return Math.E
                if (!eat('(')) throw IllegalArgumentException("Expected '(' after function")
                val arg = parseExpression()
                if (!eat(')')) throw IllegalArgumentException("Missing ')'")
                return when (fn) {
                    "sqrt" -> sqrt(arg)
                    "sin" -> sin(arg)
                    "cos" -> cos(arg)
                    else -> throw IllegalArgumentException("Unknown function: $fn")
                }
            }

            throw IllegalArgumentException("Unexpected token at $pos")
        }
    }
}
