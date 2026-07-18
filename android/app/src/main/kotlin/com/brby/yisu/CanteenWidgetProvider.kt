package com.brby.yisu

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray

enum class WidgetKind { BALANCE, OVERVIEW, ENDURANCE }

private data class WidgetPalette(
    val background: Int,
    val foreground: Int,
    val muted: Int,
    val accent: Int,
    val rule: Int,
    val meal: Int,
    val drink: Int,
    val snack: Int,
    val recharge: Int,
    val expense: Int,
    val mealBackground: Int,
    val drinkBackground: Int,
    val snackBackground: Int,
    val rechargeBackground: Int
)

private data class WidgetRecentRecord(
    val title: String,
    val subtitle: String,
    val amount: String,
    val isRecharge: Boolean,
    val category: String
)

abstract class BaseCanteenWidgetProvider(
    private val kind: WidgetKind
) : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        appWidgetIds.forEach { appWidgetId ->
            CanteenWidgetRenderer.update(context, appWidgetManager, appWidgetId, kind)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        CanteenWidgetRenderer.update(context, appWidgetManager, appWidgetId, kind)
    }
}

class CanteenWidgetProvider : BaseCanteenWidgetProvider(WidgetKind.BALANCE)

class CanteenOverviewWidgetProvider :
    BaseCanteenWidgetProvider(WidgetKind.OVERVIEW)

class CanteenEnduranceWidgetProvider :
    BaseCanteenWidgetProvider(WidgetKind.ENDURANCE)

