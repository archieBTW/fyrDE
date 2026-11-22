package com.fyrde.fyrandroid

import com.fyrde.fyrandroid.model.AppEntry
import com.fyrde.fyrandroid.search.FyrSearchEvaluator
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FyrSearchEvaluatorTest {

    @Test
    fun evaluateMath_handlesArithmeticAndFunctions() {
        assertEquals(168.0, FyrSearchEvaluator.evaluateMath("24 * 7")!!, 1e-6)
        assertEquals(1080.0, FyrSearchEvaluator.evaluateMath("1920 / 16 * 9")!!, 1e-6)
        assertEquals(12.0, FyrSearchEvaluator.evaluateMath("sqrt(144)")!!, 1e-6)
        assertEquals(1024.0, FyrSearchEvaluator.evaluateMath("2 ^ 10")!!, 1e-6)
    }

    @Test
    fun evaluateInlineQuery_supportsCalculatorAndThemeCommands() {
        val calc = FyrSearchEvaluator.evaluateInlineQuery("48 * 2")
        assertNotNull(calc)
        assertEquals("96", calc!!.copyValue)

        val darkCmd = FyrSearchEvaluator.evaluateInlineQuery(":dark")
        assertNotNull(darkCmd)
        assertEquals("theme:dark", darkCmd!!.commandAction)
    }

    @Test
    fun filterApps_ranksExactAndPrefixMatchesFirst() {
        val apps = listOf(
            AppEntry("Calculator", "com.android.calculator2", "Calculator"),
            AppEntry("Calendar", "com.android.calendar", "CalendarActivity"),
            AppEntry("Camera", "com.android.camera", "Camera")
        )
        val filtered = FyrSearchEvaluator.filterApps(apps, "calc")
        assertTrue(filtered.isNotEmpty())
        assertEquals("Calculator", filtered.first().label)
    }
}
