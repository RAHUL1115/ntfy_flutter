# Full-screen alert research

Research date: 2026-08-21

## Conclusion

ntfy can offer a Samsung Calendar-style **lock-screen alert** for an explicitly
selected set of urgent messages, but it cannot guarantee a full-screen takeover
in every device state. On Android 14 and later, a granted full-screen-intent
(FSI) access produces a full-screen activity while the device is locked, off,
or showing its always-on display. While the device is unlocked, Android's
specified presentation is a persistent heads-up notification with emphasized
actions, not a forced activity takeover. If FSI access is denied, the system
uses a heads-up notification for about 60 seconds instead. The official Android
14 behavior matrix documents these outcomes for each display state and grant
state ([AOSP FSI limits](https://source.android.com/docs/core/permissions/fsi-limits#manual-tests)).

The generic ntfy client is not an alarm or calling app merely because a remote
message has an `urgent` tag or is posted as `CATEGORY_ALARM`. It therefore does
not qualify for Android 14+'s automatic FSI grant. Google Play permits other
use cases only after explicit user consent and a clear explanation, with use
limited to necessary high-priority alerts; the declaration remains subject to
Play review ([Play full-screen-intent policy](https://support.google.com/googleplay/android-developer/answer/16558241?hl=en-GB#full-screen-intent),
[Play Console requirements](https://support.google.com/googleplay/android-developer/answer/13392821?hl=en)).

The safest product shape is therefore the one already started in this repo:
off by default, selected by the user through explicit message tags, routed to
Android's Special App Access page when needed, and degraded to a maximum-
importance notification when access is unavailable. It should not be enabled
automatically for every high-priority ntfy message.

## Samsung Calendar visual target

The supplied [Samsung Calendar reference](https://preview.redd.it/samsung-calendar-detailed-notifications-on-lock-screen-not-v0-v1b7bga6eynf1.jpg?width=1080&crop=smart&auto=webp&s=e3786a255e1e9db2ded002986f941cd26a9cc2fd)
shows a lock-screen surface with:

- edge-to-edge blurred wallpaper;
- a centered event title, scheduled time, and countdown;
- `Details` and `Dismiss` actions; and
- a bottom control for adjusting and applying a snooze duration.

The standard FSI API does not provide a Samsung Calendar visual template. It
launches the app's supplied `PendingIntent`, so a third-party app can reproduce
the layout in its own activity but cannot require an OEM to reproduce Samsung's
system styling. Android explicitly reserves control of the unlocked, locked,
off-screen, and always-on-display presentations to System UI
([`Notification.Builder.setFullScreenIntent`](https://developer.android.com/reference/android/app/Notification.Builder#setFullScreenIntent(android.app.PendingIntent,%20boolean)),
[AOSP FSI limits](https://source.android.com/docs/core/permissions/fsi-limits#manual-tests)).

### Current repo comparison

`FullScreenAlertActivity` already provides the essential third-party
foundation: it turns the screen on, displays above the lock screen, shows the
message title/body/time, and offers `Dismiss` and `Open topic`. Its activity is
excluded from Recents and is launched only through the notification's FSI.

Differences from the supplied target are presentation and snooze behavior:

| Target | Current activity | Standard-app option |
| --- | --- | --- |
| Blurred wallpaper | Opaque dark background | Use an app-owned translucent/blurred treatment where supported; exact Samsung rendering is not portable. |
| Event title, scheduled time, countdown | Message title, body, static received time | Map ntfy fields to a centered urgent-alert hierarchy; a countdown needs a defined deadline, not only the received timestamp. |
| `Details` and `Dismiss` | `Open topic` and `Dismiss` | Relabel/rearrange existing actions. |
| Adjustable snooze | Not present | Requires a persisted snooze choice and a later notification delivery path. |

The visual shell can be changed independently of FSI eligibility. It will only
be shown when Android actually launches the activity; the fallback and unlocked
presentation remain system-owned notifications.

The current permission path is substantially complete: the manifest declares
FSI access, Android 14+ is checked with `canUseFullScreenIntent()`, settings can
open Special App Access, eligible notifications use a dedicated high-importance channel,
and denied access falls back without launching the activity. The remaining
product gaps are checking the channel's *effective* user-selected importance,
providing a clearer consent explanation before the settings handoff, completing
the Play Console declaration, and device acceptance across the display states.
The Samsung visual treatment, countdown semantics, and snooze behavior are
separate UI/product gaps rather than prerequisites for lock-screen launch.

## Platform requirements

### Permission and user control

Apps targeting Android 10 or later must declare
`android.permission.USE_FULL_SCREEN_INTENT`. On Android 14+, it is Special App
Access: the app checks `NotificationManager.canUseFullScreenIntent()` and, when
false, may open `Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT`. It cannot
grant itself access, and the user may later revoke it
([Android 14 behavior change](https://developer.android.com/about/versions/14/behavior-changes-14#secure-fsi),
[AOSP user-permission flow](https://source.android.com/docs/core/permissions/fsi-limits#user-permission)).

Google Play revokes the default grant on Android 14+ for apps whose core purpose
is not alarms or receiving phone/video calls. Since 2025-01-22, apps targeting
Android 14+ without approved alarm/call functionality must obtain the user's
permission and gracefully degrade when denied
([Play Console requirements](https://support.google.com/googleplay/android-developer/answer/13392821?hl=en)).

Android 13+ separately requires notification permission for ordinary ntfy
notifications. ntfy does not receive the self-managed-phone-call exemption
([notification runtime permission](https://developer.android.com/develop/ui/views/notifications/notification-permission)).

### Channel importance

An FSI can launch only when its notification channel has
`IMPORTANCE_HIGH` or higher
([`Notification.Builder.setFullScreenIntent`](https://developer.android.com/reference/android/app/Notification.Builder#setFullScreenIntent(android.app.PendingIntent,%20boolean))).
The repo's tag-eligible alerts use a dedicated full-screen-alert channel created
with `IMPORTANCE_HIGH`, so the initial channel configuration meets this
requirement without depending on the user's settings for ordinary maximum-
priority messages.

The user remains in control of that channel. After creation, the app cannot
programmatically restore its visual or audible behavior; it can inspect the
channel and direct the user to system channel settings
([notification-channel guidance](https://developer.android.com/develop/ui/views/notifications/channels#ReadChannel)).
Consequently, FSI access alone is insufficient when notifications are blocked
or the alert's channel has been downgraded.

### Display-state behavior on Android 14+

| FSI access | Unlocked | Locked, screen off, or AOD |
| --- | --- | --- |
| Granted | Persistent heads-up notification with emphasized actions | Launch the supplied full-screen activity |
| Denied | Heads-up notification for about 60 seconds | No activity; prominent heads-up presentation for about 60 seconds |

Source: [AOSP FSI manual-test matrix](https://source.android.com/docs/core/permissions/fsi-limits#manual-tests).
OEMs may style the surfaces differently, but an app should test against these
behavioral outcomes rather than require pixel-identical Samsung presentation.

## Alarm and exact-alarm distinction

`USE_FULL_SCREEN_INTENT`, `SCHEDULE_EXACT_ALARM`, and `USE_EXACT_ALARM` are
separate capabilities. Declaring or receiving user access to an exact-alarm
permission does not make an app automatically eligible for FSI, and labeling a
notification as `CATEGORY_ALARM` does not change the app's core function. This
is an inference from Android and Play documenting independent grants and
eligibility rules for the two permission families
([Android exact-alarm guidance](https://developer.android.com/develop/background-work/services/alarms),
[Play exact-alarm policy](https://support.google.com/googleplay/android-developer/answer/16558241?hl=en#exact-alarm),
[Play FSI requirements](https://support.google.com/googleplay/android-developer/answer/13392821?hl=en)).

If the proposed snooze control must re-alert at an exact user-selected minute,
that scheduling behavior needs a separate exact-alarm design and permission
review. `USE_EXACT_ALARM` is restricted by Play to core alarm/timer/calendar
functionality; `SCHEDULE_EXACT_ALARM` has broader use cases but requires user
access and is denied by default on most fresh Android 14 installations
([Android 14 exact-alarm changes](https://developer.android.com/about/versions/14/changes/schedule-exact-alarms),
[Play exact-alarm policy](https://support.google.com/googleplay/android-developer/answer/16558241?hl=en#exact-alarm)).

## Recommended follow-up scope

1. Keep full-screen alerts disabled by default and require user-selected tags.
2. Before enabling, explain that the feature interrupts the lock screen and
   direct Android 14+ users to Special App Access only after that explanation.
3. Check notification permission, effective channel importance, and
   `canUseFullScreenIntent()`; expose the appropriate system settings when any
   prerequisite is missing.
4. Preserve the maximum-importance notification with dismiss/open actions as
   the fallback. Do not promise a full-screen activity while the phone is
   unlocked.
5. Treat the Samsung-inspired visual redesign and snooze scheduling as separate
   work. Define what ntfy field supplies an alert deadline before adding a
   countdown, and decide whether snooze precision justifies exact-alarm access.
6. Complete the Play Console FSI declaration accurately; do not claim automatic
   alarm/call eligibility for generic pushed messages.

Device acceptance should cover Android 13 and Android 14+ with FSI access both
granted and denied, and should test unlocked, locked, screen-off, and AOD modes.
At least one Samsung device and one non-Samsung device are needed to separate
portable activity behavior from OEM-specific styling.
