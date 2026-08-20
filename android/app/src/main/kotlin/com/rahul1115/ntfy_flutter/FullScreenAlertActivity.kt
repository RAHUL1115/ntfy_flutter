package com.rahul1115.ntfy_flutter

import android.app.Activity
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.text.DateFormat
import java.util.Date

class FullScreenAlertActivity : Activity() {
    private var notificationTag: String? = null
    private var notificationId = -1
    private var subscriptionId = -1
    private var eventId: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showAboveLockScreen()
        render(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        render(intent)
    }

    @Suppress("OVERRIDE_DEPRECATION")
    override fun onBackPressed() = dismissAlert()

    private fun showAboveLockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
    }

    private fun render(source: Intent) {
        notificationTag = source.getStringExtra(EXTRA_NOTIFICATION_TAG)
        notificationId = source.getIntExtra(EXTRA_NOTIFICATION_ID, -1)
        subscriptionId = source.getIntExtra(EXTRA_SUBSCRIPTION_ID, -1)
        eventId = source.getStringExtra(EXTRA_EVENT_ID)
        val title = source.getStringExtra(EXTRA_TITLE)
        val body = source.getStringExtra(EXTRA_BODY)
        val timestamp = source.getLongExtra(EXTRA_TIMESTAMP, 0)
        if (
            notificationTag == null || notificationId < 0 || subscriptionId < 0 ||
            eventId.isNullOrEmpty() || title.isNullOrEmpty() || body.isNullOrEmpty()
        ) {
            finish()
            return
        }
        setContentView(alertView(title, body, timestamp))
    }

    private fun alertView(title: String, body: String, timestamp: Long): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(24), dp(32), dp(24), dp(24))
            setBackgroundColor(BACKGROUND)
        }
        root.addView(
            LinearLayout(this).apply {
                gravity = Gravity.CENTER_VERTICAL
                addView(
                    ImageView(this@FullScreenAlertActivity).apply {
                        setImageResource(R.mipmap.ic_ntfy_launcher)
                        contentDescription = getString(R.string.full_screen_alert_app_icon)
                    },
                    LinearLayout.LayoutParams(dp(40), dp(40)),
                )
                addView(
                    text(getString(R.string.full_screen_alert_heading), 18f).apply {
                        setTypeface(typeface, Typeface.BOLD)
                    },
                    LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ).apply { marginStart = dp(12) },
                )
            },
        )
        root.addView(
            text(title, 30f).apply {
                id = R.id.full_screen_alert_title
                gravity = Gravity.CENTER
                maxLines = 3
                ellipsize = TextUtils.TruncateAt.END
                setTypeface(typeface, Typeface.BOLD)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    isAccessibilityHeading = true
                }
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(48) },
        )
        root.addView(
            ScrollView(this).apply {
                isFillViewport = true
                addView(
                    text(body, 20f).apply {
                        id = R.id.full_screen_alert_message
                        gravity = Gravity.CENTER
                    },
                    LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ),
                )
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ).apply {
                topMargin = dp(24)
                bottomMargin = dp(16)
            },
        )
        root.addView(
            text(
                DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(timestamp)),
                15f,
                SECONDARY,
            ).apply {
                id = R.id.full_screen_alert_time
                gravity = Gravity.CENTER
            },
        )
        root.addView(
            LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                addView(
                    alertButton(
                        R.id.full_screen_alert_dismiss,
                        getString(R.string.full_screen_alert_dismiss),
                        false,
                        ::dismissAlert,
                    ),
                    LinearLayout.LayoutParams(0, dp(56), 1f),
                )
                addView(
                    alertButton(
                        R.id.full_screen_alert_open,
                        getString(R.string.full_screen_alert_open),
                        true,
                        ::openTopic,
                    ),
                    LinearLayout.LayoutParams(0, dp(56), 1f).apply {
                        marginStart = dp(12)
                    },
                )
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(24) },
        )
        return root
    }

    private fun text(value: String, size: Float, color: Int = Color.WHITE) = TextView(this).apply {
        text = value
        textSize = size
        setTextColor(color)
    }

    private fun alertButton(
        viewId: Int,
        label: String,
        primary: Boolean,
        action: () -> Unit,
    ) = Button(this).apply {
        id = viewId
        text = label
        textSize = 16f
        isAllCaps = false
        contentDescription = label
        setTextColor(if (primary) Color.BLACK else Color.WHITE)
        backgroundTintList = ColorStateList.valueOf(
            if (primary) ACCENT else Color.TRANSPARENT,
        )
        background = GradientDrawable().apply {
            cornerRadius = dp(4).toFloat()
            setColor(if (primary) ACCENT else Color.TRANSPARENT)
            setStroke(dp(1), if (primary) ACCENT else OUTLINE)
        }
        setOnClickListener { action() }
    }

    private fun dismissAlert() {
        cancelNotification()
        finish()
    }

    private fun openTopic() {
        val event = eventId ?: return dismissAlert()
        cancelNotification()
        startActivity(MessageNotificationAdapter.launchIntent(this, subscriptionId, event))
        finish()
    }

    private fun cancelNotification() {
        val tag = notificationTag ?: return
        if (notificationId >= 0) {
            getSystemService(NotificationManager::class.java).cancel(tag, notificationId)
        }
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()

    companion object {
        const val EXTRA_NOTIFICATION_TAG = "fullScreenAlert.notificationTag"
        const val EXTRA_NOTIFICATION_ID = "fullScreenAlert.notificationId"
        const val EXTRA_SUBSCRIPTION_ID = "fullScreenAlert.subscriptionId"
        const val EXTRA_EVENT_ID = "fullScreenAlert.eventId"
        const val EXTRA_TITLE = "fullScreenAlert.title"
        const val EXTRA_BODY = "fullScreenAlert.body"
        const val EXTRA_TIMESTAMP = "fullScreenAlert.timestamp"

        private const val BACKGROUND = 0xff0b1210.toInt()
        private const val SECONDARY = 0xffb7c2be.toInt()
        private const val OUTLINE = 0xff7a8581.toInt()
        private const val ACCENT = 0xffffaaa5.toInt()

        fun pendingIntent(
            context: Context,
            notificationId: Int,
            notificationTag: String,
            subscriptionId: Int,
            eventId: String,
            title: String,
            body: String,
            timestamp: Long,
        ): PendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            Intent(context, FullScreenAlertActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(EXTRA_NOTIFICATION_TAG, notificationTag)
                putExtra(EXTRA_NOTIFICATION_ID, notificationId)
                putExtra(EXTRA_SUBSCRIPTION_ID, subscriptionId)
                putExtra(EXTRA_EVENT_ID, eventId)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_BODY, body)
                putExtra(EXTRA_TIMESTAMP, timestamp)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
