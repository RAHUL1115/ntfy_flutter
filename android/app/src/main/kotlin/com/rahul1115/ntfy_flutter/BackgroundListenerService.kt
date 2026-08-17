package com.rahul1115.ntfy_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
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

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var engine: FlutterEngine
    private lateinit var channel: MethodChannel
    private var ready = false
    private var callInFlight = false
    private var refreshPending = false
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
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    handler.removeCallbacks(initializationFallback)
                    ready = true
                    isRunning = call.arguments as? Boolean ?: false
                    refreshCallbacks.toList().forEach { it.success() }
                    refreshCallbacks.clear()
                    result.success(null)
                    if (isRunning || stopPending || refreshPending) {
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
                    result.success(null)
                    tearDown()
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
            tearDown()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopPending = true
        } else if (ready) {
            refreshPending = true
        }
        dispatchPending()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacks(initializationFallback)
        handler.removeCallbacks(stopFallback)
        cancelRefreshFallback()
        if (::channel.isInitialized) channel.setMethodCallHandler(null)
        if (::engine.isInitialized) engine.destroy()
        if (instance === this) instance = null
        isRunning = false
        notificationPresent = false
        refreshCallbacks.forEach {
            it.error("Background listener stopped before refreshing.")
        }
        stoppedCallbacks.forEach { it.success() }
        refreshCallbacks.clear()
        stoppedCallbacks.clear()
        val restart = restartAfterStop
        super.onDestroy()
        if (restart) handler.post { startOrRefresh(applicationContext) }
    }

    private fun dispatchPending() {
        if (!ready || callInFlight) return
        when {
            stopPending -> {
                stopPending = false
                refreshPending = false
                callInFlight = true
                handler.removeCallbacks(stopFallback)
                handler.postDelayed(stopFallback, STOP_TIMEOUT_MS)
                channel.invokeMethod("stop", null, completion { tearDown() })
            }
            refreshPending -> {
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
                channel.invokeMethod("refresh", null, object : MethodChannel.Result {
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
            stoppedCallbacks.add(completion)
            return
        }
        refreshCallbacks.add(completion)
        refreshPending = true
        dispatchPending()
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
            .setSmallIcon(R.drawable.ic_background_listener)
            .setContentTitle(getString(R.string.background_listener_notification_title))
            .setContentIntent(openApp)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSound(null)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    companion object {
        const val CHANNEL_ID = "ntfy_background_listener"
        private const val RUNTIME_CHANNEL = "com.rahul1115.ntfy_flutter/background_runtime"
        private const val ACTION_REFRESH = "background.refresh"
        private const val ACTION_STOP = "background.stop"
        private const val NOTIFICATION_ID = 8
        private const val INITIALIZATION_TIMEOUT_MS = 10_000L
        private const val REFRESH_TIMEOUT_MS = 10_000L
        private const val STOP_TIMEOUT_MS = 5_000L

        @Volatile
        private var instance: BackgroundListenerService? = null
        private val pendingStartCallbacks = mutableListOf<Completion>()

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

        fun stop(context: Context, onStopped: () -> Unit) {
            instance?.let {
                it.requestStop(onStopped)
                return
            }
            context.stopService(Intent(context, BackgroundListenerService::class.java))
            onStopped()
        }

        fun notificationPresent(): Boolean = notificationPresent
    }
}
