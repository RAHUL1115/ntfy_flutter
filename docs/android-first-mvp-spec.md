# Android-first ntfy Flutter MVP

Status: Ready for agent

## Problem Statement

A new ntfy client is needed with a Flutter interface that closely follows the source native ntfy Android app, while retaining the reliable Android behavior required for receiving messages when the visible Flutter interface is backgrounded or terminated. A direct line-by-line conversion of the native app would reproduce years of implementation complexity and expose portable behavior to Android-specific details. The long-term product must keep all portable domain, protocol, persistence, and orchestration behavior in Flutter/Dart, with native Android code limited to platform capabilities that Flutter cannot reliably provide.

This is a completely new standalone app and behavioral fork, not an update or migration of the official native app. It has its own application identity, signing lifecycle, settings, and fresh database. The first release must provide the core ntfy experience without attempting complete parity. Users need to subscribe to anonymous ntfy topics, read and manage locally stored messages, publish common message fields, receive Android notifications, and optionally keep a foreground listener active for background delivery.

## Solution

Build a new Android-only, Flutter-first app with a thin native host. Recreate the source app's screen structure, navigation, visual hierarchy, controls, dialogs, message presentation, and settings organization in Flutter, adapting only where Flutter or current Android conventions require it. Dart owns presentation, ntfy protocol behavior, reconnection, persistence, retention, publishing, message ingestion, and application state. A background Dart runtime reuses the same application core when the visible interface is absent. Native Android adapters are limited to foreground-service hosting, reboot integration, notification-system access, and other lifecycle capabilities that cannot be implemented reliably in Dart. Mature Flutter plugins are preferred before custom Kotlin.

The MVP supports anonymous HTTP and HTTPS topics, using ntfy's newline-delimited JSON HTTP stream. Users add a subscription with one complete topic URL and may assign a local display name. The topic list follows the source app's presentation while supporting swipe-to-delete. Message feeds are chronological, with the newest message at the bottom.

Background listening is optional. When enabled, Android runs a foreground listener and displays the required ongoing notification. Settings explain this requirement and provide a shortcut to the relevant Android notification-channel settings. When disabled, the listener and ongoing notification stop.

Messages are persisted locally. Individual deletion, clearing a topic, and automatic retention affect only local data and never delete messages from the ntfy server. Retention defaults to Never and can be overridden per topic.

The publish composer supports message text, title, priority, and tags. Authentication, attachments, WebSockets, FCM, UnifiedPush, custom certificates, and advanced ntfy features are deferred.

## User Stories

