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
    private val legacyChannelId = "bp_alerts"
    private val criticalChannelId = "bp_alerts_critical"
    private val warningChannelId = "bp_alerts_warning"
    private val infoChannelId = "bp_alerts_info"
    private lateinit var notificationsChannel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannels(
                listOf(
                    NotificationChannel(
                        legacyChannelId,
                        "Powiadomienia",
                        NotificationManager.IMPORTANCE_HIGH
                    ),
                    NotificationChannel(
                        criticalChannelId,
                        "Alerty krytyczne",
                        NotificationManager.IMPORTANCE_HIGH
                    ).apply {
                        description = "Najpilniejsze ostrzeżenia bezpieczeństwa"
                    },
                    NotificationChannel(
                        warningChannelId,
                        "Ostrzeżenia",
                        NotificationManager.IMPORTANCE_DEFAULT
                    ).apply {
                        description = "Ważne ostrzeżenia wymagające uwagi"
                    },
                    NotificationChannel(
                        infoChannelId,
                        "Informacje",
                        NotificationManager.IMPORTANCE_LOW
                    ).apply {
                        description = "Korekty, zakończenia i informacje o niższym priorytecie"
                    }
                )
            )
        }

        notificationsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "pl.bezpiecznapolska/notifications"
        )
        notificationsChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialNotificationTap" -> {
                    result.success(consumeNotificationTap(intent))
                }
                "showForegroundNotification" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                        PackageManager.PERMISSION_GRANTED
                    ) {
                        result.error(
                            "NOTIFICATIONS_DENIED",
                            "Notification permission denied",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    try {
                        val title = call.argument<String>("title") ?: "Bezpieczna Polska"
                        val body = call.argument<String>("body") ?: ""
                        val id = call.argument<String>("messageId")?.hashCode()
                            ?: System.nanoTime().toInt()
                        val eventId = call.argument<String>("eventId")
                        val kind = call.argument<String>("kind")
                        val category = call.argument<String>("category")
                        val selectedChannelId = safeChannelId(
                            call.argument<String>("channelId")
                        )
                        val launchIntent = Intent(this, MainActivity::class.java)
                            .addFlags(
                                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                    Intent.FLAG_ACTIVITY_SINGLE_TOP
                            )
                        if (!eventId.isNullOrBlank()) {
                            launchIntent.action =
                                "pl.bezpiecznapolska.OPEN_ALERT.$id"
                            launchIntent.putExtra("bp_event_id", eventId)
                            if (!kind.isNullOrBlank()) {
                                launchIntent.putExtra("bp_kind", kind)
                            }
                            if (!category.isNullOrBlank()) {
                                launchIntent.putExtra("bp_category", category)
                            }
                        }
                        val pending = PendingIntent.getActivity(
                            this,
                            id,
                            launchIntent,
                            PendingIntent.FLAG_UPDATE_CURRENT or
                                PendingIntent.FLAG_IMMUTABLE
                        )
                        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Notification.Builder(this, selectedChannelId)
                        } else {
                            Notification.Builder(this).apply {
                                priority = when (selectedChannelId) {
                                    criticalChannelId -> Notification.PRIORITY_HIGH
                                    warningChannelId -> Notification.PRIORITY_DEFAULT
                                    else -> Notification.PRIORITY_LOW
                                }
                                if (selectedChannelId != infoChannelId) {
                                    setDefaults(Notification.DEFAULT_ALL)
                                }
                            }
                        }
                        manager.notify(
                            id,
                            builder
                                .setSmallIcon(R.drawable.ic_notification)
                                .setContentTitle(title)
                                .setContentText(body)
                                .setStyle(Notification.BigTextStyle().bigText(body))
                                .setContentIntent(pending)
                                .setAutoCancel(true)
                                .build()
                        )
                        result.success(null)
                    } catch (_: Exception) {
                        result.error(
                            "NOTIFICATION_FAILED",
                            "Notification could not be displayed",
                            null
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val payload = consumeNotificationTap(intent)
        if (payload != null && ::notificationsChannel.isInitialized) {
            notificationsChannel.invokeMethod("notificationTap", payload)
        }
    }

    private fun safeChannelId(value: String?): String = when (value) {
        criticalChannelId -> criticalChannelId
        warningChannelId -> warningChannelId
        infoChannelId -> infoChannelId
        legacyChannelId -> legacyChannelId
        else -> warningChannelId
    }

    private fun consumeNotificationTap(source: Intent?): Map<String, String>? {
        val launchIntent = source ?: return null
        val eventId = launchIntent.getStringExtra("bp_event_id")
            ?.takeIf { it.isNotBlank() }
            ?: return null
        val payload = mutableMapOf("eventId" to eventId)
        launchIntent.getStringExtra("bp_kind")?.takeIf { it.isNotBlank() }?.let {
            payload["kind"] = it
        }
        launchIntent.getStringExtra("bp_category")?.takeIf { it.isNotBlank() }?.let {
            payload["category"] = it
        }
        launchIntent.removeExtra("bp_event_id")
        launchIntent.removeExtra("bp_kind")
        launchIntent.removeExtra("bp_category")
        return payload
    }
}