private object CanteenWidgetRenderer {
    fun update(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        kind: WidgetKind
    ) {
        val prefs = HomeWidgetPlugin.getData(context)
        val palette = paletteFor(readString(prefs, "widget_theme", "pine"))
        val balance = readString(prefs, "widget_balance", "--")
        val todaySpend = readString(prefs, "widget_today_spend", "0.00")
        val estimatedDays = readInt(prefs, "widget_estimated_days", -1)
        val studentName = readString(prefs, "widget_student_name", "")
        val updatedAt = readString(prefs, "widget_updated_at", "等待同步")
        val hideBalance = readBoolean(prefs, "widget_hide_balance", false)
        val showStudentName = readBoolean(prefs, "widget_show_student_name", true)
        val showTodaySpend = readBoolean(prefs, "widget_show_today_spend", true)

        val layout = when (kind) {
            WidgetKind.BALANCE -> R.layout.canteen_widget
            WidgetKind.OVERVIEW -> R.layout.canteen_overview_widget
            WidgetKind.ENDURANCE -> R.layout.canteen_endurance_widget
        }
        val views = RemoteViews(context.packageName, layout)
        views.setInt(R.id.widget_root, "setBackgroundResource", palette.background)

        when (kind) {
            WidgetKind.BALANCE -> renderBalance(
                views = views,
                palette = palette,
                balance = balance,
                todaySpend = todaySpend,
                estimatedDays = estimatedDays,
                studentName = studentName,
                updatedAt = updatedAt,
                hideBalance = hideBalance,
                showStudentName = showStudentName,
                showTodaySpend = showTodaySpend
            )
            WidgetKind.ENDURANCE -> renderCategories(views, prefs, palette)
            WidgetKind.OVERVIEW -> renderOverview(
                views,
                prefs,
                palette,
                updatedAt,
                appWidgetManager.getAppWidgetOptions(appWidgetId)
            )
        }

        context.packageManager.getLaunchIntentForPackage(context.packageName)?.let { intent ->
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            val pendingIntent = PendingIntent.getActivity(
                context,
                appWidgetId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
        }
        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun renderBalance(
        views: RemoteViews,
        palette: WidgetPalette,
        balance: String,
        todaySpend: String,
        estimatedDays: Int,
        studentName: String,
        updatedAt: String,
        hideBalance: Boolean,
        showStudentName: Boolean,
        showTodaySpend: Boolean
    ) {
        views.setTextViewText(
            R.id.tv_student_name,
            if (showStudentName && studentName.isNotBlank()) studentName else "校园卡"
        )
        views.setTextViewText(R.id.tv_updated_at, updatedAt)
        views.setTextViewText(R.id.tv_balance, if (hideBalance) "••••" else "¥ $balance")
        views.setTextViewText(R.id.tv_today_spend, "¥$todaySpend")
        views.setTextViewText(
            R.id.tv_estimated_days_compact,
            if (estimatedDays >= 0) "$estimatedDays 天" else "-- 天"
        )
        views.setViewVisibility(
            R.id.today_spend_group,
            if (showTodaySpend) View.VISIBLE else View.GONE
        )
        views.setTextColor(R.id.tv_accent, palette.accent)
        views.setTextColor(R.id.tv_student_name, palette.muted)
        views.setTextColor(R.id.tv_updated_at, palette.muted)
        views.setTextColor(R.id.tv_balance, palette.foreground)
        views.setTextColor(R.id.tv_today_label, palette.muted)
        views.setTextColor(R.id.tv_today_spend, palette.foreground)
        views.setTextColor(R.id.tv_estimated_label, palette.muted)
        views.setTextColor(R.id.tv_estimated_days_compact, palette.foreground)
    }

    private fun renderCategories(
        views: RemoteViews,
        prefs: SharedPreferences,
        palette: WidgetPalette
    ) {
        views.setTextColor(R.id.tv_category_accent, palette.accent)
        views.setTextColor(R.id.tv_category_title, palette.foreground)
        setCategoryTile(
            views,
            R.id.category_meal_tile,
            R.id.category_meal_icon,
            R.id.category_meal_amount,
            R.drawable.ic_widget_meal,
            palette.mealBackground,
            palette.meal,
            readString(prefs, "widget_meal_amount", "0.00")
        )
        setCategoryTile(
            views,
            R.id.category_drink_tile,
            R.id.category_drink_icon,
            R.id.category_drink_amount,
            R.drawable.ic_widget_drink,
            palette.drinkBackground,
            palette.drink,
            readString(prefs, "widget_drink_amount", "0.00")
        )
        setCategoryTile(
            views,
            R.id.category_snack_tile,
            R.id.category_snack_icon,
            R.id.category_snack_amount,
            R.drawable.ic_widget_snack,
            palette.snackBackground,
            palette.snack,
            readString(prefs, "widget_snack_amount", "0.00")
        )
    }

    private fun setCategoryTile(
        views: RemoteViews,
        tileId: Int,
        iconId: Int,
        amountId: Int,
        iconResource: Int,
        backgroundResource: Int,
        color: Int,
        amount: String
    ) {
        views.setInt(tileId, "setBackgroundResource", backgroundResource)
        views.setImageViewResource(iconId, iconResource)
        views.setInt(iconId, "setColorFilter", color)
        views.setTextViewText(amountId, "¥$amount")
        views.setTextColor(amountId, color)
    }

    private fun renderOverview(
        views: RemoteViews,
        prefs: SharedPreferences,
        palette: WidgetPalette,
        updatedAt: String,
        options: Bundle
    ) {
        views.setTextColor(R.id.tv_accent, palette.accent)
        views.setTextColor(R.id.tv_recent_label, palette.foreground)
        views.setTextViewText(R.id.tv_updated_at, updatedAt)
        views.setTextColor(R.id.tv_updated_at, palette.muted)
        views.setTextViewText(
            R.id.tv_month_recharge,
            "¥${readString(prefs, "widget_month_recharge", "0.00")}"
        )
        views.setTextViewText(
            R.id.tv_month_expense,
            "¥${readString(prefs, "widget_month_expense", "0.00")}"
        )
        views.setTextViewText(
            R.id.tv_month_count,
            "${readInt(prefs, "widget_month_record_count", 0)}条"
        )
        listOf(
            R.id.tv_month_recharge_label,
            R.id.tv_month_expense_label,
            R.id.tv_month_count_label
        ).forEach { views.setTextColor(it, palette.muted) }
        listOf(
            R.id.tv_month_recharge,
            R.id.tv_month_expense,
            R.id.tv_month_count
        ).forEach { views.setTextColor(it, palette.foreground) }
        views.setInt(R.id.recent_rule, "setBackgroundColor", palette.rule)

        val records = parseRecentRecords(
            readString(prefs, "widget_recent_records", "[]")
        )
        val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)
        val availableRows = (3 + ((minHeight - 110).coerceAtLeast(0) / 32))
            .coerceIn(3, 8)
        renderRecentRows(views, records, availableRows, palette)
    }

    private fun renderRecentRows(
        views: RemoteViews,
        records: List<WidgetRecentRecord>,
        availableRows: Int,
        palette: WidgetPalette
    ) {
        val rowIds = intArrayOf(
            R.id.recent_row_1,
            R.id.recent_row_2,
            R.id.recent_row_3,
            R.id.recent_row_4,
            R.id.recent_row_5,
            R.id.recent_row_6,
            R.id.recent_row_7,
            R.id.recent_row_8
        )
        val iconIds = intArrayOf(
            R.id.recent_icon_1,
            R.id.recent_icon_2,
            R.id.recent_icon_3,
            R.id.recent_icon_4,
            R.id.recent_icon_5,
            R.id.recent_icon_6,
            R.id.recent_icon_7,
            R.id.recent_icon_8
        )
        val titleIds = intArrayOf(
            R.id.recent_title_1,
            R.id.recent_title_2,
            R.id.recent_title_3,
            R.id.recent_title_4,
            R.id.recent_title_5,
            R.id.recent_title_6,
            R.id.recent_title_7,
            R.id.recent_title_8
        )
        val subtitleIds = intArrayOf(
            R.id.recent_subtitle_1,
            R.id.recent_subtitle_2,
            R.id.recent_subtitle_3,
            R.id.recent_subtitle_4,
            R.id.recent_subtitle_5,
            R.id.recent_subtitle_6,
            R.id.recent_subtitle_7,
            R.id.recent_subtitle_8
        )
        val amountIds = intArrayOf(
            R.id.recent_amount_1,
            R.id.recent_amount_2,
            R.id.recent_amount_3,
            R.id.recent_amount_4,
            R.id.recent_amount_5,
            R.id.recent_amount_6,
            R.id.recent_amount_7,
            R.id.recent_amount_8
        )

        if (records.isEmpty()) {
            views.setViewVisibility(rowIds[0], View.VISIBLE)
            views.setImageViewResource(iconIds[0], R.drawable.ic_widget_receipt)
            views.setInt(iconIds[0], "setBackgroundResource", palette.rechargeBackground)
            views.setInt(iconIds[0], "setColorFilter", palette.muted)
            views.setTextViewText(titleIds[0], "暂无记录")
            views.setTextViewText(subtitleIds[0], "同步后显示最近余额变动")
            views.setTextViewText(amountIds[0], "")
            views.setTextColor(titleIds[0], palette.foreground)
            views.setTextColor(subtitleIds[0], palette.muted)
            for (index in 1 until rowIds.size) {
                views.setViewVisibility(rowIds[index], View.GONE)
            }
            return
        }

        for (index in rowIds.indices) {
            if (index >= availableRows || index >= records.size) {
                views.setViewVisibility(rowIds[index], View.GONE)
                continue
            }
            val record = records[index]
            val style = recordStyle(record, palette)
            views.setViewVisibility(rowIds[index], View.VISIBLE)
            views.setImageViewResource(iconIds[index], style.first)
            views.setInt(iconIds[index], "setBackgroundResource", style.second)
            views.setInt(iconIds[index], "setColorFilter", style.third)
            views.setTextViewText(titleIds[index], record.title)
            views.setTextViewText(subtitleIds[index], record.subtitle)
            views.setTextViewText(
                amountIds[index],
                if (record.isRecharge) "+¥${record.amount}" else "-¥${record.amount}"
            )
            views.setTextColor(titleIds[index], palette.foreground)
            views.setTextColor(subtitleIds[index], palette.muted)
            views.setTextColor(
                amountIds[index],
                if (record.isRecharge) palette.recharge else palette.expense
            )
        }
    }

    private fun recordStyle(
        record: WidgetRecentRecord,
        palette: WidgetPalette
    ): Triple<Int, Int, Int> {
        if (record.isRecharge) {
            return Triple(
                R.drawable.ic_widget_recharge,
                palette.rechargeBackground,
                palette.recharge
            )
        }
        return when (record.category) {
            "meal" -> Triple(
                R.drawable.ic_widget_meal,
                palette.mealBackground,
                palette.meal
            )
            "drink" -> Triple(
                R.drawable.ic_widget_drink,
                palette.drinkBackground,
                palette.drink
            )
            "snack" -> Triple(
                R.drawable.ic_widget_snack,
                palette.snackBackground,
                palette.snack
            )
            else -> Triple(
                R.drawable.ic_widget_receipt,
                palette.rechargeBackground,
                palette.muted
            )
        }
    }

    private fun parseRecentRecords(raw: String): List<WidgetRecentRecord> {
        return try {
            val array = JSONArray(raw)
            val records = mutableListOf<WidgetRecentRecord>()
            for (index in 0 until minOf(array.length(), 8)) {
                val item = array.optJSONObject(index) ?: continue
                records.add(
                    WidgetRecentRecord(
                        title = item.optString("title", "交易记录"),
                        subtitle = item.optString("subtitle", "--/-- --:--"),
                        amount = item.optString("amount", "0.00"),
                        isRecharge = item.optBoolean("isRecharge", false),
                        category = item.optString("category", "unknown")
                    )
                )
            }
            records
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun readString(
        prefs: SharedPreferences,
        key: String,
        fallback: String
    ): String = prefs.all[key]?.toString()?.takeIf { it.isNotBlank() } ?: fallback

    private fun readBoolean(
        prefs: SharedPreferences,
        key: String,
        fallback: Boolean
    ): Boolean {
        return when (val value = prefs.all[key]) {
            is Boolean -> value
            is String -> when (value.lowercase()) {
                "true" -> true
                "false" -> false
                else -> fallback
            }
            else -> fallback
        }
    }

    private fun readInt(
        prefs: SharedPreferences,
        key: String,
        fallback: Int
    ): Int {
        val value = prefs.all[key] ?: return fallback
        return when (value) {
            is Int -> value
            is Long -> value.coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt()
            is Number -> value.toInt()
            is String -> value.toIntOrNull() ?: fallback
            else -> fallback
        }
    }

    private fun paletteFor(theme: String): WidgetPalette {
        return when (theme) {
            "grain" -> WidgetPalette(
                background = R.drawable.widget_background_grain,
                foreground = Color.rgb(107, 77, 22),
                muted = Color.rgb(128, 111, 78),
                accent = Color.rgb(45, 115, 93),
                rule = Color.argb(51, 128, 111, 78),
                meal = Color.rgb(45, 115, 93),
                drink = Color.rgb(138, 101, 26),
                snack = Color.rgb(154, 90, 50),
                recharge = Color.rgb(46, 125, 50),
                expense = Color.rgb(181, 69, 62),
                mealBackground = R.drawable.widget_category_grain_meal,
                drinkBackground = R.drawable.widget_category_grain_drink,
                snackBackground = R.drawable.widget_category_grain_snack,
                rechargeBackground = R.drawable.widget_category_grain_recharge
            )
            "ink" -> WidgetPalette(
                background = R.drawable.widget_background_ink,
                foreground = Color.rgb(244, 238, 220),
                muted = Color.rgb(184, 192, 186),
                accent = Color.rgb(215, 173, 84),
                rule = Color.argb(70, 184, 192, 186),
                meal = Color.rgb(126, 200, 164),
                drink = Color.rgb(230, 193, 108),
                snack = Color.rgb(225, 150, 111),
                recharge = Color.rgb(126, 200, 164),
                expense = Color.rgb(239, 137, 125),
                mealBackground = R.drawable.widget_category_ink_meal,
                drinkBackground = R.drawable.widget_category_ink_drink,
                snackBackground = R.drawable.widget_category_ink_snack,
                rechargeBackground = R.drawable.widget_category_ink_recharge
            )
            else -> WidgetPalette(
                background = R.drawable.widget_background,
                foreground = Color.rgb(23, 79, 67),
                muted = Color.rgb(85, 112, 105),
                accent = Color.rgb(201, 155, 60),
                rule = Color.argb(51, 112, 128, 118),
                meal = Color.rgb(31, 111, 91),
                drink = Color.rgb(138, 101, 26),
                snack = Color.rgb(154, 90, 50),
                recharge = Color.rgb(46, 125, 50),
                expense = Color.rgb(181, 69, 62),
                mealBackground = R.drawable.widget_category_pine_meal,
                drinkBackground = R.drawable.widget_category_pine_drink,
                snackBackground = R.drawable.widget_category_pine_snack,
                rechargeBackground = R.drawable.widget_category_pine_recharge
            )
        }
    }
}