1. As a new user, I want to open the app without creating an account, so that I can immediately use anonymous ntfy topics.
2. As a new user, I want an empty state that explains how to add a topic, so that I understand the app's first action.
3. As an existing ntfy Android user, I want familiar screen structure, navigation, controls, and visual hierarchy, so that the Flutter app feels like the source app.
4. As a mobile user, I want the interface to respect system light and dark appearance, so that it remains comfortable in different environments.
5. As a screen-reader user, I want controls and message metadata to have meaningful accessibility labels, so that I can operate the app without relying on visual placement.
6. As a user with limited dexterity, I want appropriately sized touch targets, so that common actions are easy to activate.
7. As a subscriber, I want to add a subscription using one complete topic URL, so that I do not have to split a server and topic into separate fields.
8. As a subscriber, I want leading and trailing whitespace removed from a topic URL, so that accidental spaces do not prevent subscription.
9. As a subscriber, I want the app to validate the topic URL before saving it, so that malformed subscriptions are caught immediately.
10. As a subscriber, I want HTTP and HTTPS self-hosted servers to be accepted, so that I am not limited to the public ntfy server.
11. As a subscriber, I want unsupported URL schemes rejected with an actionable message, so that I know how to correct the input.
12. As a subscriber, I want duplicate subscriptions detected, so that the same server and topic do not produce duplicate messages.
13. As a subscriber, I want to assign an optional local display name, so that private or machine-generated topic names are recognizable.
14. As a subscriber, I want to rename a subscription locally, so that I can reorganize the app without changing the server-side topic.
15. As a subscriber, I want the original topic URL retained after renaming, so that publishing and receiving continue against the correct topic.
16. As a subscriber, I want subscriptions to survive app restarts, so that I do not have to add them again.
17. As a subscriber, I want to see all subscriptions in one topic list, so that I can quickly choose a feed.
18. As a subscriber, I want each topic row to show its display name or topic URL, so that every subscription remains identifiable.
19. As a subscriber, I want each topic row to show unread activity, so that I can identify feeds requiring attention.
20. As a subscriber, I want the topic list to reflect new messages without manual reload, so that current state is visible while the app is open.
21. As a subscriber, I want to swipe a topic to remove it, so that topic management remains fast.
22. As a subscriber, I want destructive topic removal to require confirmation or offer undo, so that an accidental swipe does not silently remove local history.
23. As a subscriber, I want removing a topic to stop its live subscription, so that it no longer consumes resources or produces notifications.
24. As a subscriber, I want removing a topic to delete only its local data, so that the remote ntfy topic remains unaffected.
25. As a reader, I want a selected topic to open its message feed, so that I can inspect the topic's history.
26. As a reader, I want messages ordered from oldest to newest with the latest at the bottom, so that the feed behaves like a conversation.
27. As a reader, I want the initial feed position to show the newest messages, so that recent activity is immediately visible.
28. As a reader, I want incoming messages appended without losing my reading position, so that reading older content is not interrupted.
29. As a reader at the bottom of a feed, I want a new message to remain visible, so that live updates feel immediate.
30. As a reader away from the bottom, I want a clear indication that newer messages arrived, so that I can choose when to return to the latest message.
31. As a reader, I want each message to show its text and timestamp, so that I understand what happened and when.
32. As a reader, I want optional titles, priorities, and tags represented clearly, so that important message metadata is not lost.
33. As a reader, I want empty, loading, disconnected, and error states distinguished, so that I understand the current feed condition.
34. As a reader, I want previously stored messages available when offline, so that temporary network loss does not empty the feed.
35. As a reader, I want to delete an individual message locally, so that I can remove unwanted history from my device.
36. As a reader, I want local deletion to leave the remote ntfy topic unchanged, so that device cleanup cannot affect other subscribers.
37. As a reader, I want to remove all messages from the current topic, so that I can reset one local feed.
38. As a reader, I want clearing messages to preserve the subscription, so that new messages continue to arrive.
39. As a reader, I want clearing one topic to leave every other topic untouched, so that cleanup is safely scoped.
40. As a privacy-conscious user, I want a global automatic-retention setting, so that old local messages can be removed without manual cleanup.
41. As a user who values history, I want retention to default to Never, so that messages are not deleted without my choice.
42. As a user, I want retention choices of 1, 3, 6, or 12 hours and 1, 3, 10, or 30 days, so that cleanup matches my needs.
43. As a subscriber, I want a topic-specific retention override, so that sensitive and archival feeds can use different policies.
44. As a subscriber, I want a topic to inherit the global retention policy unless overridden, so that common configuration remains simple.
45. As a user, I want retention cleanup to affect only local messages, so that it never sends delete requests to ntfy servers.
46. As a publisher, I want to compose a non-empty message for the current topic, so that I can send updates without re-entering the destination.
47. As a publisher, I want to add an optional title, so that a message can communicate its subject.
48. As a publisher, I want to choose an ntfy priority, so that recipients can distinguish routine and urgent messages.
49. As a publisher, I want to add tags, so that messages can carry ntfy labels or emoji semantics.
50. As a publisher, I want invalid or empty publishing input rejected before a request is made, so that failures are understandable.
51. As a publisher, I want visible sending, success, and failure states, so that I know whether the server accepted the message.
52. As a publisher, I want a failed publish to preserve my draft, so that I can retry without retyping it.
53. As a publisher, I want the accepted message to arrive through the normal subscription stream, so that local history has one authoritative ingestion path.
54. As a publisher, I want duplicate delivery suppressed, so that publishing while subscribed does not create two copies.
55. As a foreground user, I want live messages to appear while the app is open, so that I do not need to refresh manually.
56. As a background user, I want an app setting that enables background listening, so that I can choose between instant delivery and lower resource use.
57. As a background user, I want enabling background listening to start one listener for all active subscriptions grouped efficiently by server, so that the app avoids unnecessary connections.
58. As a background user, I want Android's required ongoing foreground notification to appear while listening is active, so that the service complies with platform rules.
59. As a background user, I want the app to explain why the ongoing notification cannot be hidden, so that the behavior is not surprising.
60. As a background user, I want a Settings shortcut to the Android channel settings for the foreground listener, so that I can control the channel through supported platform controls.
61. As a user conserving battery, I want disabling background listening to stop the listener and ongoing notification, so that no hidden background work remains.
62. As a background user, I want listening to resume after process recreation and device reboot when previously enabled, so that delivery remains dependable.
63. As a background user, I want the listener to reconnect after network changes, so that switching between Wi-Fi and mobile data does not permanently stop delivery.
64. As a server operator, I want reconnect attempts to use bounded exponential backoff, so that outages do not cause aggressive retry loops.
65. As a user, I want connection state visible without blocking access to stored messages, so that an outage does not make the app unusable.
66. As a background user, I want new messages to produce Android notifications, so that I notice updates while outside the app.
67. As a background user, I want tapping a notification to open the correct topic, so that I can immediately see its context.
68. As a background user, I want one incoming ntfy message to produce at most one Android notification, so that reconnects do not cause duplicate alerts.
69. As a foreground reader already viewing a topic, I want duplicate system notifications suppressed, so that the app does not alert me about content already on screen.
70. As a user, I want notification permission requested only when needed and with context, so that the request is understandable.
71. As a user who denies notification permission, I want the in-app feed to continue working, so that denial does not break core subscription behavior.
72. As a user, I want notification priority mapped to sensible Android channel importance, so that urgent ntfy messages can be distinguished from routine ones.
73. As a returning user, I want the last received message cursor persisted per subscription, so that reconnecting does not replay the entire topic history.
74. As a returning user, I want message identity enforced locally, so that retries and reconnections cannot duplicate stored messages.
75. As a user, I want local data writes serialized through one owner, so that UI and background lifecycle transitions cannot close or corrupt each other's database access.
76. As a user, I want the app to recover gracefully from malformed server events, so that one bad message does not terminate the subscription.
77. As a user, I want actionable errors for unreachable servers and rejected publishes, so that I can distinguish bad input from temporary network failure.
78. As a maintainer, I want portable delivery behavior implemented once in Dart, so that foreground and background execution share the same ntfy semantics.
79. As a maintainer, I want the Dart application core testable with in-memory platform adapters, so that domain and UI behavior can be verified without launching Android services.
80. As a maintainer, I want end-to-end behavior verified against a controllable local ntfy server, so that protocol and lifecycle regressions are detected before release.

