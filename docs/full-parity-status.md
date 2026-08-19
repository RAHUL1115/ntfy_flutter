# Full parity status

Status date: 2026-08-19

This is the authoritative implementation and verification record for issues
#9–#20. The behavior reference is
[`binwiederhier/ntfy-android`](https://github.com/binwiederhier/ntfy-android/)
at tag [`v1.25.2`](https://github.com/binwiederhier/ntfy-android/tree/v1.25.2),
mirrored in the sibling `../ntfy-android` checkout. The ten files in
`docs/androdu_version_ref` are the visual reference set. Comparisons do not
follow the upstream default branch unless a newer baseline is explicitly
adopted.

## Current verdict

All ticketed implementation and automated verification is complete. Extended
acceptance also passed on a Genymotion Android 15 virtual device, including
cold-boot recovery, permission, priority-mode DND routing, network recovery,
per-topic delivery, settings, large text, landscape, UnifiedPush component
toggling, and connected Android tests. A stock Google APIs Android 16 / API 36
AVD also passed release installation/launch and exposed labeled home controls
to its bundled TalkBack service. Actual sound, vibration, notification LED,
OEM battery behavior, independent UnifiedPush interoperability, and the
app-owned visual differences from the supplied references are resolved in
#19. Physical TalkBack acceptance is tracked separately in #20. Real trusted-CA TLS and
client-certificate mTLS interoperability now pass against a local ntfy server
and terminating TLS proxy.
Port-specific strings that do not exist
in the upstream translation catalogs currently fall back to English and are an
explicit localization difference pending approval or translated copy.

## Ticket status

| Issue | Implemented result | Remaining device acceptance |
|---:|---|---|
| #9 | Permission context, five priority channels, emoji presentation, replacement/deduplication, visible-feed suppression, actions, remote icons, and exact-message tap routing | Actual sound, tactile vibration, and notification LED output |
| #10 | Grouped listeners, bounded reconnect, network callbacks, boot/service restoration, aggregate errors, and duplicate prevention | OEM-specific battery restriction behavior |
| #11 | Integrated MVP, release build, persistence, feed/publish/retention flows, semantics, source-aligned core UI, real-server suite, physical-device smoke, and an in-place 0.1.0 → 0.1.1 upgrade with data/profile preservation | None; acceptance complete |
| #12 | Closed after umbrella parity work, source inventory, and final reference-screen side-by-side review | None; residual differences moved to independent #19 |
| #13 | Global/per-topic mute, inheritance, priorities, insistent max, attachment policy, topic icon, dedicated channels, and DND routing | Actual sound, tactile vibration, LED, and human insistent-behavior observation |
| #14 | Topic search over persisted message/title/tag data with clear/no-result states | Hardware/system Back, rotation, and large-history responsiveness |
| #15 | Advanced publish fields, local/URL attachments, authenticated downloads, progress/open/cleanup, and limits | Android picker/share/open apps and large-file cancellation |
| #16 | Per-topic background delivery eligibility shared by foreground/background selection | Real background and battery-restriction behavior |
| #17 | Default server, users/auth, appearance, 31 native language catalogs, backup/restore, protocols, headers, certificates, broadcasts, UnifiedPush, logs, and About; trusted-CA TLS and client-certificate mTLS passed in foreground and background | Independent UnifiedPush client ecosystem |
| #18 | Closed after source toolbar/menu utilities, feedback, colors, priority glyphs, empty copy, stable core visuals, dynamic color, external intents, and final side-by-side review | None |
| #19 | Incoming-field, localization, backup, UnifiedPush, and ten-screen visual parity implemented and automated | Human sensory/OEM and independent UnifiedPush observations remain in the device checklist, outside app-owned implementation |
| #20 | Physical-device TalkBack acceptance | Complete spoken traversal on the target device |

## Screenshot evidence

`test/reference_goldens_test.dart` deterministically captures all ten supplied
states using declared Roboto and loaded Material icon fonts:

- home and home overflow
- topic and topic overflow
- topic settings and snooze dialog
- topic search with keyboard inset
- expanded attachment/publish composer with keyboard inset
- complete app settings surface
- populated topic with newest-first cards, emoji tag titles, and compact actions

The baselines are `test/goldens/reference_*.png`. Light/dark/large-text home
baselines remain covered separately by `test/widget_test.dart`.

## Source inventory and intentional differences

The source inventory was rerun against `../ntfy-android`. The remaining
differences are deliberate platform/product boundaries, not hidden missing
ticket work:

- The port keeps its own application ID and SQLite database and performs no
  import or migration from the official app.
- Background delivery uses HTTP/WebSocket streams in the app's foreground
  service. It does not ship the official project's private Firebase/FCM
  credentials.
- Android-only work remains Kotlin; portable protocol, policy, persistence,
  backup, and product behavior remains Dart.
- Reconnect uses network callbacks, JobScheduler, and bounded listener retry.
  The port does not claim an exact-alarm implementation it does not have.
- UnifiedPush registration, stable endpoints, exact-byte forwarding, and
  unregister are implemented. Compatibility with independent UnifiedPush
  client apps is still a device/ecosystem acceptance item.
- Flutter/Material rendering is behaviorally and structurally aligned but is
  not expected to be pixel-identical to every legacy XML/widget rendering path.

## Verification results

| Check | Result |
|---|---|
| `flutter analyze --no-pub` | Pass, no issues |
| `flutter test --no-pub` | Pass, 141 tests; the opt-in real-server test is skipped in the default run |
| `NTFY_BIN=... flutter test --no-pub test/real_ntfy_acceptance_test.dart` | Pass against local ntfy server 2.27.0 |
| Connected Flutter Android integration test | Pass, 2 tests: notification mapping/dedup/suppression and explicit restart cycles |
| Native Android instrumentation | Pass, 5/5 individually; the combined invocation exposed a Genymotion System UI renderer crash, not an app crash |
| `flutter build apk --debug --no-pub` | Pass |
| `flutter build apk --release` | Pass, signed 55.5 MB v0.1.2+3 release APK |
| `:app:compileDebugKotlin` | Pass |
| `:app:compileDebugAndroidTestKotlin` | Pass |
| `git diff --check` | Pass |
| Genymotion Android 15 release acceptance | Pass for launch/render, delivery, restart/reboot, permission, network recovery, per-topic disable, settings, dark mode, 1.3x text, and landscape |
| Genymotion v0.1.2+3 parity smoke | Pass for upgrade/install, launch, home/feed rendering, link recognition, app-settings scrolling, and clean app/SQLite logs |
| Local TLS/mTLS interoperability | Pass: trusted self-signed CA, client certificate/key persistence, authenticated foreground stream, background stream, and Android notification |
| In-place release upgrade | Pass: 0.1.0+1 → generated 0.1.1+2 retained the subscription, both messages, certificate profile, and a connected mTLS stream |
| Claude Opus final review | Three certificate/network findings fixed: normalized profile merging, authenticated redirect blocking, and post-commit restore cleanup safety; focused regressions and full suite pass |
| Android Studio AVD Android 16 / API 36 | Partial pass: release install/launch and labeled TalkBack home tree passed; repeated System UI ANRs under the 2 GB image prevented reliable complete spoken traversal |

The release build must run dependency/plugin generation before Gradle
compilation (`flutter build apk --release`, not a release build immediately
after an integration-test build with stale generated registration). This was
verified after a stale dev-plugin registrant was detected and regenerated.

Genymotion logged an Impeller GLES shader-link warning, but all inspected
Flutter screens rendered and remained interactive. Treat this as an emulator
graphics warning unless it reproduces visibly on a target device.

After the final fixes, three consecutive same-version release package
replacements/cold launches preserved a seeded message and produced no
`SQLITE_BUSY` error. One earlier startup lock could not be reproduced after
the stale runtime exited, so no speculative database change was made.

The real ntfy-server acceptance test remains opt-in via `NTFY_BIN`. See
`device-acceptance-checklist.md` for the checks intentionally deferred to the
user's full device pass.
