package com.rahul1115.ntfy_flutter

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class UnifiedPushReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val token = intent.getStringExtra(EXTRA_TOKEN) ?: return
        val pending = goAsync()
        when (intent.action) {
            ACTION_REGISTER -> {
                val application = application(intent) ?: run {
                    pending.finish()
                    return
                }
                BackgroundListenerService.unifiedPush(
                    context,
                    "unifiedPushRegister",
                    mapOf("application" to application, "token" to token),
                    onSuccess = { values ->
                        val endpoint = values?.get("endpoint") as? String
                        if (endpoint == null) {
                            registrationFailed(context, application, token, "INTERNAL_ERROR")
                        } else {
                            send(context, application, ACTION_NEW_ENDPOINT, token) {
                                putExtra(EXTRA_ENDPOINT, endpoint)
                            }
                        }
                        pending.finish()
                    },
                    onError = {
                        registrationFailed(context, application, token, "NETWORK")
                        pending.finish()
                    },
                )
            }
            ACTION_UNREGISTER -> BackgroundListenerService.unifiedPush(
                context,
                "unifiedPushUnregister",
                mapOf("token" to token),
                onSuccess = { values ->
                    val application = values?.get("application") as? String
                        ?: application(intent)
                    if (application != null) {
                        send(context, application, ACTION_UNREGISTERED, token)
                    }
                    pending.finish()
                },
                onError = { pending.finish() },
            )
            else -> pending.finish()
        }
    }

    private fun application(intent: Intent): String? {
        if (Build.VERSION.SDK_INT >= 34) {
            sentFromPackage?.let { return it }
        }
        @Suppress("DEPRECATION")
        intent.getParcelableExtra<PendingIntent>(EXTRA_PENDING_INTENT)
            ?.creatorPackage?.let { return it }
        return intent.getStringExtra(EXTRA_APPLICATION)
    }

    private fun registrationFailed(
        context: Context,
        application: String,
        token: String,
        reason: String,
    ) = send(context, application, ACTION_REGISTRATION_FAILED, token) {
        putExtra(EXTRA_FAILED_REASON, reason)
    }

    private fun send(
        context: Context,
        application: String,
        action: String,
        token: String,
        configure: Intent.() -> Unit = {},
    ) {
        context.sendBroadcast(Intent(action).apply {
            `package` = application
            putExtra(EXTRA_TOKEN, token)
            configure()
        })
    }

    companion object {
        private const val ACTION_REGISTER = "org.unifiedpush.android.distributor.REGISTER"
        private const val ACTION_UNREGISTER = "org.unifiedpush.android.distributor.UNREGISTER"
        private const val ACTION_NEW_ENDPOINT = "org.unifiedpush.android.connector.NEW_ENDPOINT"
        private const val ACTION_REGISTRATION_FAILED =
            "org.unifiedpush.android.connector.REGISTRATION_FAILED"
        private const val ACTION_UNREGISTERED = "org.unifiedpush.android.connector.UNREGISTERED"
        private const val EXTRA_APPLICATION = "application"
        private const val EXTRA_PENDING_INTENT = "pi"
        private const val EXTRA_TOKEN = "token"
        private const val EXTRA_ENDPOINT = "endpoint"
        private const val EXTRA_FAILED_REASON = "reason"
    }
}
