package com.hirehub.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews

class ScheduleWidgetProvider : AppWidgetProvider() {
	override fun onUpdate(
		context: Context,
		appWidgetManager: AppWidgetManager,
		appWidgetIds: IntArray,
	) {
		appWidgetIds.forEach { appWidgetId ->
			updateWidget(context, appWidgetManager, appWidgetId)
		}
	}

	companion object {
		private const val PREFS_NAME = "hirehub_schedule_widget"
		private const val CELL_COUNT = 42

		fun saveSnapshot(context: Context, snapshot: Map<String, Any?>) {
			val cells = snapshot["cells"] as? List<*>
			val editor = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
				.putString("title", snapshot["title"]?.toString() ?: "My Schedule")
				.putString("subtitle", snapshot["subtitle"]?.toString() ?: "")
				.putString("monthTitle", snapshot["monthTitle"]?.toString() ?: "Schedule")
				.putString(
					"emptyMessage",
					snapshot["emptyMessage"]?.toString() ?: "No upcoming schedule items",
				)

			cells.orEmpty().take(CELL_COUNT).forEachIndexed { index, item ->
				val cell = item as? Map<*, *>
				editor
					.putString("cell_${index}_label", cell?.get("label")?.toString() ?: "")
					.putBoolean("cell_${index}_current", cell?.get("isCurrentMonth") == true)
					.putBoolean("cell_${index}_today", cell?.get("isToday") == true)
					.putBoolean("cell_${index}_working", cell?.get("isWorking") == true)
					.putBoolean("cell_${index}_vacation", cell?.get("isVacation") == true)
					.putBoolean("cell_${index}_reminder", cell?.get("hasReminder") == true)
					.putString("cell_${index}_date_title", cell?.get("dateTitle")?.toString() ?: "")
					.putString("cell_${index}_note", cell?.get("note")?.toString() ?: "")
			}

			for (index in (cells?.size ?: 0) until CELL_COUNT) {
				editor
					.remove("cell_${index}_label")
					.remove("cell_${index}_current")
					.remove("cell_${index}_today")
					.remove("cell_${index}_working")
					.remove("cell_${index}_vacation")
					.remove("cell_${index}_reminder")
					.remove("cell_${index}_date_title")
					.remove("cell_${index}_note")
			}

			editor.apply()
		}

		fun updateAllWidgets(context: Context) {
			val manager = AppWidgetManager.getInstance(context)
			val component = ComponentName(context, ScheduleWidgetProvider::class.java)
			manager.getAppWidgetIds(component).forEach { appWidgetId ->
				updateWidget(context, manager, appWidgetId)
			}
		}

		private fun updateWidget(
			context: Context,
			appWidgetManager: AppWidgetManager,
			appWidgetId: Int,
		) {
			val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
			val views = RemoteViews(context.packageName, R.layout.schedule_widget)

			views.setTextViewText(
				R.id.widget_month_title,
				prefs.getString("monthTitle", "Schedule"),
			)

			val rowIds = intArrayOf(
				R.id.widget_calendar_row_0,
				R.id.widget_calendar_row_1,
				R.id.widget_calendar_row_2,
				R.id.widget_calendar_row_3,
				R.id.widget_calendar_row_4,
				R.id.widget_calendar_row_5,
			)

			rowIds.forEach { rowId -> views.removeAllViews(rowId) }

			for (index in 0 until CELL_COUNT) {
				val cell = RemoteViews(context.packageName, R.layout.schedule_widget_day_cell)
				val isCurrentMonth = prefs.getBoolean("cell_${index}_current", false)
				val isToday = prefs.getBoolean("cell_${index}_today", false)
				val isWorking = prefs.getBoolean("cell_${index}_working", false)
				val isVacation = prefs.getBoolean("cell_${index}_vacation", false)
				val hasReminder = prefs.getBoolean("cell_${index}_reminder", false)
				val dateTitle = prefs.getString("cell_${index}_date_title", "") ?: ""
				val note = prefs.getString("cell_${index}_note", "") ?: ""

				cell.setTextViewText(
					R.id.widget_day_text,
					prefs.getString("cell_${index}_label", ""),
				)
				cell.setTextColor(R.id.widget_day_text, dayTextColor(isCurrentMonth, isToday, isWorking, isVacation))
				cell.setInt(
					R.id.widget_day_text,
					"setBackgroundResource",
					dayBackground(isToday, isWorking, isVacation),
				)
				cell.setViewVisibility(
					R.id.widget_day_dot,
					if (hasReminder) View.VISIBLE else View.GONE,
				)

				if (!isCurrentMonth) {
					cell.setViewVisibility(R.id.widget_day_dot, View.GONE)
				}

				cell.setOnClickPendingIntent(
					R.id.widget_day_cell,
					dayClickIntent(context, index, dateTitle, note),
				)

				views.addView(rowIds[index / 7], cell)
			}

			val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
				?: Intent(context, MainActivity::class.java)
			val pendingIntent = PendingIntent.getActivity(
				context,
				0,
				launchIntent,
				PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
			)
			views.setOnClickPendingIntent(R.id.schedule_widget_root, pendingIntent)

			appWidgetManager.updateAppWidget(appWidgetId, views)
		}

		private fun dayClickIntent(
			context: Context,
			index: Int,
			dateTitle: String,
			note: String,
		): PendingIntent {
			val intent = if (note.isNotBlank()) {
				Intent(context, ScheduleNoteDialogActivity::class.java).apply {
					putExtra(ScheduleNoteDialogActivity.EXTRA_DATE_TITLE, dateTitle)
					putExtra(ScheduleNoteDialogActivity.EXTRA_NOTE, note)
					flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
				}
			} else {
				context.packageManager.getLaunchIntentForPackage(context.packageName)
					?: Intent(context, MainActivity::class.java)
			}

			return PendingIntent.getActivity(
				context,
				10_000 + index,
				intent,
				PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
			)
		}

		private fun dayBackground(isToday: Boolean, isWorking: Boolean, isVacation: Boolean): Int =
			when {
				isToday -> R.drawable.schedule_widget_day_today
				isVacation -> R.drawable.schedule_widget_day_vacation
				isWorking -> R.drawable.schedule_widget_day_working
				else -> R.drawable.schedule_widget_day_clear
			}

		private fun dayTextColor(
			isCurrentMonth: Boolean,
			isToday: Boolean,
			isWorking: Boolean,
			isVacation: Boolean,
		): Int =
			when {
				isToday || isVacation -> Color.WHITE
				isWorking -> Color.rgb(76, 175, 80)
				isCurrentMonth -> Color.rgb(32, 36, 42)
				else -> Color.rgb(170, 170, 170)
			}
	}
}
