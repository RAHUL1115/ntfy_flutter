package com.rahul1115.ntfy_flutter

import android.Manifest
import android.app.NotificationManager
import android.app.Activity
import android.content.Intent
import android.content.ContextWrapper
import android.content.pm.PackageManager
import android.os.Build
import android.widget.Button
import android.widget.TextView
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class MessageNotificationAdapterTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val manager: NotificationManager
        get() = instrumentation.targetContext.getSystemService(NotificationManager::class.java)

    @Before
    fun setUp() {
        grantNotificationPermission()
        clear()
    }

    @After
    fun tearDown() {
        grantNotificationPermission()
        clear()
    }

    @Test
    fun testFivePrioritiesUseOfficialStyleChannelImportance() {
        assertEquals(
            R.mipmap.ic_ntfy_launcher,
            instrumentation.targetContext.applicationInfo.icon,
        )
        val expectedChannels = listOf("ntfy-min", "ntfy-low", "ntfy", "ntfy-high", "ntfy-max")
        val expectedImportance = listOf(
            NotificationManager.IMPORTANCE_MIN,
            NotificationManager.IMPORTANCE_LOW,
            NotificationManager.IMPORTANCE_DEFAULT,
            NotificationManager.IMPORTANCE_HIGH,
            NotificationManager.IMPORTANCE_HIGH,
        )

        expectedChannels.indices.forEach { index ->
            assertTrue(MessageNotificationAdapter.show(instrumentation.targetContext, request(index + 1)))
        }

        val notifications = awaitActiveNotifications(5)
        assertEquals(expectedChannels, notifications.map { it.notification.channelId })
        assertEquals(expectedImportance, expectedChannels.map { manager.getNotificationChannel(it).importance })
        assertTrue(
            notifications.all {
                it.notification.smallIcon.resId == R.drawable.ic_ntfy_notification
            },
        )
        assertTrue(notifications.all { it.notification.getLargeIcon() == null })
    }

    @Test
    fun testDeniedPermissionSkipsNotificationWithoutThrowing() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val deniedContext = object : ContextWrapper(instrumentation.targetContext) {
            override fun checkSelfPermission(permission: String): Int =
                if (permission == Manifest.permission.POST_NOTIFICATIONS) {
                    PackageManager.PERMISSION_DENIED
                } else {
                    super.checkSelfPermission(permission)
                }
        }

        assertFalse(MessageNotificationAdapter.notificationsAllowed(deniedContext))
        assertFalse(MessageNotificationAdapter.show(deniedContext, request(3)))
        assertTrue(manager.activeNotifications.none { it.tag?.startsWith("ntfy:") == true })
    }

    @Test
    fun testEligibleFullScreenAlertUsesIntentWhenAllowed() {
        assertEquals(
            PackageManager.PERMISSION_GRANTED,
            instrumentation.targetContext.packageManager.checkPermission(
                Manifest.permission.USE_FULL_SCREEN_INTENT,
                instrumentation.targetContext.packageName,
            ),
        )
        assertTrue(
            MessageNotificationAdapter.show(
                instrumentation.targetContext,
                request(1) + ("fullScreenEligible" to true),
                fullScreenAllowed = true,
            ),
        )

        val notification = awaitActiveNotifications(1).single().notification
        assertEquals("ntfy-max", notification.channelId)
        assertEquals(android.app.Notification.CATEGORY_ALARM, notification.category)
        assertTrue(notification.extras.getBoolean("notification.fullScreenEligible"))
        assertNotNull(notification.fullScreenIntent)
        assertEquals(2, notification.actions.size)
        assertEquals("Dismiss", notification.actions[0].title)
        assertEquals("Open topic", notification.actions[1].title)
    }

    @Test
    fun testDeniedFullScreenAccessKeepsMaximumImportanceFallback() {
        assertTrue(
            MessageNotificationAdapter.show(
                instrumentation.targetContext,
                request(1) + ("fullScreenEligible" to true),
                fullScreenAllowed = false,
            ),
        )

        val notification = awaitActiveNotifications(1).single().notification
        assertEquals("ntfy-max", notification.channelId)
        assertNull(notification.fullScreenIntent)
        assertEquals(2, notification.actions.size)
    }

    @Test
    fun testIneligibleNotificationHasNoFullScreenIntent() {
        assertTrue(MessageNotificationAdapter.show(instrumentation.targetContext, request(1)))

        assertNull(awaitActiveNotifications(1).single().notification.fullScreenIntent)
    }

    @Test
    fun testFullScreenActivityRendersAndDismissesExactNotification() {
        assertTrue(
            MessageNotificationAdapter.show(
                instrumentation.targetContext,
                request(1) + ("fullScreenEligible" to true),
                fullScreenAllowed = false,
            ),
        )
        val active = awaitActiveNotifications(1).single()
        val activity = startFullScreenActivity(active.tag, active.id)
        try {
            assertEquals(
                "A long urgent alert title",
                activity.findViewById<TextView>(R.id.full_screen_alert_title).text,
            )
            assertEquals(
                "A full message that needs immediate attention.",
                activity.findViewById<TextView>(R.id.full_screen_alert_message).text,
            )
            val dismiss = activity.findViewById<Button>(R.id.full_screen_alert_dismiss)
            assertTrue(dismiss.height >= dp(48))
            instrumentation.runOnMainSync { dismiss.performClick() }
            awaitNoNotification(active.tag)
            assertTrue(activity.isFinishing)
        } finally {
            if (!activity.isFinishing) activity.finish()
        }
    }

    @Test
    fun testFullScreenActivityOpenRoutesOnceAndCancelsNotification() {
        assertTrue(
            MessageNotificationAdapter.show(
                instrumentation.targetContext,
                request(1) + ("fullScreenEligible" to true),
                fullScreenAllowed = false,
            ),
        )
        val active = awaitActiveNotifications(1).single()
        val activity = startFullScreenActivity(active.tag, active.id)
        try {
            instrumentation.runOnMainSync {
                activity.findViewById<Button>(R.id.full_screen_alert_open).performClick()
            }
            awaitNoNotification(active.tag)
            val target = awaitNotificationTap()
            assertEquals(7, target?.get("subscriptionId"))
            assertEquals("event-1", target?.get("eventId"))
            assertNull(MessageNotificationAdapter.takeNotificationTap())
            assertTrue(activity.isFinishing)
        } finally {
            if (!activity.isFinishing) activity.finish()
        }
    }

    @Test
    fun testFullScreenActivityBackDismissesNotification() {
        assertTrue(
            MessageNotificationAdapter.show(
                instrumentation.targetContext,
                request(1) + ("fullScreenEligible" to true),
                fullScreenAllowed = false,
            ),
        )
        val active = awaitActiveNotifications(1).single()
        val activity = startFullScreenActivity(active.tag, active.id)
        try {
            instrumentation.runOnMainSync { activity.onBackPressed() }
            awaitNoNotification(active.tag)
            assertTrue(activity.isFinishing)
        } finally {
            if (!activity.isFinishing) activity.finish()
        }
    }

    @Test
    fun testTapPayloadIsDistinctAndConsumedOnce() {
        val request = request(4)
        assertTrue(MessageNotificationAdapter.show(instrumentation.targetContext, request))
        assertTrue(MessageNotificationAdapter.show(instrumentation.targetContext, request))
        val notification = manager.activeNotifications.single { it.tag?.startsWith("ntfy:") == true }
        assertNotNull(notification.notification.contentIntent)

        MessageNotificationAdapter.recordLaunchIntent(
            MessageNotificationAdapter.launchIntent(
                instrumentation.targetContext,
                7,
                "event-4",
            ),
        )
        val target = MessageNotificationAdapter.takeNotificationTap()

        assertEquals(7, target?.get("subscriptionId"))
        assertEquals("event-4", target?.get("eventId"))
        assertNull(MessageNotificationAdapter.takeNotificationTap())

        MessageNotificationAdapter.recordLaunchIntent(
            MessageNotificationAdapter.launchIntent(
                instrumentation.targetContext,
                8,
                "event-5",
            ),
        )
        val nextTarget = MessageNotificationAdapter.takeNotificationTap()
        assertEquals(8, nextTarget?.get("subscriptionId"))
        assertEquals("event-5", nextTarget?.get("eventId"))
        assertNull(MessageNotificationAdapter.takeNotificationTap())
    }

    @Test
    fun testSequenceUpdatesReplaceAndControlsCancelNotification() {
        val first = request(3) + mapOf(
            "eventId" to "update-1",
            "sequenceId" to "deployment",
            "body" to "Starting",
            "actions" to listOf(
                mapOf(
                    "id" to "copy",
                    "action" to "copy",
                    "label" to "Copy",
                    "value" to "done",
                ),
            ),
        )
        val second = first + mapOf("eventId" to "update-2", "body" to "Finished")

        assertTrue(MessageNotificationAdapter.show(instrumentation.targetContext, first))
        assertTrue(MessageNotificationAdapter.show(instrumentation.targetContext, second))
        val active = awaitActiveNotifications(1).single()
        assertEquals("ntfy:7:deployment", active.tag)
        assertEquals("Finished", active.notification.extras.getString("android.text"))
        assertEquals("update-2", active.notification.extras.getString("notification.eventId"))
        assertEquals(1, active.notification.actions.size)

        MessageNotificationAdapter.cancel(instrumentation.targetContext, 7, "deployment")
        repeat(50) {
            if (manager.activeNotifications.none { it.tag == "ntfy:7:deployment" }) return
            Thread.sleep(20)
        }
        assertTrue(manager.activeNotifications.none { it.tag == "ntfy:7:deployment" })
    }

    @Test
    fun testNotificationsGroupByTopicUrlAndClearExactTopic() {
        val first = request(3) + mapOf("eventId" to "first", "sequenceId" to "first")
        val second = request(4) + mapOf("eventId" to "second", "sequenceId" to "second")
        val other = request(3) + mapOf(
            "subscriptionId" to 8,
            "eventId" to "other",
            "sequenceId" to "other",
            "topicUrl" to "https://example.com/alerts",
        )

        assertTrue(MessageNotificationAdapter.show(instrumentation.targetContext, first))
        assertTrue(MessageNotificationAdapter.show(instrumentation.targetContext, second))
        assertTrue(MessageNotificationAdapter.show(instrumentation.targetContext, other))

        val children = awaitActiveNotifications(3)
        val topicGroup = "ntfy-topic:https://ntfy.sh/alerts"
        val otherGroup = "ntfy-topic:https://example.com/alerts"
        assertEquals(2, children.count { it.notification.group == topicGroup })
        assertEquals(1, children.count { it.notification.group == otherGroup })
        val summaries = manager.activeNotifications.filter {
            it.notification.flags and android.app.Notification.FLAG_GROUP_SUMMARY != 0
        }
        assertEquals(2, summaries.size)
        assertTrue(summaries.all { it.notification.extras.getString("android.title") == "Alerts" })

        MessageNotificationAdapter.clearTopic(
            instrumentation.targetContext,
            "https://ntfy.sh/alerts",
        )

        repeat(50) {
            if (manager.activeNotifications.none {
                    it.notification.group == topicGroup
                }) return@repeat
            Thread.sleep(20)
        }
        assertTrue(manager.activeNotifications.none {
            it.notification.group == topicGroup
        })
        assertTrue(manager.activeNotifications.any {
            it.notification.group == otherGroup
        })
    }

    @Test
    fun testVisibleSubscriptionMatchIsExactAndClears() {
        MessageNotificationAdapter.setVisibleSubscription(7)

        assertTrue(MessageNotificationAdapter.isSubscriptionVisible(7))
        assertFalse(MessageNotificationAdapter.isSubscriptionVisible(8))
        assertFalse(MessageNotificationAdapter.show(instrumentation.targetContext, request(3)))
        assertTrue(
            MessageNotificationAdapter.show(
                instrumentation.targetContext,
                request(3) + ("subscriptionId" to 8),
            ),
        )

        MessageNotificationAdapter.setVisibleSubscription(null)
        assertFalse(MessageNotificationAdapter.isSubscriptionVisible(7))
    }

    @Test
    fun testMainActivityRequestsHighestSupportedRefreshRate() {
        val activity = instrumentation.startActivitySync(
            Intent(instrumentation.targetContext, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            },
        ) as MainActivity
        try {
            val expected = activity.windowManager.defaultDisplay.supportedRefreshRates.maxOrNull()
            assertEquals(expected, activity.window.attributes.preferredRefreshRate)
        } finally {
            activity.finish()
        }
    }

    private fun request(priority: Int): Map<String, Any> = mapOf(
        "id" to priority,
        "subscriptionId" to 7,
        "eventId" to "event-$priority",
        "topicUrl" to "https://ntfy.sh/alerts",
        "topicName" to "Alerts",
        "title" to "Alerts",
        "body" to "Message $priority",
        "priority" to listOf("min", "low", "normal", "high", "max")[priority - 1],
        "timestamp" to 1_787_000_000_000L,
    )

    private fun startFullScreenActivity(tag: String, id: Int): Activity =
        instrumentation.startActivitySync(
            Intent(instrumentation.targetContext, FullScreenAlertActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra(FullScreenAlertActivity.EXTRA_NOTIFICATION_TAG, tag)
                putExtra(FullScreenAlertActivity.EXTRA_NOTIFICATION_ID, id)
                putExtra(FullScreenAlertActivity.EXTRA_SUBSCRIPTION_ID, 7)
                putExtra(FullScreenAlertActivity.EXTRA_EVENT_ID, "event-1")
                putExtra(FullScreenAlertActivity.EXTRA_TITLE, "A long urgent alert title")
                putExtra(
                    FullScreenAlertActivity.EXTRA_BODY,
                    "A full message that needs immediate attention.",
                )
                putExtra(FullScreenAlertActivity.EXTRA_TIMESTAMP, 1_787_000_000_000L)
            },
        )

    private fun awaitNoNotification(tag: String) {
        repeat(50) {
            if (manager.activeNotifications.none { it.tag == tag }) return
            Thread.sleep(20)
        }
        assertTrue(manager.activeNotifications.none { it.tag == tag })
    }

    private fun awaitNotificationTap(): Map<String, Any>? {
        repeat(100) {
            MessageNotificationAdapter.takeNotificationTap()?.let { return it }
            Thread.sleep(20)
        }
        return null
    }

    private fun dp(value: Int) =
        (value * instrumentation.targetContext.resources.displayMetrics.density).toInt()

    private fun awaitActiveNotifications(count: Int) = run {
        var notifications = manager.activeNotifications
            .filter { it.tag?.startsWith("ntfy:") == true }
            .sortedBy { it.id }
        repeat(50) {
            if (notifications.size == count) return@run notifications
            Thread.sleep(20)
            notifications = manager.activeNotifications
                .filter { it.tag?.startsWith("ntfy:") == true }
                .sortedBy { it.id }
        }
        notifications
    }

    private fun grantNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            instrumentation.uiAutomation.grantRuntimePermission(
                instrumentation.targetContext.packageName,
                Manifest.permission.POST_NOTIFICATIONS,
            )
        }
    }

    private fun clear() {
        manager.cancelAll()
        while (MessageNotificationAdapter.takeNotificationTap() != null) {
            // Drain launch payloads left by a previous test.
        }
        MessageNotificationAdapter.setVisibleSubscription(null)
    }
}
