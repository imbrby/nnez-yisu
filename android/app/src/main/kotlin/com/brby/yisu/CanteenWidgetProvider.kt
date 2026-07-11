package com.brby.yisu

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

enum class WidgetKind { BALANCE, OVERVIEW, ENDURANCE }

private data class WidgetPalette(
    val background: Int,
    val foreground: Int,
    val muted: Int,
    val accent: Int,
    val rule: Int
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
            CanteenWidgetRenderer.update(
                context,
                appWidgetManager,
                appWidgetId,
                kind
            )
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        CanteenWidgetRenderer.update(
            context,
            appWidgetManager,
            appWidgetId,
            kind
        )
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
        val balance = prefs.getString("widget_balance", null) ?: "--"
        val todaySpend = prefs.getString("widget_today_spend", null) ?: "0.00"
        val estimatedDays = readInt(prefs, "widget_estimated_days", -1)
        val monthExpense = prefs.getString("widget_month_expense", null) ?: "0.00"
        val monthRecharge = prefs.getString("widget_month_recharge", null) ?: "0.00"
        val monthRecordCount = readInt(prefs, "widget_month_record_count", 0)
        val monthLabel = prefs.getString("widget_month_label", null) ?: "本月记录"
        val studentName = prefs.getString("widget_student_name", null).orEmpty()
        val updatedAt = prefs.getString("widget_updated_at", null) ?: "等待同步"
        val hideBalance = prefs.getBoolean("widget_hide_balance", false)
        val showStudentName = prefs.getBoolean("widget_show_student_name", true)
        val showTodaySpend = prefs.getBoolean("widget_show_today_spend", true)
        val palette = paletteFor(prefs.getString("widget_theme", "pine"))

        val layout = when (kind) {
            WidgetKind.BALANCE -> R.layout.canteen_widget
            WidgetKind.OVERVIEW -> R.layout.canteen_overview_widget
            WidgetKind.ENDURANCE -> R.layout.canteen_endurance_widget
        }
        val views = RemoteViews(context.packageName, layout)
        views.setInt(R.id.widget_root, "setBackgroundResource", palette.background)

        when (kind) {
            WidgetKind.BALANCE -> {
                views.setTextViewText(
                    R.id.tv_balance,
                    if (hideBalance) "••••" else "¥ $balance"
                )
                views.setTextColor(R.id.tv_balance, palette.foreground)
                views.setTextColor(R.id.tv_accent, palette.accent)
                views.setTextViewText(
                    R.id.tv_student_name,
                    if (showStudentName && studentName.isNotBlank()) {
                        "${studentName}的校园卡"
                    } else {
                        "一粟 · 校园卡"
                    }
                )
                views.setTextColor(R.id.tv_student_name, palette.muted)
                views.setTextViewText(R.id.tv_updated_at, updatedAt)
                views.setTextColor(R.id.tv_updated_at, palette.muted)
                views.setViewVisibility(
                    R.id.today_spend_group,
                    if (showTodaySpend) View.VISIBLE else View.GONE
                )
                views.setTextViewText(R.id.tv_today_spend, "¥ $todaySpend")
                views.setTextColor(R.id.tv_today_spend, palette.foreground)
                views.setTextColor(R.id.tv_today_label, palette.muted)
            }
            WidgetKind.OVERVIEW -> {
                views.setTextColor(R.id.tv_accent, palette.accent)
                views.setTextViewText(R.id.tv_month_label, monthLabel)
                views.setTextColor(R.id.tv_month_label, palette.foreground)
                views.setTextViewText(R.id.tv_updated_at, updatedAt)
                views.setTextColor(R.id.tv_updated_at, palette.muted)
                views.setTextViewText(R.id.tv_month_recharge, "¥ $monthRecharge")
                views.setTextColor(R.id.tv_month_recharge, palette.foreground)
                views.setTextColor(R.id.tv_month_recharge_label, palette.muted)
                views.setTextViewText(R.id.tv_month_expense, "¥ $monthExpense")
                views.setTextColor(R.id.tv_month_expense, palette.foreground)
                views.setTextColor(R.id.tv_month_expense_label, palette.muted)
                views.setTextViewText(R.id.tv_month_count, "$monthRecordCount 条")
                views.setTextColor(R.id.tv_month_count, palette.foreground)
                views.setTextColor(R.id.tv_month_count_label, palette.muted)
            }
            WidgetKind.ENDURANCE -> {
                views.setTextViewText(
                    R.id.tv_balance,
                    if (hideBalance) "余额 ••••" else "余额 ¥ $balance"
                )
                views.setTextColor(R.id.tv_endurance_label, palette.muted)
                views.setTextViewText(
                    R.id.tv_estimated_days,
                    if (estimatedDays >= 0) "$estimatedDays 天" else "-- 天"
                )
                views.setTextColor(R.id.tv_estimated_days, palette.foreground)
                views.setInt(R.id.widget_rule, "setBackgroundColor", palette.rule)
                views.setTextColor(R.id.tv_balance, palette.muted)
            }
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

    private fun paletteFor(theme: String?): WidgetPalette {
        return when (theme) {
            "grain" -> WidgetPalette(
                R.drawable.widget_background_grain,
                Color.rgb(107, 77, 22),
                Color.rgb(128, 111, 78),
                Color.rgb(45, 115, 93),
                Color.argb(51, 128, 111, 78)
            )
            "ink" -> WidgetPalette(
                R.drawable.widget_background_ink,
                Color.rgb(244, 238, 220),
                Color.rgb(184, 192, 186),
                Color.rgb(215, 173, 84),
                Color.argb(70, 184, 192, 186)
            )
            else -> WidgetPalette(
                R.drawable.widget_background,
                Color.rgb(23, 79, 67),
                Color.rgb(85, 112, 105),
                Color.rgb(201, 155, 60),
                Color.argb(51, 112, 128, 118)
            )
        }
    }
}
