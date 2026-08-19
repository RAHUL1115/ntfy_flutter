# Android-first MVP parity audit

> Historical MVP audit. The current implementation and verification record is
> maintained in [full-parity-status.md](full-parity-status.md); Android-only
> checks are in [device-acceptance-checklist.md](device-acceptance-checklist.md).

Status: Static audit complete; Android device acceptance deferred

Audit date: 2026-08-18

## Scope and method

This audit checks the 80 user stories, implementation decisions, testing decisions, and every implemented Flutter surface against the Android-first MVP contract in [`android-first-mvp-spec.md`](android-first-mvp-spec.md#L5). Evidence is limited to the Flutter implementation and tests in this repository and the sibling native Android source/resources in `../../ntfy-android`. No claim below depends on public documentation or a secondary description of either app.

`Verified` means an automated non-device check exercises the behavior. `Implemented; device pending` means the required production path exists but its Android OS behavior cannot be completed without an emulator/device. `Partial` means a concrete part of the criterion is absent or insufficiently covered. Intentional scope differences are listed separately and are not counted as gaps.

## Verdict

The portable core of the MVP is substantially present: anonymous URL subscriptions, persistence, chronological feeds, local cleanup, retention, publishing, streaming/reconnection, cursor/idempotency behavior, optional background listening, and notification routing all have production implementations and broad Dart/widget coverage. The app is not ready to declare full MVP parity because Android lifecycle/notification acceptance remains deferred, the final post-fix full-suite rerun is pending, the acceptance suite against a real ntfy server is opt-in, accessibility coverage is incomplete, and the architecture does not yet provide the single application-wide command/state interface or demonstrably single database-write owner required by the design decisions.

The rename-dialog lifecycle defect found during this audit has been fixed by removing its premature `TextEditingController` disposal ([`retention_settings.dart`](../lib/retention_settings.dart#L41)). The focused rename widget test now passes; the parent task owns the final full-suite rerun.

The largest remaining source-app presentation differences are:

1. **Add-subscription composition.** The native app uses a full-screen Material surface with a close affordance, toolbar action, scrolling content, progress, and inline errors ([`fragment_add_dialog.xml`](../../ntfy-android/app/src/main/res/layout/fragment_add_dialog.xml#L11)). Flutter uses a compact `AlertDialog` ([`main.dart`](../lib/main.dart#L611)). Its complete-URL and optional-display-name fields are intentional MVP differences, but the screen hierarchy is not close parity.
2. **Message priority presentation.** The native card uses distinct priority 1/2/4/5 assets and hides the default priority ([`DetailAdapter.kt`](../../ntfy-android/app/src/main/java/io/heckel/ntfy/ui/DetailAdapter.kt#L176)); Flutter uses one of two generic icons plus `Priority N` text ([`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L629)). Metadata is not lost, but icon parity is incomplete.
3. **Empty-feed instruction detail.** Native reserves separate rows for the explanation, concrete curl example, and documentation link ([`activity_detail.xml`](../../ntfy-android/app/src/main/res/layout/activity_detail.xml#L47)); Flutter gives the explanation but omits the topic-specific example/link ([`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L487)).

The earlier functional topic-list gaps are closed in the audited tree: Flutter now stores total/unread/last-activity metadata, sorts by latest activity, renders the count/date subtitle and unread badge, and refreshes background-isolate changes ([`subscriptions.dart`](../lib/subscriptions.dart#L155), [`main.dart`](../lib/main.dart#L372)).

## User-story criterion matrix

| ID | Criterion | Result | Evidence / finding |
|---:|---|---|---|
| 1 | No account required | Verified | App opens directly to subscriptions; no authentication gate ([`main.dart`](../lib/main.dart#L56)). |
| 2 | Useful first-run empty state | Verified | Empty explanation and add direction ([`main.dart`](../lib/main.dart#L471)); widget coverage ([`widget_test.dart`](../test/widget_test.dart#L20)). |
| 3 | Familiar native structure and hierarchy | Partial | Core list/feed/settings/composer topology is recognizable, but the three presentation differences in the verdict remain. |
| 4 | System light/dark appearance | Verified | `ThemeMode.system` and source palette tokens ([`main.dart`](../lib/main.dart#L14), [`colors.xml`](../../ntfy-android/app/src/main/res/values/colors.xml#L3)); light/dark widget tests ([`widget_test.dart`](../test/widget_test.dart#L171)). |
| 5 | Meaningful screen-reader labels | Partial | Primary controls and message metadata have semantics ([`main.dart`](../lib/main.dart#L398), [`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L594)); no complete traversal/increased-scale audit exists. |
| 6 | Appropriate touch targets | Partial | Standard Material controls and a primary-control size test exist ([`widget_test.dart`](../test/widget_test.dart#L192)); all primary screens and text-scale cases are not covered. |
| 7 | One complete topic URL | Verified | Single URL field ([`main.dart`](../lib/main.dart#L570)). |
| 8 | Trim URL whitespace | Verified | Normalization trims before parsing ([`subscriptions.dart`](../lib/subscriptions.dart#L399)). |
| 9 | Validate before saving | Verified | Normalization/validation precedes insert ([`subscriptions.dart`](../lib/subscriptions.dart#L109), [`subscription_store_test.dart`](../test/subscription_store_test.dart#L25)). |
| 10 | HTTP and HTTPS self-hosting | Verified | Both schemes accepted, other schemes rejected ([`subscriptions.dart`](../lib/subscriptions.dart#L407)). |
| 11 | Actionable unsupported-scheme error | Verified | Explicit HTTP/HTTPS message ([`subscriptions.dart`](../lib/subscriptions.dart#L392)). |
| 12 | Detect duplicates | Verified | Canonical unique URL plus user-facing error ([`subscriptions.dart`](../lib/subscriptions.dart#L122), [`subscription_store_test.dart`](../test/subscription_store_test.dart#L75)). |
| 13 | Optional local display name | Verified | Stored independently at subscription creation ([`subscriptions.dart`](../lib/subscriptions.dart#L109)). |
| 14 | Rename locally | Verified | Persistence/navigation are implemented ([`retention_settings.dart`](../lib/retention_settings.dart#L29), [`subscriptions.dart`](../lib/subscriptions.dart#L193)); focused widget coverage now passes after correcting the dialog controller lifetime ([`widget_test.dart`](../test/widget_test.dart#L75)). |
| 15 | Rename retains original URL | Verified | Rename updates only `display_name`; URL remains separate ([`subscriptions.dart`](../lib/subscriptions.dart#L193)). Native uses the same separation ([`DetailSettingsActivity.kt`](../../ntfy-android/app/src/main/java/io/heckel/ntfy/ui/DetailSettingsActivity.kt#L392)). |
| 16 | Subscriptions survive restart | Verified | SQLite storage/reopen coverage ([`subscriptions.dart`](../lib/subscriptions.dart#L61), [`subscription_store_test.dart`](../test/subscription_store_test.dart#L307)). |
| 17 | One topic list | Verified | Root subscriptions list ([`main.dart`](../lib/main.dart#L410)). |
| 18 | Identifiable topic row | Verified | Display name/URL plus count and last-activity subtitle ([`main.dart`](../lib/main.dart#L372), [`main.dart`](../lib/main.dart#L458)). |
| 19 | Unread activity | Verified | Persisted unread count and accessible badge ([`subscriptions.dart`](../lib/subscriptions.dart#L155), [`main.dart`](../lib/main.dart#L501)); widget coverage clears only the viewed topic ([`widget_test.dart`](../test/widget_test.dart#L112)). |
| 20 | List updates without manual reload | Verified | Lifecycle refresh plus lightweight store polling bridge background-isolate writes into the visible list ([`main.dart`](../lib/main.dart#L186)). |
| 21 | Swipe topic removal | Verified | Horizontal `Dismissible` ([`main.dart`](../lib/main.dart#L447)). This is an intentional MVP adaptation; native removes through selection/action mode rather than swipe. |
| 22 | Confirm or undo topic removal | Verified | Destructive confirmation precedes dismissal ([`main.dart`](../lib/main.dart#L307)). |
| 23 | Removal stops live subscription | Verified | Background listener refresh follows removal and an open feed closes on unsubscribe ([`main.dart`](../lib/main.dart#L333), [`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L367)). |
| 24 | Removal is local-only | Verified | SQLite cascade only; HTTP acceptance asserts no delete request ([`subscriptions.dart`](../lib/subscriptions.dart#L147), [`http_acceptance_test.dart`](../test/http_acceptance_test.dart#L304)). |
| 25 | Topic opens its feed | Verified | Row navigation creates a topic feed ([`main.dart`](../lib/main.dart#L275)). |
| 26 | Oldest-to-newest, newest at bottom | Verified | Store orders ascending and controller sorts by time/local id ([`subscriptions.dart`](../lib/subscriptions.dart#L166), [`topic_feed.dart`](../lib/topic_feed.dart#L528)). This intentionally reverses native newest-first behavior ([`Database.kt`](../../ntfy-android/app/src/main/java/io/heckel/ntfy/db/Database.kt#L590)). |
| 27 | Initial position shows newest | Verified | Initial post-frame scroll to max extent; widget coverage ([`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L183), [`topic_feed_widget_test.dart`](../test/topic_feed_widget_test.dart#L153)). |
| 28 | Incoming messages preserve reading position | Verified | Captures/restores the first visible anchor ([`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L152)). |
| 29 | New message stays visible at bottom | Verified | Bottom-state append scroll behavior ([`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L119)). |
| 30 | New-message indication away from bottom | Verified | Extended `New messages` action ([`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L466)). |
| 31 | Message text and timestamp | Verified | Message card renders both ([`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L574)). |
| 32 | Title, priority, tags represented | Verified | All fields render and enter the semantics label ([`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L576)); priority icon parity remains a visual gap. |
| 33 | Empty/loading/disconnected/error states differ | Verified | State enum, status label, spinner, and empty surface ([`topic_feed.dart`](../lib/topic_feed.dart#L10), [`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L456)). |
| 34 | Stored messages remain offline | Verified | Feed loads persisted snapshot before connecting and retains it across offline/error ([`topic_feed.dart`](../lib/topic_feed.dart#L320), [`topic_feed_widget_test.dart`](../test/topic_feed_widget_test.dart#L101)). |
| 35 | Delete one message locally | Verified | Swipe plus repository-scoped delete ([`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L523), [`subscriptions.dart`](../lib/subscriptions.dart#L276)). |
| 36 | Individual delete leaves server unchanged | Verified | Local repository command; no-delete HTTP acceptance ([`http_acceptance_test.dart`](../test/http_acceptance_test.dart#L304)). |
| 37 | Clear current topic | Verified | Confirmed clear command ([`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L306)). |
| 38 | Clear preserves subscription | Verified | Deletes only message rows ([`subscriptions.dart`](../lib/subscriptions.dart#L306)). |
| 39 | Clear is topic-scoped | Verified | Subscription predicate and multi-topic test ([`subscriptions.dart`](../lib/subscriptions.dart#L306), [`subscription_store_test.dart`](../test/subscription_store_test.dart#L225)). |
| 40 | Global automatic retention | Verified | Global setting and periodic cleanup ([`retention_settings.dart`](../lib/retention_settings.dart#L7), [`retention.dart`](../lib/retention.dart#L97)). |
| 41 | Retention defaults to Never | Verified | Enum/schema default and test ([`retention.dart`](../lib/retention.dart#L3), [`retention_test.dart`](../test/retention_test.dart#L13)). |
| 42 | All required retention choices | Verified | Exact 1/3/6/12 hour and 1/3/10/30 day set ([`retention.dart`](../lib/retention.dart#L3)). |
| 43 | Per-topic override | Verified | Topic setting command ([`retention_settings.dart`](../lib/retention_settings.dart#L90)). |
| 44 | Topic inherits global | Verified | Nullable override and summary ([`retention.dart`](../lib/retention.dart#L31)). |
| 45 | Retention is local-only | Verified | SQLite cleanup only ([`subscriptions.dart`](../lib/subscriptions.dart#L494)). |
| 46 | Publish non-empty message to current topic | Verified | Quick/full composers and current subscription URL ([`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L218), [`topic_feed.dart`](../lib/topic_feed.dart#L264)). |
| 47 | Optional publish title | Verified | Optional title control/request field ([`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L874), [`publish.dart`](../lib/publish.dart#L50)). |
| 48 | Five ntfy priorities | Verified | Five choices and request mapping ([`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L923), [`publish_test.dart`](../test/publish_test.dart#L9)). |
| 49 | Publish tags | Verified | Comma-trim parser and request mapping ([`publish.dart`](../lib/publish.dart#L121)). |
| 50 | Reject empty/invalid before request | Verified | Model validation precedes HTTP creation ([`publish.dart`](../lib/publish.dart#L18), [`publish_test.dart`](../test/publish_test.dart#L49)). |
| 51 | Sending/success/failure visible | Verified | Disabled/progress state, success snackbar, inline failure ([`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L778)). |
| 52 | Failed draft preserved | Verified | Controllers are retained on exception; widget retry test ([`topic_feed_widget_test.dart`](../test/topic_feed_widget_test.dart#L437)). |
| 53 | Accepted publish enters through stream | Verified | Composer never inserts locally; acceptance test waits for streamed insertion ([`http_acceptance_test.dart`](../test/http_acceptance_test.dart#L126)). |
| 54 | Duplicate publish delivery suppressed | Verified | Unique `(subscription_id,event_id)` and acceptance coverage ([`subscriptions.dart`](../lib/subscriptions.dart#L446), [`http_acceptance_test.dart`](../test/http_acceptance_test.dart#L126)). |
| 55 | Foreground live messages | Verified | Feed begins an HTTP JSON stream and emits ingested rows ([`topic_feed.dart`](../lib/topic_feed.dart#L320)). |
| 56 | Global background-listening opt-in | Verified | Persisted switch ([`retention_settings.dart`](../lib/retention_settings.dart#L300), [`subscriptions.dart`](../lib/subscriptions.dart#L350)). |
| 57 | One efficient listener grouped by server | Verified | Runtime groups by server and compatible cursor; tests cover grouping and safe cursor separation ([`background_listening.dart`](../lib/background_listening.dart#L246), [`background_listening_test.dart`](../test/background_listening_test.dart#L72)). |
| 58 | Ongoing foreground notification | Implemented; device pending | Service calls `startForeground` and builds an ongoing notification ([`BackgroundListenerService.kt`](../android/app/src/main/kotlin/com/rahul1115/ntfy_flutter/BackgroundListenerService.kt#L48)). |
| 59 | Explain required notification | Verified | Switch subtitle explains ongoing notification and denial behavior ([`retention_settings.dart`](../lib/retention_settings.dart#L243)). |
| 60 | Shortcut to listener-channel settings | Implemented; device pending | Flutter command and Android channel intent ([`retention_settings.dart`](../lib/retention_settings.dart#L255), [`MainActivity.kt`](../android/app/src/main/kotlin/com/rahul1115/ntfy_flutter/MainActivity.kt#L106)). |
| 61 | Disable stops service/ongoing notification | Implemented; device pending | Host stop and `stopForeground(...REMOVE)` path ([`background_listening.dart`](../lib/background_listening.dart#L157), [`BackgroundListenerService.kt`](../android/app/src/main/kotlin/com/rahul1115/ntfy_flutter/BackgroundListenerService.kt#L240)). |
| 62 | Resume after recreation/reboot | Implemented; device pending | Sticky service, persisted opt-in, boot receiver ([`BackgroundListenerService.kt`](../android/app/src/main/kotlin/com/rahul1115/ntfy_flutter/BackgroundListenerService.kt#L126), [`NtfyApplication.kt`](../android/app/src/main/kotlin/com/rahul1115/ntfy_flutter/NtfyApplication.kt#L32)). |
| 63 | Reconnect after network changes | Implemented; device pending | Default network callback forces serialized reconnect ([`NtfyApplication.kt`](../android/app/src/main/kotlin/com/rahul1115/ntfy_flutter/NtfyApplication.kt#L10)). |
| 64 | Bounded exponential backoff | Verified | 1/2/4/8/16/30-second cap and reset on healthy protocol records ([`topic_feed.dart`](../lib/topic_feed.dart#L211), [`topic_feed_test.dart`](../test/topic_feed_test.dart#L113)). |
| 65 | Connection state visible without hiding stored data | Verified | App-bar status remains independent from populated message list ([`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L442), [`topic_feed_widget_test.dart`](../test/topic_feed_widget_test.dart#L101)). |
| 66 | Background messages create Android notifications | Implemented; device pending | Notification is requested only after a successful new insert ([`background_listening.dart`](../lib/background_listening.dart#L340), [`MessageNotificationAdapter.kt`](../android/app/src/main/kotlin/com/rahul1115/ntfy_flutter/MessageNotificationAdapter.kt#L66)). |
| 67 | Tap opens correct topic/message context | Implemented; device pending | Stable identifiers cross the native seam; Flutter opens topic and reveals even an older lazy-list event id ([`MessageNotificationAdapter.kt`](../android/app/src/main/kotlin/com/rahul1115/ntfy_flutter/MessageNotificationAdapter.kt#L113), [`main.dart`](../lib/main.dart#L232), [`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L162)); off-screen widget coverage exists ([`topic_feed_widget_test.dart`](../test/topic_feed_widget_test.dart#L16)). |
| 68 | At most one notification per message | Verified | Alert follows only a successful unique insert; reconnect coverage ([`background_listening_test.dart`](../test/background_listening_test.dart#L200)). |
| 69 | Suppress while relevant feed visible | Verified | Visibility is registered before feed start and checked in Dart/native; lifecycle/route tests cover it ([`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L82), [`notifications_test.dart`](../test/notifications_test.dart#L39)). |
| 70 | Contextual notification permission | Implemented; device pending | Permission is requested only when enabling background listening, beside explanatory settings copy ([`background_listening.dart`](../lib/background_listening.dart#L157), [`retention_settings.dart`](../lib/retention_settings.dart#L243)). |
| 71 | Permission denial does not break feed | Verified | Notification failures return false without affecting ingestion; denial test ([`notifications.dart`](../lib/notifications.dart#L162), [`background_listening_test.dart`](../test/background_listening_test.dart#L271)). |
| 72 | Priority maps to Android importance | Implemented; device pending | Five stable channels map min/low/default/high/max ([`MessageNotificationAdapter.kt`](../android/app/src/main/kotlin/com/rahul1115/ntfy_flutter/MessageNotificationAdapter.kt#L177)); channel behavior needs OS inspection. |
| 73 | Persist cursor per subscription | Verified | Cursor stored transactionally with ingestion and reused as `since` ([`subscriptions.dart`](../lib/subscriptions.dart#L243), [`topic_feed.dart`](../lib/topic_feed.dart#L112)). |
| 74 | Enforce local message identity | Verified | Unique subscription/event identity and dedupe tests ([`subscriptions.dart`](../lib/subscriptions.dart#L446), [`subscription_store_test.dart`](../test/subscription_store_test.dart#L194)). |
| 75 | Serialize writes through one owner | Partial | Each session serializes its own operations, but UI and background isolates open independent `SubscriptionStore` connections ([`topic_feed.dart`](../lib/topic_feed.dart#L480), [`background_listening.dart`](../lib/background_listening.dart#L437)); there is no single application-wide owner/queue. SQLite transactions protect individual operations, but that is weaker than the stated decision. |
| 76 | Recover from malformed events | Verified | Parser returns null and stream continues; parser/controller tests ([`topic_feed.dart`](../lib/topic_feed.dart#L141), [`topic_feed_test.dart`](../test/topic_feed_test.dart#L11)). |
| 77 | Actionable server/publish errors | Verified | Typed network/status messages and visible feed error labels ([`publish.dart`](../lib/publish.dart#L78), [`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L1003)). |
| 78 | Portable delivery behavior in Dart | Verified | Parsing, reconnect, ingestion, retention, and grouping live in Dart; Kotlin hosts lifecycle and notifications only ([`background_listening.dart`](../lib/background_listening.dart#L204)). |
| 79 | Core testable with in-memory adapters | Verified | Repository/client/host/notification seams are exercised throughout `test/` (for example [`background_listening_test.dart`](../test/background_listening_test.dart#L13)). |
| 80 | Controllable local ntfy end-to-end | Partial | Loopback HTTP acceptance is automatic ([`http_acceptance_test.dart`](../test/http_acceptance_test.dart#L16)); real ntfy acceptance is environment-gated and skipped by default ([`real_ntfy_acceptance_test.dart`](../test/real_ntfy_acceptance_test.dart#L15)). Android lifecycle remains device-only. |

## Implementation-decision matrix

| Spec lines | Decision | Result |
|---|---|---|
| 108–109 | Standalone app and fixed `com.rahul1115.ntfy_flutter` identity | Verified: Gradle namespace/application id match ([`build.gradle.kts`](../android/app/build.gradle.kts#L7)). |
| 110 | Flutter owns portable app behavior | Verified for implemented MVP behavior; the native host contains lifecycle/notification integration only. |
| 111–112 | One deep domain module with two conceptual command/state operations | Partial: feature sessions expose typed commands/state, but screens depend on several feature-specific repositories/sessions rather than one application-core interface ([`main.dart`](../lib/main.dart#L62), [`topic_feed.dart`](../lib/topic_feed.dart#L252)). |
| 113 | Same Dart core in foreground/background | Verified: both runtimes use the same store, stream parser, ingestion, notification, and retention types ([`background_listening.dart`](../lib/background_listening.dart#L437)). |
| 114–116 | Thin native host and narrow testable platform seam | Partial: native responsibilities are properly narrow, but background-host and message-notification channels are separate seams rather than the specified single platform seam ([`MainActivity.kt`](../android/app/src/main/kotlin/com/rahul1115/ntfy_flutter/MainActivity.kt#L17)). Both have Dart fakes. |
| 117–119 | Dart SQLite, serialized access, one authoritative store, primitive seam values | Partial only for global serialization (story 75); one SQLite schema is authoritative and channel values are primitives. |
| 120 | Native app is behavioral reference; adapted host source retains notices | No copied portable upstream module was identified. License/attribution still needs release review if source/assets are later copied. |
| 121 | Android only | Verified by platform project/scope. |
| 122 | Anonymous only; protected topics not silently accepted | Verified for credential-bearing URLs (explicitly rejected) and publish denial errors ([`subscriptions.dart`](../lib/subscriptions.dart#L411), [`publish.dart`](../lib/publish.dart#L101)). |
| 123–125 | Complete canonical URL, HTTP(S), NDJSON HTTP stream | Verified ([`subscriptions.dart`](../lib/subscriptions.dart#L399), [`topic_feed.dart`](../lib/topic_feed.dart#L60)). |
| 126–127 | Grouped background listener; bounded reconnect and network refresh | Verified statically/unit-level; network callback remains device pending. |
| 128–131 | Global opt-in, ongoing notification, minimal declarations, contextual permission | Implemented; Android outcomes remain device pending. Manifest declarations are limited to internet/network/service/notifications/boot ([`AndroidManifest.xml`](../android/app/src/main/AndroidManifest.xml#L1)). |
| 132–133 | Server ID/cursor idempotency and stream-authoritative publish | Verified. |
| 134–141 | Composer fields, feed order, local names/removal, retention policies/cleanup | Verified, including the intentional newest-at-bottom divergence from native. |
| 142 | Loading/empty/live/reconnecting/offline/error without hiding data | Verified. |
| 143 | Close source UI parity | Partial: see screen audit and top presentation gaps. |
| 144 | Dependencies only when standard facilities are insufficient | Verified: implementation uses Dart/Flutter/Android facilities plus SQLite; no speculative UI/state dependency was added. |

## Screen-by-screen parity audit

| Surface | Matches | Actual gaps | Intentional differences |
|---|---|---|---|
| Topic list | Same title, list/empty-state split, SMS motif, count/last activity/unread row hierarchy, latest-activity ordering, overflow, bottom-end add FAB, and destructive confirmation; source palette is carried over ([`activity_main.xml`](../../ntfy-android/app/src/main/res/layout/activity_main.xml#L257), [`fragment_main_item.xml`](../../ntfy-android/app/src/main/res/layout/fragment_main_item.xml#L16), [`main.dart`](../lib/main.dart#L372)). | Flutter lacks the native pull-to-refresh gesture/network banner pattern; automatic refresh and feed connection state cover the required MVP behavior, so this is a minor interaction/visual difference rather than a missing story. | Flutter adds spec-required topic swipe; native uses selection/action mode. Native notification-state icons, mute/bell, and docs/rate/report items are beyond narrowed MVP. |
| Add subscription | Clear description, inline validation, busy state, URL entry. | Compact alert instead of native full-screen Material composition/progress toolbar. | Complete URL + local display name replace native topic/server/instant-delivery fields by explicit MVP decision. |
| Topic feed | Same separate topic surface, gray light feed background, card list, empty illustration, compact composer, overflow cleanup/settings actions ([`activity_detail.xml`](../../ntfy-android/app/src/main/res/layout/activity_detail.xml#L17), [`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L401)). | Empty instructions are abbreviated; Flutter displays connection text under the toolbar instead of native transient banners/state icons. | Oldest-to-newest/newest-bottom and away-from-bottom indicator are explicit MVP behavior. Search, test message, copy URL, mute/bell, attachments/actions are out of scope. |
| Message card | Closely matches 6dp side spacing, 3dp radius, timestamp/title/body/tags hierarchy ([`fragment_detail_item.xml`](../../ntfy-android/app/src/main/res/layout/fragment_detail_item.xml#L2), [`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L599)). | Generic priority symbols/text replace five source icons; source per-card overflow/tap-copy/multi-select are absent. | Attachments, rich Markdown, action buttons, click URLs, and remote icons are explicitly out of scope. Swipe-delete with Undo matches native behavior ([`DetailActivity.kt`](../../ntfy-android/app/src/main/java/io/heckel/ntfy/ui/DetailActivity.kt#L355)). |
| Compact composer | Rounded input, expand control, 48dp circular send action, up-to-four-line message match native closely ([`view_message_bar.xml`](../../ntfy-android/app/src/main/res/layout/view_message_bar.xml#L13), [`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L657)). | No material gap found. | Flutter rejects empty input as the MVP requires; current native code allows it. |
| Full composer | Full-screen surface, close/publish toolbar, persistent message field, filter chips for title/tags/priority, five priority choices, progress/error preservation match the source organization ([`fragment_publish_dialog.xml`](../../ntfy-android/app/src/main/res/layout/fragment_publish_dialog.xml#L279), [`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L838)). | Source uses priority-specific icons in its dropdown; Flutter uses text-only items. | Markdown, click/email/delay/attachments/call chips are out of scope. |
| Global settings | Back-navigable list, section header typography, retention under Notifications, background notification controls. | The new global background-listener controls have no exact native screen counterpart, so only internal hierarchy—not pixel identity—can be compared. | Native default server/users/language/dynamic colors/backup/protocol/certs/broadcast/UnifiedPush/logging/about settings are out of scope. MVP retention values/default intentionally differ. |
| Topic settings | Notification retention, local display name, and immutable topic URL follow native Notifications/Appearance/About organization ([`detail_preferences.xml`](../../ntfy-android/app/src/main/res/xml/detail_preferences.xml#L3), [`retention_settings.dart`](../lib/retention_settings.dart#L29)). | The Flutter screen is much sparser because the native screen's notification controls are excluded. No in-scope control is missing. | Instant delivery, mute, minimum priority, insistent alerts, custom/dedicated channels, and subscription icon are not MVP requirements. |
| Destructive dialogs/snackbars | Topic/message cleanup uses confirmation or Undo and error snackbars; wording is actionable. | No material in-scope gap found. | Flutter confirms topic swipe whereas native confirms action-mode removal. |

### Typography, colors, icons, and spacing

- The principal light/dark tokens match the source resources: light primary `#338574`, dark primary `#84D6C2`, light surface `#FFFFFF`, light feed `#EEEEEE`, dark background `#121212`, and dark high container `#282F33` ([`colors.xml`](../../ntfy-android/app/src/main/res/values/colors.xml#L3), [`colors.xml` dark](../../ntfy-android/app/src/main/res/values-night/colors.xml#L3), [`main.dart`](../lib/main.dart#L14)).
- Flutter relies on Material 3 type roles rather than copying AppCompat type styles. The observable hierarchy—small timestamp/tags, medium body/title, bold optional title, emphasized settings section—is aligned. Exact font metrics and increased text scaling remain device/manual checks.
- Core add/send/SMS/delete/priority semantics are recognizable Material icons. Priority-specific native assets are the concrete icon gap. Attachments, custom subscription icons, notification-state icons, and search icons correspond to excluded features.
- Feed cards intentionally mirror the source's tight 6dp horizontal / 3dp-radius layout. Topic-row/add-dialog spacing is less faithful because Flutter uses `ListTile` defaults and `AlertDialog` rather than the source's explicit 18dp row padding and full-screen dialog.

## Screenshot-by-screenshot native reference audit

The nine captures in [`androdu_version_ref`](androdu_version_ref/) are treated as visual primary evidence for the captured native-app state. The sibling XML/Kotlin source remains authoritative for behavior that a still image cannot establish. `Covered` means the corresponding MVP surface or behavior belongs to issues #9, #10, or #11; it does not mean the deferred Android-device acceptance has run. `New` identifies full-port work that is outside those three tickets.

| Native capture | Native implementation | Current Flutter mapping | Parity finding | Ticket classification |
|---|---|---|---|---|
| [`home page.jpg`](<androdu_version_ref/home page.jpg>) | Root toolbar/list/empty/FAB ([`activity_main.xml`](../../ntfy-android/app/src/main/res/layout/activity_main.xml#L257)); topic-row hierarchy ([`fragment_main_item.xml`](../../ntfy-android/app/src/main/res/layout/fragment_main_item.xml#L2)); row binding ([`MainAdapter.kt`](../../ntfy-android/app/src/main/java/io/heckel/ntfy/ui/MainAdapter.kt#L74)). | `SubscriptionsScreen`, toolbar, ordered topic rows, metadata/unread badge, overflow, and add FAB ([`main.dart`](../lib/main.dart#L164), [`main.dart`](../lib/main.dart#L410), [`main.dart`](../lib/main.dart#L458)). | The captured title, SMS motif, topic/display name, total-notification subtitle, and add placement are represented. Flutter does not expose the captured toolbar mute/bell state, native per-row notification-state/custom subscription icons, pull-to-refresh gesture, or `Everything is up to date` refresh feedback. | Base list/metadata/order/unread and the minor refresh/feedback comparison: **#11 covered**. Notification policy controls and selectable custom subscription icons: **New**; not #9's basic message-alert scope. |
| [`home page options.jpg`](<androdu_version_ref/home page options.jpg>) | Root overflow defines settings plus rate/docs/report actions ([`menu_main_action_bar.xml`](../../ntfy-android/app/src/main/res/menu/menu_main_action_bar.xml#L10)). | Root overflow opens Settings ([`main.dart`](../lib/main.dart#L393)). | The captured Settings entry exists. `Rate the app` does not. | Settings: **#11 covered**. Rate action/store integration: **New**, low-priority non-core parity. |
| [`topic.jpg`](<androdu_version_ref/topic.jpg>) | Feed toolbar, empty instruction/example, list, and composer ([`activity_detail.xml`](../../ntfy-android/app/src/main/res/layout/activity_detail.xml#L11)); search/notification/menu actions ([`menu_detail_action_bar.xml`](../../ntfy-android/app/src/main/res/menu/menu_detail_action_bar.xml#L4)); compact composer ([`view_message_bar.xml`](../../ntfy-android/app/src/main/res/layout/view_message_bar.xml#L8)). | Topic toolbar/status, empty state, chronological list, compact composer, and overflow ([`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L401), [`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L657)). | Core hierarchy is close. Flutter abbreviates the captured empty instructions by omitting the concrete topic-specific curl example/link and puts connection state below the toolbar. It has neither toolbar search nor mute/bell action. The capture's blue dynamic-color action differs from Flutter's fixed source palette. | Feed/composer, empty-state completion, and palette comparison: **#11** (the curl/example omission remains a presentation gap; dynamic color is an intentional MVP difference). Search and notification policy controls: **New**. |
| [`topic_options.jpg`](<androdu_version_ref/topic_options.jpg>) | Topic overflow contains subscription settings, clear, test, and unsubscribe (plus conditional copy URL in source) ([`menu_detail_action_bar.xml`](../../ntfy-android/app/src/main/res/menu/menu_detail_action_bar.xml#L31)); destructive flows ([`DetailActivity.kt`](../../ntfy-android/app/src/main/java/io/heckel/ntfy/ui/DetailActivity.kt#L878)). | Overflow contains Subscription settings, Clear all notifications, and Unsubscribe ([`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L451)). | Three captured actions and their confirmation flows exist. Flutter reasonably disables Clear when the feed is empty whereas the capture leaves it enabled. `Send test notification` is absent. | Settings/clear/unsubscribe and the empty-state enablement decision: **#11 covered**. Test notification (and source's conditional copy-URL utility): **New**; neither is required by #9. |
| [`topic settings.jpg`](<androdu_version_ref/topic settings.jpg>) | Per-topic Notifications/Appearance/About preferences ([`detail_preferences.xml`](../../ntfy-android/app/src/main/res/xml/detail_preferences.xml#L3)); retention/rename/URL behavior ([`DetailSettingsActivity.kt`](../../ntfy-android/app/src/main/java/io/heckel/ntfy/ui/DetailSettingsActivity.kt#L296), [`DetailSettingsActivity.kt`](../../ntfy-android/app/src/main/java/io/heckel/ntfy/ui/DetailSettingsActivity.kt#L392)). | Topic settings expose Display name, Delete notifications, and Topic URL ([`retention_settings.dart`](../lib/retention_settings.dart#L29), [`retention_settings.dart`](../lib/retention_settings.dart#L96), [`retention_settings.dart`](../lib/retention_settings.dart#L112)). | Retention, local rename, immutable URL, section hierarchy, and summaries map directly. Flutter's sparse group order differs from the captured Notifications → Appearance → About order. Captured per-topic instant delivery, mute, minimum priority, highest-priority insistent alert, custom notification settings, and subscription icon are absent. | Retention/rename/URL and sparse ordering: **#11 covered**. Global listener lifecycle behind the app-wide replacement: **#10 covered**, device pending. Exact per-topic delivery and all per-topic notification/icon preferences: **New**; #9 only delivers basic alerts. |
| [`app_settings.jpg`](<androdu_version_ref/app_settings.jpg>) | Global preference groups span Notifications, General, Appearance, Backup/restore, Advanced, and About ([`main_preferences.xml`](../../ntfy-android/app/src/main/res/xml/main_preferences.xml#L3)); channel shortcut behavior ([`SettingsActivity.kt`](../../ntfy-android/app/src/main/java/io/heckel/ntfy/ui/SettingsActivity.kt#L260)). | Global settings expose retention and the MVP background-listening switch/explanation/channel shortcut ([`retention_settings.dart`](../lib/retention_settings.dart#L144), [`retention_settings.dart`](../lib/retention_settings.dart#L301), [`retention_settings.dart`](../lib/retention_settings.dart#L315)). | Captured Delete notifications maps to Flutter, although its default/options intentionally follow the MVP. Background-listener controls are a narrowed replacement without a pixel-identical native row. Mute/minimum priority/download/insistent/channel policy, default server/users/language, explicit appearance controls, backup/restore, protocol/headers/certificates/broadcast/UnifiedPush/logs, and About rows are absent. | Retention: **#11 covered**. Background service/channel/recovery: **#9/#10 covered**, device pending. All other captured preference families: **New** full-port backlog. |
| [`attachment.jpg`](<androdu_version_ref/attachment.jpg>) | Despite its filename, the capture shows the expanded publish composer, not a received attachment. Native provides message plus toggle chips for Markdown, title, tags, priority, click URL, email, delay, attach URL/local file, and phone call ([`fragment_publish_dialog.xml`](../../ntfy-android/app/src/main/res/layout/fragment_publish_dialog.xml#L18), [`fragment_publish_dialog.xml`](../../ntfy-android/app/src/main/res/layout/fragment_publish_dialog.xml#L279)); publish handling is in [`PublishFragment.kt`](../../ntfy-android/app/src/main/java/io/heckel/ntfy/ui/PublishFragment.kt#L494). | Flutter has the full-screen close/publish shell, message field, and optional Title/Tags/Priority chips ([`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L798), [`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L898), [`topic_feed_screen.dart`](../lib/topic_feed_screen.dart#L965)). | The common composer hierarchy and MVP fields match. Fine spacing/icon/dropdown comparison remains in #11. Markdown, click URL, email, delay, URL/local attachments, and call actions are missing; native priority choices also use dedicated icons. | Message/title/tags/five priorities and composer shell: **#11 covered**, with priority-icon presentation still a #11 visual gap. Every other captured chip and attachment flow: **New**. |
| [`search_in_topic.jpg`](<androdu_version_ref/search_in_topic.jpg>) | Search expands across the toolbar and filters the topic's database-backed list ([`menu_detail_action_bar.xml`](../../ntfy-android/app/src/main/res/menu/menu_detail_action_bar.xml#L4), [`DetailActivity.kt`](../../ntfy-android/app/src/main/java/io/heckel/ntfy/ui/DetailActivity.kt#L584), [`Database.kt`](../../ntfy-android/app/src/main/java/io/heckel/ntfy/db/Database.kt#L590)). | Flutter retains the normal topic toolbar and has no search query/state/filter surface; its feed/empty/composer beneath it maps to the non-search portions of the capture. | The captured expanded query field, filtered results, and no-results state are absent. | Underlying feed/composer: **#11 covered**. Topic message search: **New**, explicitly outside the MVP and all three tickets. |
| [`topic_snooz_seeting.jpg`](<androdu_version_ref/topic_snooz_seeting.jpg>) | Per-topic mute opens a duration dialog with 30 minutes, 1/2/8 hours, tomorrow, and resume choices ([`fragment_notification_dialog.xml`](../../ntfy-android/app/src/main/res/layout/fragment_notification_dialog.xml#L12), [`NotificationFragment.kt`](../../ntfy-android/app/src/main/java/io/heckel/ntfy/ui/NotificationFragment.kt#L39), [`values.xml`](../../ntfy-android/app/src/main/res/values/values.xml#L59)). | No Flutter screen or dialog maps to this notification-policy state. | Entire captured snooze/mute workflow is absent. It is distinct from suppressing duplicate alerts or suppressing alerts while the feed is visible. | **New** notification-policy feature. It is not covered by #9, #10, or #11. |

### Feature-parity backlog exposed by the captures

These are not blockers for the narrowed MVP tickets, but they are real gaps against the user's longer-term exact-port goal.

| Priority | Feature cluster | Capture/source evidence | Existing-ticket relation | Suggested future ticket boundary |
|---:|---|---|---|---|
| 1 | Notification policy and snoozing | [`topic settings.jpg`](<androdu_version_ref/topic settings.jpg>), [`topic_snooz_seeting.jpg`](<androdu_version_ref/topic_snooz_seeting.jpg>), and global notification preferences ([`main_preferences.xml`](../../ntfy-android/app/src/main/res/xml/main_preferences.xml#L3)). | #9 supplies basic priority-mapped alerts, dedupe, routing, and visible-feed suppression; #10 supplies service recovery. Neither supplies policy UI/semantics. | Global and per-topic mute schedules, minimum priority, insistent-highest behavior, download policy, and native channel controls. |
| 2 | Topic message search | [`search_in_topic.jpg`](<androdu_version_ref/search_in_topic.jpg>) and native query handling ([`DetailActivity.kt`](../../ntfy-android/app/src/main/java/io/heckel/ntfy/ui/DetailActivity.kt#L584)). | New; explicitly excluded from #11 MVP. | Search toolbar lifecycle, persisted-message filtering, no-results state, clearing/back behavior, and tests. |
| 3 | Advanced publishing and attachments | [`attachment.jpg`](<androdu_version_ref/attachment.jpg>) and publish layout ([`fragment_publish_dialog.xml`](../../ntfy-android/app/src/main/res/layout/fragment_publish_dialog.xml#L279)). | #11 covers message/title/tags/priority only. | Markdown, click/email/delay/call actions, URL/local attachment picking/upload, progress, permission/error/retry, and received-attachment rendering. |
| 4 | Exact per-topic delivery controls | [`topic settings.jpg`](<androdu_version_ref/topic settings.jpg>) and native instant-delivery preference ([`detail_preferences.xml`](../../ntfy-android/app/src/main/res/xml/detail_preferences.xml#L6)). | #10 implements the MVP's global opt-in foreground listener, not native per-topic selection. | Per-subscription listener eligibility, summaries/service regrouping, persistence, and migration from the global switch. |
| 5 | Remaining settings families | [`app_settings.jpg`](<androdu_version_ref/app_settings.jpg>) and native preference tree ([`main_preferences.xml`](../../ntfy-android/app/src/main/res/xml/main_preferences.xml#L3)). | New; outside #9/#10/#11. | Split into coherent tickets: servers/users/auth, appearance/localization, backup/restore, advanced networking/security, integrations/logging, and About. |
| 6 | Native utility actions and refresh affordances | [`home page.jpg`](<androdu_version_ref/home page.jpg>), [`home page options.jpg`](<androdu_version_ref/home page options.jpg>), [`topic_options.jpg`](<androdu_version_ref/topic_options.jpg>). | Pull-to-refresh/status feedback is a documented **#11** interaction difference. Test notification, conditional copy URL, and rate-app are **New**. | If exact parity is required, separate refresh/status behavior from the lower-priority notification/store-facing utility actions. |

Issue #10's most important acceptance criteria—process/service recreation, boot restore, network recovery, and foreground-service notification behavior—are not directly provable from any of these screenshots. They remain in the device-only checklist rather than being inferred from visual similarity.

## Intentional MVP scope differences (future full-port gaps)

The following are intentional relative to issues #9–#11, so they do not block those tickets. They are still gaps against a later exact native-app port and should not be mistaken for final product parity.

| Native behavior/surface | Why it is not an MVP gap |
|---|---|
| Split topic/server subscription entry, default-server selection | MVP explicitly requires one complete URL. |
| Native newest-first feed and scroll-to-position-0 | MVP explicitly requires chronological oldest-to-newest with latest at bottom. |
| Topic removal via long-press/action mode | MVP explicitly chooses swipe plus confirmation/undo. |
| FCM/instant per-topic delivery, WebSockets, UnifiedPush | Deferred by the protocol/delivery scope. Global foreground listening is the MVP replacement. |
| Authentication/users/tokens, custom headers/certificates | Explicitly out of scope. Credential-bearing URLs are rejected. |
| Search, rich Markdown, attachments, actions, click URLs, delayed/email/call publishing | Explicitly out of scope. |
| Per-topic mute/min-priority/insistent/custom channel controls, test notification | Advanced notification behavior is outside the MVP's five priority channels and basic local alerts. |
| Share targets/deep links, broadcast interfaces, backup/restore, localization picker, rate/docs/report links | Explicitly out of scope or non-core native surfaces. |
| Pixel-perfect legacy/XML rendering | Explicitly excluded; close visual and interaction similarity remains the bar. |

## Automated verification

The last stable pre-audit baseline reported in this work session was:

| Command | Status |
|---|---|
| `flutter test` | Passed 77 tests; the real-server acceptance test was intentionally skipped without its environment flag. |
| `flutter analyze` | Clean. |
| Android debug APK compile | Passed. |
| Android instrumentation-test APK compile | Passed. |
| Android instrumentation/device execution | Not run; no emulator/device was connected. |

Current-tree audit runs on 2026-08-18:

| Command | Status |
|---|---|
| `flutter analyze` | Passed: `No issues found`. |
| `flutter test` | The pre-fix run found the rename controller defect. A final post-fix full-suite rerun is pending in the parent task; the real-server test remains environment-gated when `NTFY_BIN` is unset. |
| `flutter test test/widget_test.dart --plain-name "topic settings rename only the local display name"` | Passed after removal of the premature controller disposal (reported by the implementing parent task). |

The audit itself is read-only except for this report. The parent task will run the final `flutter analyze`, `flutter test`, `flutter build apk --debug`, and `android\\gradlew.bat app:assembleDebugAndroidTest` checks. Compilation is evidence of wiring only; it does not replace the device checklist below.

### Testing-decision coverage

| Spec area | Result |
|---|---|
| Observable/highest practical seams | Mostly met: widget, repository, loopback HTTP, platform adapter, and instrumentation seams are used instead of private implementation assertions. |
| Running app + controllable local ntfy server | Partial: loopback protocol tests run automatically; the real ntfy-server scenario is opt-in, and notification/lifecycle completion needs Android. |
| Presentation through in-memory domain adapters | Broad coverage exists for subscription, removal, feed ordering/states, publish, retention, listener settings, notification routing/visibility, rename, and unread behavior. The focused rename test passes; the final aggregate rerun is pending. |
| Core command/state behavior | Broadly met for parsing, persistence, idempotency, cursor, cleanup, retention, reconnect, publishing, listener enable/disable. The intended single app-wide command/state facade itself was not implemented. |
| Native host only through platform/integration seam | Met structurally; execution on Android is pending. |
| Protocol cases | Normal/title/priorities/tags/keepalive/malformed/disconnect/reconnect/duplicate paths are covered across parser, controller, notification, and HTTP tests. |
| Publish acceptance | Met: request fields and stream-authoritative single insertion are covered. |
| Android integration and lifecycle | Compiles but device execution is pending for permissions, taps, service notification, stop, suppression, process death, network changes, and reboot. |
| Database lifecycle regression | Loopback/integration code covers independent runtime restart without closing the UI store; repeated actual background/resume/service transitions remain device-only. |
| Retention controlled-clock matrix | Met for every duration, inheritance, override, cutoff, and scope. |
| UI parity comparisons | Partial: source code/resources and local native reference captures were reviewed; no repeatable screenshot/golden comparison exists. |
| Accessibility | Partial: semantic labels and selected touch targets are tested; traversal order, all targets, large text, and TalkBack operation remain. |
| Emulator + physical + restrictive OEM release gate | Not met by design in this pass; explicitly deferred to the device phase. |

## Device-only manual checklist

Do these only after all ticket implementation and non-device checks pass. Use a current Android emulator first, then one physical device; add a battery-restrictive OEM device if available.

### Installation, appearance, and accessibility

- [ ] Fresh install opens directly to the anonymous empty state; no account prompt or migration appears.
- [ ] Compare topic list, add flow, feed, composer, global settings, topic settings, dialogs, cards, typography, colors, icons, and spacing side by side with the native app in light and dark modes.
- [ ] Rotate/change window size where supported; ensure dialogs, composer, errors, and message cards remain usable.
- [ ] Set system font/display size high; verify no clipped toolbar status, priority metadata, composer controls, settings summaries, or destructive actions.
- [ ] With TalkBack, verify logical traversal and spoken names/state for add, topic rows/unread badge, overflow actions, settings choices, message metadata/delete action, composer chips, publish progress/error, and new-message action.
- [ ] Confirm every primary action has an approximately 48dp touch target.

### Subscription, feed, and persistence

- [ ] Add HTTP and HTTPS topics (including a self-hosted non-default port), trim whitespace, reject malformed/duplicate/authenticated URLs, rename locally, and confirm URL/publish target are unchanged.
- [ ] Receive into several topics; confirm unread badges update while on the list and clear only when the corresponding feed is viewed.
- [ ] Confirm latest-activity topic ordering and count/date/unread row metadata match the native hierarchy with real incoming messages.
- [ ] Verify newest-at-bottom initial position, at-bottom auto-follow, away-from-bottom anchor preservation, and `New messages` action with long feeds.
- [ ] Disable networking: stored messages remain, state becomes offline/retrying, and recovery resumes without duplicate rows.
- [ ] Swipe-delete/Undo one message, clear one topic, and remove one subscription; confirm other topics and the remote server are unaffected.
- [ ] Restart the app and verify subscriptions, names, unread state, messages, cursor behavior, listener preference, and retention policy persist.

### Publishing and retention

- [ ] Quick-publish and full-publish message/title/all five priorities/tags; verify the server receives exact fields and the stream adds exactly one local row.
- [ ] Force unreachable, denied, timeout, and oversized-message failures; confirm actionable text and preserved retryable draft.
- [ ] Exercise global Never/all finite durations and one inheriting/overridden topic with controlled old messages; verify cleanup scope while the app is foregrounded and backgrounded.

### Notifications and Android lifecycle

- [ ] Enable background listening from its explanatory setting; verify permission appears only then on Android 13+.
- [ ] Deny permission; confirm foreground/background ingestion and in-app history continue. Grant later and confirm alerts begin.
- [ ] Verify exactly one ongoing low-importance listener notification while enabled, its channel-settings shortcut, and complete removal/service stop when disabled.
- [ ] Send all five priorities and inspect channel id/importance, sound/vibration, title/body/time, auto-cancel, and absence of duplicate alerts across reconnect/replay.
- [ ] Keep the target feed visible and send a message: card appears, no system alert. Cover app resumed/inactive/background transitions and a settings route over the feed.
- [ ] Tap a notification for a recent and a far off-screen older message from foreground, background, and terminated states; verify the exact topic and message context are revealed once.
- [ ] Enable background listening, background/terminate the process, send messages, and confirm delivery. Repeat after Android recreates the service.
- [ ] Toggle Wi-Fi/mobile data and airplane mode repeatedly; verify bounded recovery, no parallel duplicate listeners, and no duplicate storage/notifications.
- [ ] Reboot with listening enabled and disabled; verify it resumes only for the enabled case and does not surface hidden work for the disabled case.
- [ ] Repeatedly background/resume the UI while restarting/stopping the listener; verify no closed-database errors, corruption, missing rows, or stale UI.

## Exit criteria

Issue #11 can be considered statically complete when the final four non-device commands pass and every `Partial` item is either fixed or explicitly accepted as a documented follow-up. MVP release parity still requires the device checklist, including at least one current emulator and one physical device as required by the spec ([`android-first-mvp-spec.md`](android-first-mvp-spec.md#L146)).
