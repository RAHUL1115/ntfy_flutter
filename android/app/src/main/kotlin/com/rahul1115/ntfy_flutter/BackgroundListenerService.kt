package com.rahul1115.ntfy_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.AlarmManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class BackgroundListenerService : Service() {
    private data class Completion(
        val success: () -> Unit,
        val error: (String) -> Unit,
    )

    private data class UnifiedPushOperation(
        val method: String,
        val arguments: Map<String, String>,
        val success: (Map<*, *>?) -> Unit,
        val error: (String) -> Unit,
    )

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var engine: FlutterEngine
    private lateinit var channel: MethodChannel
    private lateinit var notificationChannel: MethodChannel
    private var ready = false
    private var callInFlight = false
    private var refreshPending = false
    private var reconnectPending = false
    private var stopPending = false
    private var tearingDown = false
    private var restartAfterStop = false
    private val refreshCallbacks = mutableListOf<Completion>()
    private val stoppedCallbacks = mutableListOf<Completion>()
    private val initializationFallback = Runnable {
        refreshCallbacks.toList().forEach {
            it.error("Background listener did not become ready.")
        }
        refreshCallbacks.clear()
        failUnifiedPushOperations("Background listener did not become ready.")
        tearDown()
    }
    private val stopFallback = Runnable { tearDown() }
    private var refreshFallback: Runnable? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        synchronized(pendingStartCallbacks) {
            refreshCallbacks.addAll(pendingStartCallbacks)
            pendingStartCallbacks.clear()
        }
        isRunning = true
        createNotificationChannel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification())
        }
        notificationPresent = true
        handler.postDelayed(initializationFallback, INITIALIZATION_TIMEOUT_MS)

        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)
        engine = FlutterEngine(applicationContext)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, RUNTIME_CHANNEL)
        notificationChannel = MethodChannel(
            engine.dartExecutor.binaryMessenger,
            MessageNotificationAdapter.CHANNEL_NAME,
        )
        MessageNotificationAdapter.configure(
            notificationChannel,
            this,
            handlesTaps = false,
        )
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    handler.removeCallbacks(initializationFallback)
                    ready = true
                    isRunning = call.arguments as? Boolean ?: false
                    refreshCallbacks.toList().forEach { it.success() }
                    refreshCallbacks.clear()
                    result.success(null)
                    if (isRunning || stopPending || refreshPending || hasUnifiedPushOperations()) {
                        dispatchPending()
                    } else {
                        tearDown()
                    }
                }
                "failed" -> {
                    handler.removeCallbacks(initializationFallback)
                    val message = call.arguments as? String
                        ?: "Background listener failed to initialize."
                    refreshCallbacks.toList().forEach { it.error(message) }
                    refreshCallbacks.clear()
                    failUnifiedPushOperations(message)
                    result.success(null)
                    tearDown()
                }
                "connectionState" -> {
                    updateConnectionState(call.arguments)
                    result.success(null)
                }
                "unifiedPushMessage" -> {
                    deliverUnifiedPushMessage(call.arguments)
                    result.success(null)
                }
                "scheduleReconnect" -> {
                    val epochMilliseconds = (call.arguments as? Number)?.toLong()
                    result.success(
                        epochMilliseconds != null && scheduleReconnect(epochMilliseconds),
                    )
                }
                "cancelReconnect" -> {
                    cancelReconnect()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(
                    loader.findAppBundlePath(),
                    "package:ntfy_flutter/background_listening.dart",
                    "backgroundMain",
                ),
            )
        } catch (error: Exception) {
            handler.removeCallbacks(initializationFallback)
            val message = error.message ?: "Background listener failed to initialize."
            refreshCallbacks.toList().forEach { it.error(message) }
            refreshCallbacks.clear()
            failUnifiedPushOperations(message)
            tearDown()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopPending = true
        } else if (intent?.action == ACTION_RECONNECT && ready) {
            reconnectPending = true
        } else if (intent?.action == ACTION_UP) {
            // The queued UnifiedPush operation is dispatched below.
        } else if (ready) {
            refreshPending = true
        }
        dispatchPending()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacks(initializationFallback)
        clearConnectionStates()
        isRunning = false
        notificationPresent = false
        refreshCallbacks.forEach {
            it.error("Background listener stopped before refreshing.")
        }
        stoppedCallbacks.forEach { it.success() }
        refreshCallbacks.clear()
        stoppedCallbacks.clear()
        val restart = restartAfterStop
        if (::notificationChannel.isInitialized) {
            MessageNotificationAdapter.detach(notificationChannel)
        }
        if (::channel.isInitialized) channel.setMethodCallHandler(null)
        if (::engine.isInitialized) engine.destroy()
        if (instance === this) instance = null
        super.onDestroy()
        if (restart) handler.post { startOrRefresh(applicationContext) }
    }

    private fun dispatchPending() {
        if (!ready || callInFlight) return
        when {
            stopPending -> {
                stopPending = false
                refreshPending = false
                reconnectPending = false
                callInFlight = true
                handler.removeCallbacks(stopFallback)
                handler.postDelayed(stopFallback, STOP_TIMEOUT_MS)
                channel.invokeMethod("stop", null, completion { tearDown() })
            }
            hasUnifiedPushOperations() -> {
                val operation = takeUnifiedPushOperation() ?: return
                callInFlight = true
                channel.invokeMethod(
                    operation.method,
                    operation.arguments,
                    object : MethodChannel.Result {
                        override fun success(result: Any?) {
                            callInFlight = false
                            val values = result as? Map<*, *>
                            isRunning = values?.get("active") as? Boolean ?: isRunning
                            operation.success(values)
                            if (!isRunning && !hasUnifiedPushOperations() && !refreshPending) {
                                tearDown()
                            } else {
                                dispatchPending()
                            }
                        }

                        override fun error(code: String, message: String?, details: Any?) {
                            callInFlight = false
                            operation.error(message ?: "UnifiedPush operation failed.")
                            dispatchPending()
                        }

                        override fun notImplemented() {
                            callInFlight = false
                            operation.error("UnifiedPush is unavailable.")
                            dispatchPending()
                        }
                    },
                )
            }
            reconnectPending || refreshPending -> {
                val method = if (reconnectPending) "reconnect" else "refresh"
                reconnectPending = false
                refreshPending = false
                callInFlight = true
                val fallback = Runnable {
                    if (!callInFlight || tearingDown) return@Runnable
                    callInFlight = false
                    refreshCallbacks.toList().forEach {
                        it.error("Background listener refresh timed out.")
                    }
                    refreshCallbacks.clear()
                    tearDown()
                }
                refreshFallback = fallback
                handler.postDelayed(fallback, REFRESH_TIMEOUT_MS)
                channel.invokeMethod(method, null, object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        cancelRefreshFallback()
                        if (tearingDown) return
                        isRunning = result as? Boolean ?: false
                        callInFlight = false
                        if (isRunning) {
                            refreshCallbacks.toList().forEach { it.success() }
                            refreshCallbacks.clear()
                            dispatchPending()
                        } else if (refreshPending) {
                            dispatchPending()
                        } else {
                            stoppedCallbacks.addAll(refreshCallbacks)
                            refreshCallbacks.clear()
                            tearDown()
                        }
                    }
                    override fun error(code: String, message: String?, details: Any?) {
                        cancelRefreshFallback()
                        if (tearingDown) return
                        refreshCallbacks.toList().forEach {
                            it.error(message ?: "Background listener refresh failed.")
                        }
                        refreshCallbacks.clear()
                        tearDown()
                    }
                    override fun notImplemented() {
                        cancelRefreshFallback()
                        if (tearingDown) return
                        refreshCallbacks.toList().forEach {
                            it.error("Background listener refresh is unavailable.")
                        }
                        refreshCallbacks.clear()
                        tearDown()
                    }
                })
            }
        }
    }

    private fun cancelRefreshFallback() {
        refreshFallback?.let(handler::removeCallbacks)
        refreshFallback = null
    }

    private fun completion(done: () -> Unit) = object : MethodChannel.Result {
        override fun success(result: Any?) = done()
        override fun error(code: String, message: String?, details: Any?) = done()
        override fun notImplemented() = done()
    }

    private fun tearDown() {
        if (tearingDown) return
        if (refreshPending || refreshCallbacks.isNotEmpty()) {
            restartAfterStop = true
            synchronized(pendingStartCallbacks) {
                pendingStartCallbacks.addAll(refreshCallbacks)
            }
            refreshCallbacks.clear()
            refreshPending = false
        }
        tearingDown = true
        handler.removeCallbacks(stopFallback)
        cancelRefreshFallback()
        notificationPresent = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun requestRefresh(completion: Completion) {
        if (tearingDown) {
            restartAfterStop = true
            synchronized(pendingStartCallbacks) {
                pendingStartCallbacks.add(completion)
            }
            return
        }
        refreshCallbacks.add(completion)
        refreshPending = true
        dispatchPending()
    }

    private fun requestReconnect() {
        reconnectPending = true
        dispatchPending()
    }

    private fun reconnectIntent(): PendingIntent = PendingIntent.getService(
        this,
        RECONNECT_REQUEST_CODE,
        Intent(this, BackgroundListenerService::class.java).setAction(ACTION_RECONNECT),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun scheduleReconnect(epochMilliseconds: Long): Boolean {
        val alarms = getSystemService(AlarmManager::class.java)
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            !alarms.canScheduleExactAlarms()
        ) return false
        alarms.setExactAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            epochMilliseconds,
            reconnectIntent(),
        )
        return true
    }

    private fun cancelReconnect() {
        getSystemService(AlarmManager::class.java).cancel(reconnectIntent())
    }

    private fun requestStop(onStopped: () -> Unit = {}) {
        stoppedCallbacks.add(Completion(onStopped) { onStopped() })
        stopPending = true
        handler.removeCallbacks(stopFallback)
        handler.postDelayed(stopFallback, STOP_TIMEOUT_MS)
        dispatchPending()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.background_listener_channel_name),
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                setShowBadge(false)
                setSound(null, null)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun notification(): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.drawable.ic_ntfy_notification)
            .setContentTitle(getString(R.string.background_listener_notification_title))
            .setContentIntent(openApp)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSound(null)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    private fun deliverUnifiedPushMessage(value: Any?) {
        val message = value as? Map<*, *> ?: return
        val application = message["application"] as? String ?: return
        val token = message["token"] as? String ?: return
        val bytes = message["message"] as? ByteArray ?: return
        sendBroadcast(Intent(ACTION_UP_MESSAGE).apply {
            `package` = application
            putExtra(EXTRA_UP_TOKEN, token)
            putExtra(EXTRA_UP_MESSAGE, bytes)
        })
    }

    companion object {
        const val CHANNEL_ID = "ntfy_background_listener"
        private const val RUNTIME_CHANNEL = "com.rahul1115.ntfy_flutter/background_runtime"
        private const val ACTION_REFRESH = "background.refresh"
        private const val ACTION_RECONNECT = "background.reconnect"
        private const val ACTION_STOP = "background.stop"
        private const val ACTION_UP = "background.unified_push"
        private const val ACTION_UP_MESSAGE = "org.unifiedpush.android.connector.MESSAGE"
        private const val EXTRA_UP_TOKEN = "token"
        private const val EXTRA_UP_MESSAGE = "message"
        private const val NOTIFICATION_ID = 8
        private const val RECONNECT_REQUEST_CODE = 9
        private const val INITIALIZATION_TIMEOUT_MS = 10_000L
        private const val REFRESH_TIMEOUT_MS = 10_000L
        private const val STOP_TIMEOUT_MS = 5_000L

        @Volatile
        private var instance: BackgroundListenerService? = null
        private val pendingStartCallbacks = mutableListOf<Completion>()
        private val pendingUnifiedPushOperations = mutableListOf<UnifiedPushOperation>()
        private const val PREFERENCES = "background_listener"
        private const val ENABLED = "enabled"
        private val connectionStates = mutableMapOf<String, Map<String, Any?>>()

        @Volatile
        var isRunning = false
            private set

        @Volatile
        private var notificationPresent = false

        fun startOrRefresh(
            context: Context,
            onRefreshed: () -> Unit = {},
            onError: (String) -> Unit = {},
        ) {
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                .edit().putBoolean(ENABLED, true).apply()
            val completion = Completion(onRefreshed, onError)
            instance?.let {
                it.requestRefresh(completion)
                return
            }
            synchronized(pendingStartCallbacks) {
                pendingStartCallbacks.add(completion)
            }
            val intent = Intent(context, BackgroundListenerService::class.java)
                .setAction(ACTION_REFRESH)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (error: Exception) {
                synchronized(pendingStartCallbacks) {
                    pendingStartCallbacks.remove(completion)
                }
                onError(error.message ?: "Could not start background listener.")
            }
        }

        fun unifiedPush(
            context: Context,
            method: String,
            arguments: Map<String, String>,
            onSuccess: (Map<*, *>?) -> Unit,
            onError: (String) -> Unit,
        ) {
            val operation = UnifiedPushOperation(method, arguments, onSuccess, onError)
            synchronized(pendingUnifiedPushOperations) {
                pendingUnifiedPushOperations.add(operation)
            }
            instance?.let { service ->
                service.handler.post { service.dispatchPending() }
                return
            }
            val intent = Intent(context, BackgroundListenerService::class.java)
                .setAction(ACTION_UP)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (error: Exception) {
                synchronized(pendingUnifiedPushOperations) {
                    pendingUnifiedPushOperations.remove(operation)
                }
                onError(error.message ?: "Could not start UnifiedPush.")
            }
        }

        private fun hasUnifiedPushOperations(): Boolean =
            synchronized(pendingUnifiedPushOperations) {
                pendingUnifiedPushOperations.isNotEmpty()
            }

        private fun takeUnifiedPushOperation(): UnifiedPushOperation? =
            synchronized(pendingUnifiedPushOperations) {
                if (pendingUnifiedPushOperations.isEmpty()) null
                else pendingUnifiedPushOperations.removeAt(0)
            }

        private fun failUnifiedPushOperations(message: String) {
            val operations = synchronized(pendingUnifiedPushOperations) {
                pendingUnifiedPushOperations.toList().also {
                    pendingUnifiedPushOperations.clear()
                }
            }
            operations.forEach { it.error(message) }
        }

        fun stop(context: Context, onStopped: () -> Unit) {
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                .edit().putBoolean(ENABLED, false).apply()
            instance?.let {
                it.requestStop(onStopped)
                return
            }
            context.stopService(Intent(context, BackgroundListenerService::class.java))
            onStopped()
        }

        fun notificationPresent(): Boolean = notificationPresent

        @Synchronized
        fun connectionStates(): List<Map<String, Any?>> = connectionStates.values.toList()

        @Synchronized
        private fun updateConnectionState(value: Any?) {
            val status = value as? Map<*, *> ?: return
            val server = status["server"] as? String ?: return
            if (status["error"] == "__removed__") {
                connectionStates.remove(server)
            } else {
                connectionStates[server] = status.entries.associate { it.key.toString() to it.value }
            }
        }

        @Synchronized
        private fun clearConnectionStates() = connectionStates.clear()

        fun isEnabled(context: Context): Boolean =
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                .getBoolean(ENABLED, false)

        fun forceReconnectIfRunning(context: Context): Boolean {
            if (!isEnabled(context)) return false
            instance?.let { service ->
                service.handler.post { service.requestReconnect() }
                return true
            }
            return false
        }
    }
}
