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

class MainActivity : FlutterActivity() {
    private val channelId = "bp_alerts"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(channelId, "Powiadomienia", NotificationManager.IMPORTANCE_HIGH)
            )
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pl.bezpiecznapolska/notifications")
            .setMethodCallHandler { call, result ->
                if (call.method != "showForegroundNotification") {
                    result.notImplemented()
                } else if (Build.VERSION.SDK_INT >= 33 &&
                    checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                    result.error("NOTIFICATIONS_DENIED", "Notification permission denied", null)
                } else {
                    try {
                        val title = call.argument<String>("title") ?: "Bezpieczna Polska"
                        val body = call.argument<String>("body") ?: ""
                        val id = call.argument<String>("messageId")?.hashCode()
                            ?: System.nanoTime().toInt()
                        val intent = Intent(this, MainActivity::class.java)
                            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        val pending = PendingIntent.getActivity(
                            this, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )
                        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Notification.Builder(this, channelId)
                        } else {
                            Notification.Builder(this)
                                .setPriority(Notification.PRIORITY_HIGH)
                                .setDefaults(Notification.DEFAULT_ALL)
                        }
                        manager.notify(id, builder
                            .setSmallIcon(R.drawable.ic_notification)
                            .setContentTitle(title)
                            .setContentText(body)
                            .setStyle(Notification.BigTextStyle().bigText(body))
                            .setContentIntent(pending)
                            .setAutoCancel(true)
                            .build())
                        result.success(null)
                    } catch (_: Exception) {
                        result.error("NOTIFICATION_FAILED", "Notification could not be displayed", null)
                    }
                }
            }
    }
}