## Implementation Decisions

- The product is a completely new Android-only standalone app and behavioral fork, not an upgrade-compatible replacement for the official native app. It uses its own application identity, signing lifecycle, settings, and fresh database. No migration, import, shared database, native signing key, or Room compatibility work is required.
- The initialized application identity is `com.rahul1115.ntfy_flutter`. Product naming may change independently, but changing the application identity after distribution is not supported.
- Flutter/Dart owns navigation, screens, rendering, forms, accessibility, domain models, URL normalization, ntfy event parsing, publishing, reconnection policy, persistence schema and queries, retention, message ingestion, deduplication, and application state.
- The Dart application core is a deep module behind a domain interface. Presentation sends typed commands and observes typed state/events; screens do not know whether work is executing in the visible Flutter runtime or a background Dart runtime.
- The domain interface exposes two conceptual operations: execute a typed domain command and observe typed domain state/events. Subscription, publishing, retention, and listener operations are commands rather than separate shallow modules.
- The same Dart application core runs for foreground and background delivery. Protocol and persistence rules must not be reimplemented in Kotlin.
- A thin native Android host owns only platform lifecycle capabilities: foreground-service hosting, reboot startup, Android notification-system integration, notification-channel settings navigation, and any required OS callbacks.
- Flutter plugins are used for native capabilities when they meet lifecycle and reliability requirements. Custom Kotlin is added only where a plugin cannot satisfy a required Android behavior.
- Native access sits behind one narrow platform seam. A production Android adapter and in-memory Dart adapter satisfy that interface, making it independently testable without exposing Android contexts, intents, cursors, or framework notification objects.
- Dart owns the SQLite schema and repository behavior through a Flutter-compatible SQLite adapter. Database access from UI and background runtimes is serialized; foreground-service teardown must never close a connection still used by another Flutter runtime.
- The app maintains one authoritative local store. It must not introduce separate native and Dart databases or reconciliation between competing stores.
- Values crossing the native seam contain stable identifiers and serializable primitives only.
- Proven behavior from the Apache-2.0-licensed native ntfy app is a behavioral reference for lifecycle edge cases. Portable native modules are not copied as permanent implementations; any adapted native source is restricted to the thin host and retains required notices.
- The MVP supports Android only. No iOS, web, desktop, or cross-platform background-delivery promise is made.
- The MVP supports anonymous topics only. Credentials, access tokens, and authenticated private topics are rejected or clearly identified as unsupported rather than silently failing.
- Topic entry uses one complete URL. The app canonicalizes the server/topic identity for duplicate detection while retaining a safe display form.
- The MVP supports HTTP and HTTPS. Advanced trust configuration is not included.
- Live delivery uses ntfy's newline-delimited JSON HTTP stream. WebSocket selection is not exposed.
- One background Dart listener manages active subscriptions and groups topic streams by server where the protocol permits it. The native host keeps that runtime eligible to execute through an Android foreground service.
- Reconnection uses bounded exponential backoff with reset after a healthy connection. Network changes trigger a refresh without creating parallel listeners.
- Background listening is globally opt-in. Disabling it stops all persistent listener work; foreground in-app listening may continue while the app is active.
- Android's foreground-service notification remains ongoing whenever the background listener is active. The app does not claim it can hide this notification.
- The app registers only the Android permissions, receivers, service declarations, and boot handling needed by the MVP.
- Local notification permission is requested contextually. Refusal does not disable message ingestion or in-app history.
- Incoming server message IDs provide idempotency. The persisted per-subscription cursor prevents unnecessary replay after reconnect.
- All accepted messages, including messages published by this app, enter local history through the subscription ingestion path. The composer does not optimistically insert a second local message.
- The publish composer supports message, optional title, priority, and tags. It publishes through the same server/topic identity used by the subscription.
- Message feeds are chronological with the newest item at the bottom. UI update behavior preserves the reader's position when they are inspecting older messages.
- Topic display names are local metadata and never modify the server-side topic.
- Swipe-to-delete is the primary topic-removal gesture, with confirmation or undo before irreversible local cleanup.
- Individual message deletion, topic clearing, retention cleanup, and topic removal are local-only operations.
- Global retention defaults to Never. Supported durations are 1, 3, 6, and 12 hours and 1, 3, 10, and 30 days.
- Every topic can inherit global retention or select one of the same explicit durations.
- Retention cleanup is idempotent and safe to run after startup and from the background Dart runtime. It does not require the visible Flutter interface to remain alive.
- UI state distinguishes initial loading, empty history, live connection, reconnecting, offline, and actionable errors without hiding persisted data.
- The Flutter UI should closely reproduce the source app's information architecture, navigation, screen composition, dialogs, settings grouping, typography hierarchy, colors, icons, spacing, and interaction patterns. Accessibility and current Android requirements remain mandatory, but a new one-handed redesign is explicitly deferred.
- The implementation should add dependencies only when Flutter or Android standard facilities do not provide the required behavior.

