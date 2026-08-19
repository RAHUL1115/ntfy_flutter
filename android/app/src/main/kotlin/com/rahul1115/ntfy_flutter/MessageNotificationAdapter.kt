package com.rahul1115.ntfy_flutter

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.NotificationChannelGroup
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel

object MessageNotificationAdapter {
    const val CHANNEL_NAME = "com.rahul1115.ntfy_flutter/message_notifications"
    private const val EXTRA_SUBSCRIPTION_ID = "notification.subscriptionId"
    private const val EXTRA_EVENT_ID = "notification.eventId"
    private const val TAG_PREFIX = "ntfy:"

    private val pendingTaps = ArrayDeque<Map<String, Any>>()

    @Volatile
    private var visibleSubscriptionId: Int? = null

    @Volatile
    private var tapChannel: MethodChannel? = null

    fun configure(channel: MethodChannel, context: Context, handlesTaps: Boolean) {
        if (handlesTaps) tapChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "showNotification" -> {
                    @Suppress("UNCHECKED_CAST")
                    val request = call.arguments as? Map<String, Any>
                    result.success(request != null && show(context, request))
                }
                "isSubscriptionVisible" -> {
                    val subscriptionId = (call.arguments as? Number)?.toInt()
                    result.success(
                        subscriptionId != null && isSubscriptionVisible(subscriptionId),
                    )
                }
                "setVisibleSubscription" -> {
                    setVisibleSubscription((call.arguments as? Number)?.toInt())
                    result.success(null)
                }
                "takeNotificationTap" -> result.success(takeNotificationTap())
                "openNotificationSettings" -> {
                    val subscriptionId = (call.arguments as? Number)?.toInt()
                    openNotificationSettings(context, subscriptionId)
                    result.success(null)
                }
                "showConnectionAlert" -> {
                    @Suppress("UNCHECKED_CAST")
                    val request = call.arguments as? Map<String, Any>
                    result.success(request != null && showConnectionAlert(context, request))
                }
                "clearConnectionAlert" -> {
                    context.getSystemService(NotificationManager::class.java)
                        .cancel(CONNECTION_ALERT_ID)
                    result.success(null)
                }
                "cancelNotification" -> {
                    @Suppress("UNCHECKED_CAST")
                    val request = call.arguments as? Map<String, Any>
                    val subscriptionId = (request?.get("subscriptionId") as? Number)?.toInt()
                    val sequenceId = request?.get("sequenceId") as? String
                    if (subscriptionId != null && !sequenceId.isNullOrEmpty()) {
                        cancel(context, subscriptionId, sequenceId)
                    }
                    result.success(null)
                }
                "broadcastMessage" -> {
                    @Suppress("UNCHECKED_CAST")
                    val request = call.arguments as? Map<String, Any>
                    result.success(request != null && broadcastMessage(context, request))
                }
                "broadcastAction" -> {
                    @Suppress("UNCHECKED_CAST")
                    val request = call.arguments as? Map<String, Any>
                    result.success(request != null && broadcastAction(context, request))
                }
                else -> result.notImplemented()
            }
        }
    }

    fun detach(channel: MethodChannel) {
        if (tapChannel === channel) tapChannel = null
    }

    fun setVisibleSubscription(subscriptionId: Int?) {
        visibleSubscriptionId = subscriptionId
    }

    fun isSubscriptionVisible(subscriptionId: Int): Boolean =
        visibleSubscriptionId == subscriptionId

    fun show(context: Context, request: Map<String, Any>): Boolean {
        val id = (request["id"] as? Number)?.toInt() ?: return false
        val subscriptionId =
            (request["subscriptionId"] as? Number)?.toInt() ?: return false
        val eventId = request["eventId"] as? String ?: return false
        val sequenceId = request["sequenceId"] as? String ?: eventId
        val title = request["title"] as? String ?: return false
        val body = request["body"] as? String ?: return false
        val priority = request["priority"] as? String ?: return false
        val insistent = request["insistent"] as? Boolean ?: false
        val timestamp = (request["timestamp"] as? Number)?.toLong() ?: return false
        val customChannelGroup = request["channelId"] as? String
        val channelId = if (customChannelGroup == null) {
            channelId(priority) ?: return false
        } else {
            "$customChannelGroup-$priority"
        }
        if (isSubscriptionVisible(subscriptionId)) return false
        val manager = context.getSystemService(NotificationManager::class.java)
        if (!notificationsAllowed(context)) return false
        createChannels(context, manager)
        if (customChannelGroup != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelName = request["channelName"] as? String ?: customChannelGroup
            createChannels(context, manager, customChannelGroup, channelName)
        }

        val notificationId = notificationId(subscriptionId, sequenceId)
        val openTopic = PendingIntent.getActivity(
            context,
            notificationId,
            safeViewIntent(request["click"] as? String)
                ?: launchIntent(context, subscriptionId, eventId),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, channelId)
        } else {
            Notification.Builder(context)
        }
        val iconPath = request["iconPath"] as? String
        if (iconPath != null) {
            BitmapFactory.decodeFile(iconPath)?.let(builder::setLargeIcon)
        }
        (request["iconBytes"] as? ByteArray)?.let { bytes ->
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.let(builder::setLargeIcon)
        }
        builder
            .setSmallIcon(R.drawable.ic_background_listener)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(openTopic)
            .setWhen(timestamp)
            .setShowWhen(true)
            .setAutoCancel(true)
            .setOnlyAlertOnce(!insistent)
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setPriority(legacyPriority(priority))
            .addExtras(Bundle().apply {
                putInt(EXTRA_SUBSCRIPTION_ID, subscriptionId)
                putString(EXTRA_EVENT_ID, eventId)
            })
        addUserActions(
            context,
            builder,
            request["actions"] as? List<*>,
            subscriptionId,
            sequenceId,
        )
        if (insistent) {
            builder.setDeleteIntent(
                PendingIntent.getBroadcast(
                    context,
                    notificationId,
                    Intent(context, InsistentNotificationReceiver::class.java).apply {
                        putExtra("tag", notificationTag(subscriptionId, sequenceId))
                        putExtra("id", notificationId)
                    },
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
        }
        val notification = builder.build()
        if (insistent) {
            notification.flags = notification.flags or Notification.FLAG_INSISTENT
        }
        manager.notify(notificationTag(subscriptionId, sequenceId), notificationId, notification)
        return true
    }

    fun cancel(context: Context, subscriptionId: Int, sequenceId: String) {
        context.getSystemService(NotificationManager::class.java).cancel(
            notificationTag(subscriptionId, sequenceId),
            notificationId(subscriptionId, sequenceId),
        )
    }

    private fun addUserActions(
        context: Context,
        builder: Notification.Builder,
        values: List<*>?,
        subscriptionId: Int,
        sequenceId: String,
    ) {
        values.orEmpty().take(3).forEach { value ->
            @Suppress("UNCHECKED_CAST")
            val action = value as? Map<String, Any?> ?: return@forEach
            val id = action["id"] as? String ?: return@forEach
            val label = action["label"] as? String ?: return@forEach
            val type = (action["action"] as? String)?.lowercase() ?: return@forEach
            val intent = Intent(context, MessageActionReceiver::class.java).apply {
                putExtra("actionType", type)
                putExtra("url", action["url"] as? String)
                putExtra("method", action["method"] as? String)
                putExtra("body", action["body"] as? String)
                putExtra("intentAction", action["intent"] as? String)
                putExtra("value", action["value"] as? String)
                putExtra("clear", action["clear"] as? Boolean ?: false)
                putExtra("subscriptionId", subscriptionId)
                putExtra("sequenceId", sequenceId)
                putExtra("headers", stringMapJson(action["headers"]))
                putExtra("extras", stringMapJson(action["extras"]))
            }
            val pending = PendingIntent.getBroadcast(
                context,
                "$subscriptionId:$sequenceId:$id".hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            builder.addAction(Notification.Action.Builder(0, label, pending).build())
        }
    }

    private fun showConnectionAlert(context: Context, request: Map<String, Any>): Boolean {
        val server = request["server"] as? String ?: return false
        val threshold = (request["thresholdSeconds"] as? Number)?.toInt() ?: return false
        if (!notificationsAllowed(context)) return false
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CONNECTION_ALERT_CHANNEL_ID,
                    context.getString(R.string.connection_alert_channel),
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }
        val openApp = PendingIntent.getActivity(
            context,
            CONNECTION_ALERT_ID,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CONNECTION_ALERT_CHANNEL_ID)
        } else {
            Notification.Builder(context)
        }
        val minutes = (threshold / 60).coerceAtLeast(1)
        val text = "Unable to connect to $server for more than $minutes minutes. Check your network connection."
        manager.notify(
            CONNECTION_ALERT_ID,
            builder
                .setSmallIcon(R.drawable.ic_background_listener)
                .setContentTitle(context.getString(R.string.connection_alert_title))
                .setContentText(text)
                .setStyle(Notification.BigTextStyle().bigText(text))
                .setContentIntent(openApp)
                .setAutoCancel(true)
                .setCategory(Notification.CATEGORY_ERROR)
                .build(),
        )
        return true
    }

    private fun broadcastMessage(context: Context, request: Map<String, Any>): Boolean {
        val id = request["id"] as? String ?: return false
        val baseUrl = request["baseUrl"] as? String ?: return false
        val topic = request["topic"] as? String ?: return false
        val time = (request["time"] as? Number)?.toLong() ?: return false
        val priority = (request["priority"] as? Number)?.toInt() ?: return false
        val muted = request["muted"] as? Boolean ?: false
        val message = request["message"] as? String ?: ""
        val messageBytes = request["messageBytes"] as? ByteArray ?: message.toByteArray(Charsets.UTF_8)
        val tags = request["tags"] as? String ?: ""
        val tagsMap = tags.split(',')
            .filter(String::isNotEmpty)
            .mapIndexed { index, tag -> "${index + 1}=$tag" }
            .joinToString(",")
        context.sendBroadcast(Intent("io.heckel.ntfy.MESSAGE_RECEIVED").apply {
            putExtra("id", id)
            putExtra("base_url", baseUrl)
            putExtra("topic", topic)
            putExtra("time", time.toInt())
            putExtra("title", request["title"] as? String ?: "")
            putExtra("message", message)
            putExtra("message_bytes", messageBytes)
            putExtra("message_encoding", request["messageEncoding"] as? String ?: "")
            putExtra("content_type", request["contentType"] as? String ?: "")
            putExtra("tags", tags)
            putExtra("tags_map", tagsMap)
            putExtra("priority", priority)
            putExtra("click", request["click"] as? String ?: "")
            putExtra("muted", muted)
            putExtra("muted_str", muted.toString())
            putExtra("attachment_name", request["attachmentName"] as? String ?: "")
            putExtra("attachment_type", request["attachmentType"] as? String ?: "")
            putExtra("attachment_size", (request["attachmentSize"] as? Number)?.toLong() ?: 0L)
            putExtra("attachment_expires", (request["attachmentExpires"] as? Number)?.toLong() ?: 0L)
            putExtra("attachment_url", request["attachmentUrl"] as? String ?: "")
        })
        return true
    }

    private fun broadcastAction(context: Context, request: Map<String, Any>): Boolean {
        val requested = request["intent"] as? String
        val action = requested
            ?.takeIf { it.isNotBlank() && !it.contains('\n') && it.length <= 255 }
            ?: "io.heckel.ntfy.USER_ACTION"
        val broadcast = Intent(action)
        @Suppress("UNCHECKED_CAST")
        (request["extras"] as? Map<String, String>).orEmpty().forEach { (key, value) ->
            broadcast.putExtra(key, value)
        }
        context.sendBroadcast(broadcast)
        return true
    }

    fun launchIntent(context: Context, subscriptionId: Int, eventId: String): Intent =
        Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            data = Uri.Builder()
                .scheme("ntfy")
                .authority("notification")
                .appendPath(subscriptionId.toString())
                .appendPath(eventId)
                .build()
            putExtra(EXTRA_SUBSCRIPTION_ID, subscriptionId)
            putExtra(EXTRA_EVENT_ID, eventId)
        }

    fun safeViewIntent(value: String?): Intent? {
        if (value.isNullOrBlank()) return null
        val uri = try {
            Uri.parse(value)
        } catch (_: Exception) {
            return null
        }
        if (uri.scheme?.lowercase() !in SAFE_VIEW_SCHEMES) return null
        return Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    private fun stringMapJson(value: Any?): String {
        @Suppress("UNCHECKED_CAST")
        val map = value as? Map<String, String> ?: return "{}"
        return org.json.JSONObject(map).toString()
    }

    private fun notificationTag(subscriptionId: Int, sequenceId: String) =
        "$TAG_PREFIX$subscriptionId:$sequenceId"

    private fun notificationId(subscriptionId: Int, sequenceId: String) =
        "$subscriptionId:$sequenceId".hashCode() and Int.MAX_VALUE

    fun recordLaunchIntent(intent: Intent?) {
        if (intent == null || !intent.hasExtra(EXTRA_SUBSCRIPTION_ID)) return
        val subscriptionId = intent.getIntExtra(EXTRA_SUBSCRIPTION_ID, -1)
        val eventId = intent.getStringExtra(EXTRA_EVENT_ID)
        intent.removeExtra(EXTRA_SUBSCRIPTION_ID)
        intent.removeExtra(EXTRA_EVENT_ID)
        if (subscriptionId < 0 || eventId.isNullOrEmpty()) return
        synchronized(pendingTaps) {
            pendingTaps.addLast(
                mapOf("subscriptionId" to subscriptionId, "eventId" to eventId),
            )
        }
        tapChannel?.invokeMethod("notificationTapAvailable", null)
    }

    fun takeNotificationTap(): Map<String, Any>? = synchronized(pendingTaps) {
        if (pendingTaps.isEmpty()) null else pendingTaps.removeFirst()
    }

    fun notificationsAllowed(context: Context): Boolean {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.N ||
            context.getSystemService(NotificationManager::class.java).areNotificationsEnabled()
    }

    fun activeNotifications(context: Context): List<Map<String, Any>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return emptyList()
        return context.getSystemService(NotificationManager::class.java)
            .activeNotifications
            .filter { it.tag?.startsWith(TAG_PREFIX) == true }
            .mapNotNull { status ->
                val subscriptionId = status.notification.extras.getInt(
                    EXTRA_SUBSCRIPTION_ID,
                    -1,
                )
                val eventId = status.notification.extras.getString(EXTRA_EVENT_ID)
                if (subscriptionId < 0 || eventId.isNullOrEmpty()) return@mapNotNull null
                mapOf(
                    "subscriptionId" to subscriptionId,
                    "eventId" to eventId,
                    "channelId" to (status.notification.channelId ?: "legacy"),
                )
            }
    }

    private fun openNotificationSettings(context: Context, subscriptionId: Int?) {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            }
        } else {
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:${context.packageName}"),
            )
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    private fun channelId(priority: String): String? = when (priority) {
        "min" -> "ntfy-min"
        "low" -> "ntfy-low"
        "normal" -> "ntfy"
        "high" -> "ntfy-high"
        "max" -> "ntfy-max"
        else -> null
    }

    private fun legacyPriority(priority: String): Int = when (priority) {
        "min" -> Notification.PRIORITY_MIN
        "low" -> Notification.PRIORITY_LOW
        "high" -> Notification.PRIORITY_HIGH
        "max" -> Notification.PRIORITY_MAX
        else -> Notification.PRIORITY_DEFAULT
    }

    private fun createChannels(context: Context, manager: NotificationManager) {
        createChannels(context, manager, null, null)
    }

    private fun createChannels(
        context: Context,
        manager: NotificationManager,
        groupId: String?,
        groupName: String?,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (groupId != null) {
            manager.createNotificationChannelGroup(
                NotificationChannelGroup(groupId, groupName ?: groupId),
            )
        }
        fun id(priority: String, fallback: String): String =
            if (groupId == null) fallback else "$groupId-$priority"
        val channels = listOf(
            Triple(id("min", "ntfy-min"), R.string.message_channel_min, NotificationManager.IMPORTANCE_MIN),
            Triple(id("low", "ntfy-low"), R.string.message_channel_low, NotificationManager.IMPORTANCE_LOW),
            Triple(id("normal", "ntfy"), R.string.message_channel_default, NotificationManager.IMPORTANCE_DEFAULT),
            Triple(id("high", "ntfy-high"), R.string.message_channel_high, NotificationManager.IMPORTANCE_HIGH),
            Triple(id("max", "ntfy-max"), R.string.message_channel_max, NotificationManager.IMPORTANCE_HIGH),
        ).mapIndexed { index, (id, name, importance) ->
            NotificationChannel(id, context.getString(name), importance).apply {
                group = groupId
                if (index == 3 || index == 4) {
                    enableVibration(true)
                    vibrationPattern = if (index == 3) HIGH_VIBRATION else MAX_VIBRATION
                }
                if (index == 4) {
                    enableLights(true)
                    setBypassDnd(true)
                }
            }
        }
        manager.createNotificationChannels(channels)
    }

    private val HIGH_VIBRATION = longArrayOf(
        300, 100, 300, 100, 300, 100, 300, 2000,
    )
    private val MAX_VIBRATION = longArrayOf(
        300, 100, 300, 100, 300, 100, 300, 2000,
        300, 100, 300, 100, 300, 100, 300, 2000,
        300, 100, 300, 100, 300, 100, 300, 2000,
    )
    private const val CONNECTION_ALERT_CHANNEL_ID = "ntfy-connection-alert"
    private const val CONNECTION_ALERT_ID = 712301
    private val SAFE_VIEW_SCHEMES = setOf("http", "https", "mailto", "tel", "geo", "market")
}

class InsistentNotificationReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val tag = intent.getStringExtra("tag") ?: return
        val id = intent.getIntExtra("id", -1)
        if (id < 0) return
        context.getSystemService(NotificationManager::class.java).cancel(tag, id)
    }
}

class MessageActionReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.getStringExtra("actionType") == "http") {
            val pending = goAsync()
            Thread {
                try {
                    finish(context, intent, runHttp(intent))
                } finally {
                    pending.finish()
                }
            }.start()
            return
        }
        val success = when (intent.getStringExtra("actionType")) {
            "view" -> {
                val view = MessageNotificationAdapter.safeViewIntent(intent.getStringExtra("url"))
                if (view == null) false else try {
                    context.startActivity(view)
                    true
                } catch (_: Exception) {
                    false
                }
            }
            "copy" -> {
                val value = intent.getStringExtra("value") ?: ""
                val clipboard = context.getSystemService(android.content.ClipboardManager::class.java)
                clipboard.setPrimaryClip(android.content.ClipData.newPlainText("ntfy", value))
                true
            }
            "broadcast" -> sendBroadcast(context, intent)
            else -> false
        }
        finish(context, intent, success)
    }

    private fun sendBroadcast(context: Context, source: Intent): Boolean {
        val action = source.getStringExtra("intentAction")
            ?.takeIf { it.isNotBlank() && !it.contains('\n') && it.length <= 255 }
            ?: "io.heckel.ntfy.USER_ACTION"
        val broadcast = Intent(action)
        val extras = org.json.JSONObject(source.getStringExtra("extras") ?: "{}")
        extras.keys().forEach { key -> broadcast.putExtra(key, extras.optString(key)) }
        context.sendBroadcast(broadcast)
        return true
    }

    private fun runHttp(intent: Intent): Boolean {
        val value = intent.getStringExtra("url") ?: return false
        val uri = Uri.parse(value)
        if (uri.scheme?.lowercase() !in setOf("http", "https")) return false
        val connection = java.net.URL(value).openConnection() as? java.net.HttpURLConnection
            ?: return false
        return try {
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            val method = (intent.getStringExtra("method") ?: "POST").uppercase()
            if (!method.matches(Regex("[A-Z]{1,16}"))) return false
            connection.requestMethod = method
            val headers = org.json.JSONObject(intent.getStringExtra("headers") ?: "{}")
            headers.keys().forEach { key ->
                val valueForKey = headers.optString(key)
                if (!key.contains('\n') && !valueForKey.contains('\n')) {
                    connection.setRequestProperty(key, valueForKey)
                }
            }
            intent.getStringExtra("body")?.let { body ->
                connection.doOutput = true
                connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            }
            connection.responseCode in 200..299
        } catch (_: Exception) {
            false
        } finally {
            connection.disconnect()
        }
    }

    private fun finish(context: Context, intent: Intent, success: Boolean) {
        if (!success || !intent.getBooleanExtra("clear", false)) return
        val subscriptionId = intent.getIntExtra("subscriptionId", -1)
        val sequenceId = intent.getStringExtra("sequenceId") ?: return
        if (subscriptionId >= 0) {
            MessageNotificationAdapter.cancel(context, subscriptionId, sequenceId)
        }
    }
}
