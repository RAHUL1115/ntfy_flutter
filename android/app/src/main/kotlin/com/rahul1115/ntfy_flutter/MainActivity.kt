package com.rahul1115.ntfy_flutter

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val notificationPermissionResults = mutableListOf<MethodChannel.Result>()
    private lateinit var messageNotificationChannel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        messageNotificationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MessageNotificationAdapter.CHANNEL_NAME,
        )
        MessageNotificationAdapter.configure(messageNotificationChannel, this, handlesTaps = true)
        MessageNotificationAdapter.recordLaunchIntent(intent)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.rahul1115.ntfy_flutter/background_host",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startOrRefresh" -> BackgroundListenerService.startOrRefresh(
                    this,
                    onRefreshed = { result.success(null) },
                    onError = { message ->
                        result.error("background_start_failed", message, null)
                    },
                )
                "stop" -> BackgroundListenerService.stop(this) {
                    result.success(null)
                }
                "requestNotificationPermission" ->
                    requestNotificationPermission(result)
                "openChannelSettings" -> {
                    openChannelSettings()
                    result.success(null)
                }
                "status" -> result.success(
                    mapOf(
                        "running" to BackgroundListenerService.isRunning,
                        "notificationPresent" to
                            BackgroundListenerService.notificationPresent(),
                        "notificationsAllowed" to
                            MessageNotificationAdapter.notificationsAllowed(this),
                        "messageNotifications" to
                            MessageNotificationAdapter.activeNotifications(this),
                        "connections" to BackgroundListenerService.connectionStates(),
                    ),
                )
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.rahul1115.ntfy_flutter/system_settings",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setUnifiedPushEnabled" -> {
                    val enabled = call.arguments as? Boolean ?: false
                    setUnifiedPushEnabled(enabled)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        MessageNotificationAdapter.recordLaunchIntent(intent)
    }

    override fun onDestroy() {
        MessageNotificationAdapter.setVisibleSubscription(null)
        notificationPermissionResults.toList().forEach { it.success(false) }
        notificationPermissionResults.clear()
        if (::messageNotificationChannel.isInitialized) {
            MessageNotificationAdapter.detach(messageNotificationChannel)
        }
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        notificationPermissionResults.toList().forEach { it.success(granted) }
        notificationPermissionResults.clear()
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        notificationPermissionResults.add(result)
        if (notificationPermissionResults.size == 1) {
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST,
            )
        }
    }

    private fun openChannelSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                putExtra(
                    Settings.EXTRA_CHANNEL_ID,
                    BackgroundListenerService.CHANNEL_ID,
                )
            }
        } else {
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName"),
            )
        }
        startActivity(intent)
    }

    private fun setUnifiedPushEnabled(enabled: Boolean) {
        val state = if (enabled) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }
        packageManager.setComponentEnabledSetting(
            ComponentName(this, UnifiedPushReceiver::class.java),
            state,
            PackageManager.DONT_KILL_APP,
        )
    }

    companion object {
        private const val NOTIFICATION_PERMISSION_REQUEST = 8001
    }
}
