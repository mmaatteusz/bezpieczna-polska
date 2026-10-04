package pl.bezpiecznapolska.bezpieczna_polska

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    private var notifications: MethodChannel? = null
    private val channels = mapOf(
        "bp_threats" to Pair("Zagrożenia", NotificationManager.IMPORTANCE_HIGH),
        "bp_warnings" to Pair("Ostrzeżenia", NotificationManager.IMPORTANCE_DEFAULT),
        "bp_information" to Pair("Informacyjne", NotificationManager.IMPORTANCE_LOW)
    )
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.getStringExtra("bp_event_id")?.let { id ->
            notifications?.invokeMethod("notificationOpened", id)
            intent.removeExtra("bp_event_id")
        }
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            channels.forEach { (id, info) -> manager.createNotificationChannel(NotificationChannel(id, info.first, info.second)) }
        }
        notifications = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pl.bezpiecznapolska/notifications")
        notifications!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialEventId" -> {
                    val id = intent.getStringExtra("bp_event_id")
                    intent.removeExtra("bp_event_id")
                    result.success(id)
                }
                "showForegroundNotification" -> {
                    if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        result.error("NOTIFICATIONS_DENIED", "Notification permission denied", null)
                    } else {
                        try {
                            val remaining = call.argument<String>("expiresAt")?.let { SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                                timeZone = TimeZone.getTimeZone("UTC")
                            }.parse(it)!!.time - System.currentTimeMillis() }
                            if (remaining != null && remaining <= 0) {
                                result.success(null)
                                return@setMethodCallHandler
                            }
                            val eventId = call.argument<String>("eventId")
                            val title = call.argument<String>("title") ?: "Bezpieczna Polska"
                            val body = call.argument<String>("body") ?: ""
                            val id = (eventId ?: call.argument<String>("messageId"))?.hashCode() ?: System.nanoTime().toInt()
                            val channelId = call.argument<String>("channelId")?.takeIf { channels.containsKey(it) } ?: "bp_information"
                            val tap = Intent(this, MainActivity::class.java)
                                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                                .setData(android.net.Uri.parse("bp://notification/$id"))
                            if (eventId != null) tap.putExtra("bp_event_id", eventId)
                            val pending = PendingIntent.getActivity(this, id, tap, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, channelId)
                                else Notification.Builder(this).setPriority(if (channelId == "bp_threats") Notification.PRIORITY_HIGH else if (channelId == "bp_warnings") Notification.PRIORITY_DEFAULT else Notification.PRIORITY_LOW)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && remaining != null) builder.setTimeoutAfter(remaining)
                            manager.notify(id, builder.setSmallIcon(R.drawable.ic_notification)
                                .setContentTitle(title).setContentText(body)
                                .setStyle(Notification.BigTextStyle().bigText(body))
                                .setContentIntent(pending).setAutoCancel(true).build())
                            result.success(null)
                        } catch (_: Exception) {
                            result.error("NOTIFICATION_FAILED", "Notification could not be displayed", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
