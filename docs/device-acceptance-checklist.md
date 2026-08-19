# Android device acceptance checklist

Use a clean install and an upgrade install on at least one Android 13+ device.
Where possible, repeat the visual/accessibility pass on a small phone and a
large-screen device. Record Android version, app build, server, and result in
the relevant issue before closing it.

## 2026-08-19 Genymotion basic smoke

Environment: Genymotion Phone, Android 15 / API 35, 570×1230 at 220 dpi,
release APK 0.1.0 (version code 1).

- [x] Corrected release APK installs, cold-launches, registers production
  plugins, and renders its persisted subscription list.
- [x] Persisted feed renders message cards, priority glyphs, offline/retrying
  state, connection-error action, notification state, and quick composer.
- [x] Topic search opens/closes; topic overflow exposes settings, clear, test,
  copy URL, and unsubscribe; topic settings expose inherited policies,
  delivery, retention, name, and URL.
- [x] Home overflow and the app settings hierarchy render; the add-subscription
  surface opens with disabled submit until valid input.
- [x] No app/Dart exception occurred during the corrected-build smoke pass.
  Genymotion emitted a non-fatal Impeller GLES shader-link warning.
- [ ] Notifications, publishing, attachments, external intents, localization
  switching, certificates, backup, broadcast, and UnifiedPush were not changed
  or exercised in this basic pass.
- [ ] Reboot, app relaunch/restart, force-stop, permission revocation, Doze,
  process death, and network transitions were intentionally not run per user
  instruction.

## 2026-08-19 Genymotion extended acceptance

Environment: the same Android 15 / API 35 virtual phone, corrected release APK,
three-button navigation, and notification permission granted unless the test
explicitly revoked it.

- [x] Foreground/background delivery, visible-feed suppression, all five
  priority channels, exact notification tap routing, permission denial/grant,
  airplane-mode recovery, process recreation, explicit service restart, app
  relaunch, and full virtual-device reboot passed without duplicate messages.
- [x] Per-topic background delivery now stops the topic's background listener.
  A max-priority message published while disabled produced no tray notification;
  opening the topic later fetched it into visible history.
- [x] Connected Android integration tests passed priority mapping,
  deduplication, visible-feed suppression, and two explicit service restart
  cycles, including a rapid stop/re-enable race. Native instrumentation passed
  5/5 when run individually: permission denial, five priority channels,
  visible-feed suppression, tap payload consumption, and sequence
  replacement/cancel. The combined runner triggered a Genymotion Android 15
  System UI renderer crash; the app process did not crash.
- [x] Priority-mode DND routing passed after temporary notification-policy
  access: max priority bypassed DND and normal priority was intercepted. Total
  silence intercepted both, as Android specifies. Policy access and DND were
  restored after the test.
- [x] A full Genymotion cold boot restored the background listener from
  `BOOT_COMPLETED` before the app was opened. A message published afterward was
  received once with the correct topic, event ID, title, body, and priority.
- [x] The UnifiedPush settings toggle enabled and disabled the Android receiver
  component. Independent client registration and delivery cannot be exercised
  because this emulator has no separate UnifiedPush client/distributor.
- [x] The complete settings surface is one scrollable page. General,
  Appearance, Backup & Restore, Advanced, and About are section headers, not an
  overlapped bottom navigation bar; all sections are reachable above the system
  navigation inset. Dark mode and the restore picker/cancel path passed.
- [x] Settings and feed remained usable at 1.3x font scale and in landscape;
  Android's accessibility tree exposed labels, actions, and switch states.
- [x] The opt-in real-server acceptance test passed against ntfy server 2.27.0,
  covering ingest, publish, persisted cursor resume, and reconnect.
- [ ] Genymotion does not have TalkBack installed. Actual audible sound,
  tactile vibration, notification LED output, OEM battery restrictions, and
  independent UnifiedPush interoperability remain outside emulator acceptance.
  DND routing and channel vibration/light configuration were verified through
  Android system state.
- [ ] Switching to Spanish translated the source-owned settings labels, but
  several port-specific background/dynamic-color descriptions intentionally
  fell back to English because the upstream Android catalogs have no matching
  translations. This difference still requires product approval or translated
  copy before claiming fully localized parity.

## 2026-08-19 Android Studio AVD acceptance

Environment: `flutter_api_36`, Google APIs Android 16 / API 36, x86_64,
1080x2400 at 420 dpi, release APK 0.1.0 (version code 1). The AVD used six
virtual CPUs and its existing 2 GB RAM configuration.

- [x] The release APK installed and launched on API 36 without an app fatal
  exception.
- [x] The bundled Google TalkBack service enabled and bound to ntfy. The home
  accessibility tree exposed meaningful labels for the page heading,
  notification state, overflow menu, topic rows, and add-subscription action.
  The only unlabeled focusable node was the non-clickable full-screen Flutter
  host container, not an actionable control.
- [ ] End-to-end spoken traversal is not accepted from this AVD. Android System
  UI repeatedly raised its own ANR while TalkBack and first-run Google services
  were active, including after increasing the guest from four to six CPUs.
  The host had insufficient free memory to safely raise the guest to 4 GB.
