package com.eylexander.lllearner

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.database.DatabaseUtils
import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

// The daily reminder: an alarm at the time chosen in the app's settings (set through
// MainActivity's "setReminder"), and again after a reboot. When it goes off, it reads
// user.db (the same file as lib/store.dart) to say how many reviews are due, and stays
// silent if the learner already practised today and nothing is due.
class Reminder : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        schedule(context) // the next one: alarms are one-shot
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) notify(context)
    }

    companion object {
        private fun prefs(c: Context) = c.getSharedPreferences("reminder", Context.MODE_PRIVATE)

        fun set(c: Context, on: Boolean, minutes: Int, db: String) {
            prefs(c).edit().putBoolean("on", on).putInt("minutes", minutes).putString("db", db).apply()
            schedule(c)
        }

        /** Next occurrence of the chosen time, within a 15-minute window (no exact-alarm permission needed). */
        fun schedule(c: Context) {
            val alarms = c.getSystemService(AlarmManager::class.java)
            val pending = PendingIntent.getBroadcast(
                c, 0, Intent(c, Reminder::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            alarms.cancel(pending)
            val p = prefs(c)
            if (!p.getBoolean("on", false)) return
            val minutes = p.getInt("minutes", 19 * 60)
            val at = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, minutes / 60)
                set(Calendar.MINUTE, minutes % 60)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
                if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_MONTH, 1)
            }
            alarms.setWindow(AlarmManager.RTC_WAKEUP, at.timeInMillis, 15 * 60 * 1000L, pending)
        }

        /** (reviews due in the current course, practised today), or null if user.db can't be read. */
        private fun progress(c: Context): Pair<Long, Boolean>? = try {
            SQLiteDatabase.openDatabase(prefs(c).getString("db", null)!!, null, SQLiteDatabase.OPEN_READONLY).use { db ->
                val state = JSONObject(DatabaseUtils.stringForQuery(db, "SELECT v FROM meta WHERE k = 'state'", null))
                val course = state.optString("course", "man")
                val due = DatabaseUtils.longForQuery(
                    db, "SELECT count(*) FROM progress WHERE key >= ? AND key < ? AND due <= ?",
                    arrayOf("$course:", "$course;", "${System.currentTimeMillis()}"),
                )
                val today = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(Date())
                due to (state.optString("lastDay") == today)
            }
        } catch (e: Exception) {
            null
        }

        private fun notify(c: Context) {
            val (due, practised) = progress(c) ?: (0L to false)
            if (practised && due == 0L) return
            val manager = c.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel("reminder", "Rappel quotidien", NotificationManager.IMPORTANCE_DEFAULT)
            )
            val open = PendingIntent.getActivity(
                c, 0, Intent(c, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE,
            )
            val title = when {
                due > 1 -> "$due révisions vous attendent"
                due == 1L -> "Une révision vous attend"
                else -> "Votre leçon du jour vous attend"
            }
            // Without the notification permission (Android 13+), this does nothing.
            manager.notify(
                1,
                Notification.Builder(c, "reminder")
                    .setSmallIcon(R.drawable.ic_notification)
                    .setContentTitle(title)
                    .setContentText("Quelques minutes suffisent pour entretenir votre série.")
                    .setContentIntent(open)
                    .setAutoCancel(true)
                    .build(),
            )
        }
    }
}
