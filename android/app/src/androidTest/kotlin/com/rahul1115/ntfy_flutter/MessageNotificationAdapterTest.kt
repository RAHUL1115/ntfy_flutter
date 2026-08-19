package com.rahul1115.ntfy_flutter

import android.Manifest
import android.app.NotificationManager
import android.content.ContextWrapper
import android.content.pm.PackageManager
import android.os.Build
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

    private fun request(priority: Int): Map<String, Any> = mapOf(
        "id" to priority,
        "subscriptionId" to 7,
        "eventId" to "event-$priority",
        "title" to "Alerts",
        "body" to "Message $priority",
        "priority" to listOf("min", "low", "normal", "high", "max")[priority - 1],
        "timestamp" to 1_787_000_000_000L,
    )

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