## Testing Decisions

- Tests assert externally observable behavior through the highest practical seam. They do not assert private classes, SQL query shape, platform-channel method names, widget tree trivia, or worker implementation details.
- The primary acceptance seam is the running app plus a controllable local ntfy server. Acceptance tests publish and stream real ntfy protocol events, then verify visible feed state and Android notification behavior.
- The local server uses isolated randomized topics per test and is reset between scenarios. Tests must not rely on public ntfy topics or external network availability.
- The Flutter presentation module is tested through the Dart domain interface using in-memory adapters. Widget tests cover subscription entry, duplicate and malformed URL feedback, topic removal, feed ordering, publish validation, retention selection, listener settings, loading states, and error states.
- The Dart application core is tested through its domain command/state interface. Tests cover protocol parsing, persistence, message idempotency, cursor recovery, local deletion, scoped clearing, retention, reconnection, publishing, and listener enable/disable behavior.
- The native Android host is tested only through the narrow platform seam and Android integration tests. Tests verify hosting and OS integration, not portable ntfy business rules.
- Protocol acceptance covers normal messages, titles, all supported priorities, tags, keepalive records, malformed records, disconnects, reconnects, and duplicate message IDs.
- Publishing acceptance verifies request fields at the server and confirms that the published message appears once through the normal stream.
- Android integration tests verify notification permission handling, notification creation, notification-to-topic navigation, foreground-listener notification presence, disabling the listener, and suppression while the relevant feed is visible.
- Lifecycle acceptance uses an emulator or physical Android device to exercise foreground/background transitions, process termination, service restart, network loss/recovery, and reboot recovery.
- Database regression tests repeatedly background and resume the app while restarting the foreground listener, proving that service teardown cannot close the data access used by Flutter.
- Retention tests use a controllable clock or seeded timestamps and verify every supported duration, global inheritance, per-topic override, and strict topic scoping.
- UI parity checks compare each implemented Flutter screen against the corresponding source-app screen for information hierarchy, navigation, controls, dialogs, settings organization, message presentation, colors, icons, and spacing. Differences must be intentional and documented.
- Accessibility tests verify semantic labels, traversal order, touch-target sizing, and operation with increased text scaling on the primary screens.
- Prior art is the native app's manual behavior checklist and its established handling of subscriptions, message identity, foreground listening, and Android notification channels. Since the native repository has no automated suite for these flows, this project must leave automated regression coverage rather than relying only on manual parity checks.
- Before an MVP release, the complete acceptance suite must pass on at least one current Android emulator and one physical device. Background behavior must be manually smoke-tested on a battery-restrictive OEM device when available.

