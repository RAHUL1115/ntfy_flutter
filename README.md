# ntfy Flutter

Independent Flutter client for ntfy. It uses its own Android application ID
and SQLite database; it does not import or migrate data from the official app.
The current visual source of truth is [`docs/new_design`](docs/new_design).

The current implementation includes subscriptions, foreground/background
delivery, Android message notifications, notification policy, search,
publishing and managed attachments, retention, per-topic delivery, networking
and security settings, backup/restore, logging, and source-aligned utility/UI
surfaces. See the [parity status](docs/full-parity-status.md) and
[device acceptance checklist](docs/device-acceptance-checklist.md).

## Install and update

Download the latest signed Android APK from the
[GitHub releases page](https://github.com/RAHUL1115/ntfy_flutter/releases/latest).
The app's **Update app** menu item opens the same page so users can check for
and install new versions.

Report problems through the project's
[GitHub issues](https://github.com/RAHUL1115/ntfy_flutter/issues).

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

The real-server acceptance test is enabled by setting `NTFY_BIN` to a local
ntfy server executable. Android OS and ecosystem behavior is intentionally
finished with the device checklist after the non-device suite is green.
