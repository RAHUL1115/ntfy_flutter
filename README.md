# ntfy Flutter

Independent Flutter port of the ntfy Android client. It uses its own Android
application ID and SQLite database; it does not import or migrate data from the
official app.

The parity target is [`binwiederhier/ntfy-android`](https://github.com/binwiederhier/ntfy-android/)
at tag [`v1.25.2`](https://github.com/binwiederhier/ntfy-android/tree/v1.25.2).
References to the source or upstream app mean that fixed version, not its
moving default branch.

The current implementation includes subscriptions, foreground/background
delivery, Android message notifications, notification policy, search,
publishing and managed attachments, retention, per-topic delivery, networking
and security settings, backup/restore, logging, and source-aligned utility/UI
surfaces. See the [parity status](docs/full-parity-status.md) and
[device acceptance checklist](docs/device-acceptance-checklist.md).

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

The real-server acceptance test is enabled by setting `NTFY_BIN` to a local
ntfy server executable. Android OS and ecosystem behavior is intentionally
finished with the device checklist after the non-device suite is green.