## Out of Scope

- Drop-in replacement of the official `io.heckel.ntfy` app, shared signing identity, shared storage, or migration of any official-app database or settings.
- Importing, restoring, or automatically discovering data from an existing official native-app installation.
- iOS, web, desktop, or other non-Android platforms.
- Username/password authentication, access tokens, authenticated private topics, or credential storage.
- WebSocket subscriptions or a user-selectable connection protocol.
- Firebase Cloud Messaging delivery and Play/F-Droid product flavors.
- UnifiedPush distributor behavior.
- Trusted custom certificate authorities, certificate pinning controls, and PKCS#12 client certificates.
- Custom HTTP headers.
- File and media attachments, attachment download management, image previews, and upload progress.
- Delayed publishing, email forwarding, phone calls, Markdown publishing, click URLs, remote attachment URLs, and ntfy action buttons.
- Rich Markdown rendering in received message bodies.
- Dedicated notification-channel groups per subscription, custom sounds, insistent alarms, and advanced action receivers.
- External Android broadcast interfaces for sending or receiving ntfy messages.
- Android share-target publishing and ntfy deep-link handling.
- Backup and restore.
- Message search.
- Server-side message deletion or clearing.
- Multiple accounts, server administration, or topic discovery.
- Pixel-perfect reproduction of legacy rendering quirks or XML implementation details. Close visual and interaction similarity to the source app is in scope.
- Analytics, telemetry, payments, ratings prompts, or account registration.

## Further Notes

- Implementation started from a deliberately minimal Flutter scaffold rather than carrying forward the previous prototype's architecture. Add state management, feature modules, dependencies, and native seams only as an approved vertical slice requires them.
- The existing native Android app remains the behavioral reference for core ntfy semantics and difficult Android lifecycle cases. This specification intentionally narrows the first release rather than treating every native feature as mandatory parity or preserving its native implementation structure.
- The intended end state is Flutter/Dart ownership of every portable capability. Future parity work extends the Dart application core; native Android code grows only when a required OS capability has no reliable Flutter implementation.
- The immediate UI target is faithful source-app similarity, not a new one-handed redesign. Broader UX optimization should be considered only after functional and visual porting is established.
- The source native app is Apache 2.0 licensed. Any adapted source or assets must preserve the license and attribution requirements.
- The required ongoing Android notification is a platform constraint of foreground background listening, not a removable UI choice.
- A realistic target for an autonomous coding agent is approximately 7–10 focused agent-days for this MVP, followed by physical-device stabilization. Background lifecycle behavior is the largest schedule risk.
- Human input remains necessary for physical-device checks, release signing, store publication, and judgment about battery behavior on OEM-specific Android builds.
