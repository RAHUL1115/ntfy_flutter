package dev.rahul.ntfy_flutter

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.rahul.ntfy_flutter/settings",
        ).setMethodCallHandler { call, result ->
            if (call.method != "openDeliveryNotificationSettings") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            startActivity(
                Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    putExtra(Settings.EXTRA_CHANNEL_ID, "ntfy_delivery")
                },
            )
            result.success(null)
        }
    }
}