- [ ] This AVD uses disposable snapshot/data behavior for sideloaded apps, so
  its APK disappearance after an emulator restart is not valid evidence for or
  against application persistence. The Genymotion restart/reboot result remains
  the valid virtual-device result.

## Build and persistence

- [x] Install the release APK and confirm the independent application ID/name.
- [x] Add HTTP and HTTPS topics, restart the app, and confirm topics/messages/settings persist.
- [x] Upgrade over an older build and confirm the database migrates without data loss.
- [ ] Restore a valid backup into a clean install; reject malformed/version-incompatible backups without changing existing data.

Upgrade environment: Genymotion Android 15 / API 35. A populated 0.1.0+1
release installation was upgraded in place to a generated 0.1.1+2 release
build. The mTLS subscription, stored live/background messages, managed trusted
CA and client certificate/key profile, background-listening preference, and
connected stream all survived.

TLS environment: local ntfy 2.26.3 behind separate TLS and mTLS endpoints. The
app trusted the scoped self-signed CA, persisted a scoped client certificate
and private key, received a foreground message over mTLS, and received another
through the background service with the expected Android notification.

## Notifications and lifecycle (#9, #10, #13, #16)

- [ ] On Android 13+, enable background listening and verify the explanatory permission context, grant path, and denial path.
- [ ] Publish all five priorities and verify their channel importance, sound/vibration/light behavior, including DND behavior where allowed.
- [ ] Verify emoji tags, title/body, timestamp, topic icon, dedicated topic channel, minimum-priority filtering, snooze, and insistent max priority.
- [ ] Keep the matching feed visible: no tray notification. Cover it or open another topic: a notification appears.
- [ ] Tap a recent and an old/off-screen notification from foreground, background, and terminated states; the exact topic/message is revealed.
- [ ] Redeliver the same event and restart/reconnect; only one stored message and one system notification are produced.
- [ ] Exercise Wi-Fi/mobile/offline transitions, screen off/Doze, process death, service restart, device reboot, and force-stop semantics.
- [ ] Verify each per-topic delivery choice changes listener behavior and that disconnected alerts appear/clear at the configured threshold.

## Publishing and attachments (#15)

- [ ] Publish plain and advanced messages with every optional field and verify them in the official client/web app.
- [ ] Pick a local file, publish it, observe progress, cancel/retry, and verify the 50 MB validation path.
- [ ] Receive attachments below/above the automatic-download threshold; open cached and remote files with an appropriate Android app.
- [ ] Delete one message, clear a topic, unsubscribe, and run retention; confirm only the associated managed files are removed.

## Settings and integrations (#17)

- [ ] Exercise authenticated HTTP/HTTPS foreground and background connections, JSON/HTTP protocol selection, custom headers, a trusted self-signed certificate, and a client-certificate/key pair.
- [ ] Confirm secrets remain inaccessible to normal backup/export paths and invalid certificate/key pairs are rejected.
- [ ] Switch light/dark/system, dynamic colors, language, and message-bar visibility; restart after each family.
- [ ] Test the Android notification-channel settings intent. Reconnect currently uses network callbacks, JobScheduler, and normal retry timers; the port does not claim exact-alarm scheduling.
- [ ] Enable broadcasts and capture `io.heckel.ntfy.MESSAGE_RECEIVED`; verify all native-compatible extras, including muted and attachment values.
- [ ] Toggle UnifiedPush and verify component enable/disable, registration,
  stable endpoint delivery, exact payload bytes, and unregister with an
  independent UnifiedPush client app.
- [ ] Enable logs, exercise network/publish activity, export logs, and verify the 1,000-entry cap and secret redaction.

## UI, intents, and accessibility (#11, #12, #14, #18, #20)

- [ ] Compare every screen in `docs/androdu_version_ref` side by side in light mode, then repeat core surfaces in dark/dynamic-color mode.
- [ ] Verify home/topic overflow menus, refresh snackbar, test notification, copy/share URL, rate app, documentation, and report-issue intents.
- [ ] Search a large topic, clear the query, use system Back, rotate the device, and confirm keyboard/focus behavior.
- [ ] Complete TalkBack spoken traversal through home, add topic, feed,
  publish, search, topic settings, and app settings; verify order, labels,
  actions, and state announcements. API 36 home labels passed on the AVD, but
  repeated System UI ANRs prevented reliable end-to-end traversal. This is now
  tracked independently in #20.
- [ ] Repeat at the largest practical font/display scale and check touch targets, clipping, overflow, and landscape behavior.
- [ ] Check scroll anchoring while older messages are read and while new messages arrive at and away from the bottom.

## Closure

- [ ] Add remaining observed results and device details to #19 and #20.
- [ ] Resolve or explicitly accept the known differences in `full-parity-status.md`.
- [x] Close completed parent/umbrella tickets; keep independent #19 and #20
  visible until their remaining criteria pass or are explicitly accepted.
