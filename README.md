# ntfy Flutter

A minimal, independent Android client for subscribing to ntfy topics, reading and publishing messages, storing a local feed, and receiving live messages through an Android foreground service. Topic setup uses one full URL such as `https://ntfy.sh/my-topic`; subscriptions may have a local display name without changing the server topic. It is not affiliated with the ntfy project and intentionally has no FCM, WorkManager, account sync, or routing framework.

## Requirements

- Flutter with Dart 3.13 or newer
- Android SDK 36
- Android 7.0 (API 24) or newer
- Java 17

## Build, test, and run

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
flutter run
```

The debug APK is written under `build/app/outputs/flutter-apk/`.

## Background delivery

Adding the first subscription imports existing messages with `since=all`, marks that import read, and then asks for Android notification permission. Imported and duplicate events do not create notifications. Live WebSocket messages are transactionally deduplicated in SQLite before a local notification is shown.

The app starts or restarts one low-importance foreground delivery service only after a visible action: a successful subscription, a visible unsubscribe that changes the saved streams, or returning to the foreground with saved subscriptions. The service owns one WebSocket per subscription, reconnects with bounded exponential delay, and stops when the last subscription is removed. Its ongoing notification is required by Android. **App settings → Listening notification** opens the Android channel settings where the user may minimize or block that channel while the service remains active; Android may still show it in the system active-apps area.

Android may recreate a service that the system kills, but **Force stop** in Android settings always prevents the app and service from running until the user opens the app again. Device vendors may impose additional battery restrictions. Automatic boot delivery is intentionally disabled; opening the app starts saved subscriptions again.

Anonymous self-hosted servers may use cleartext `http://`. Basic passwords and bearer tokens are accepted only for `https://` servers and are stored with Android-backed secure storage. Credentials are never placed in application logs.

## Local message retention

Auto-delete is local-only and never deletes messages from the ntfy server. The global default is **Never**. It can be changed to 1, 3, 6, or 12 hours; 1, 3, 10, or 30 days. Each topic may inherit the global default or override it, including an explicit **Never** override. Cleanup runs at startup, during reloads and incoming events, and every 15 minutes while the foreground delivery service is active.

Tapping a message notification, including one that launched a terminated app, opens the matching saved topic feed. If that subscription was removed, the tap opens the normal subscription list.

## Physical-device acceptance checklist

Use a physical Android 13+ device for the platform behavior that unit and widget tests cannot verify:

- [ ] Install the debug APK and add a unique test topic.
- [ ] Confirm the notification permission prompt appears only after the first subscription succeeds.
- [ ] Confirm imported history appears read and creates no notification.
- [ ] Publish a new message from another client while this app is foregrounded; confirm one feed row and one notification.
- [ ] Publish while this app is backgrounded and while its UI process has been removed from recents; confirm delivery continues with the ongoing service notification visible.
- [ ] Send the same event again or reconnect; confirm no duplicate row or notification.
- [ ] Tap a message notification with the app running, backgrounded, and terminated; confirm the matching topic feed opens.
- [ ] Test an anonymous self-hosted HTTP server and an authenticated HTTPS server.
- [ ] Remove subscriptions; confirm the service remains for remaining topics and stops after the last is removed.
- [ ] Force stop the app, publish a message, and confirm no delivery occurs until the app is opened again.
