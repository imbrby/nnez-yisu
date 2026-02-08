package com.brby.yisu

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.app.PendingIntent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

class CanteenWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onEnabled(context: Context) {}

    override fun onDisabled(context: Context) {}

    companion object {
        private fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val prefs = HomeWidgetPlugin.getData(context)
            val balance = prefs.getString("widget_balance", null) ?: "--"
            val todaySpent = prefs.getString("widget_today_spent", null) ?: "--"

            val views = RemoteViews(context.packageName, R.layout.canteen_widget)
            views.setTextViewText(R.id.tv_balance, "¥ $balance")
            views.setTextViewText(R.id.tv_today_spent, "¥ $todaySpent")

            // Click to open app
            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (intent != null) {
                val pendingIntent = PendingIntent.getActivity(
                    context, 0, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
