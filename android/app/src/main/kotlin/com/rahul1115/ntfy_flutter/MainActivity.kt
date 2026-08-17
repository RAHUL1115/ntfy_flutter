package com.rahul1115.ntfy_flutter

import android.Manifest
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                    ),
                )
                else -> result.notImplemented()
            }
        }
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

    companion object {
        private const val NOTIFICATION_PERMISSION_REQUEST = 8001
    }
}
