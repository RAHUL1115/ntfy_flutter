# Official ntfy Android feature and settings audit

## Scope, provenance, and reading guide

This is a primary-source audit of the official `binwiederhier/ntfy-android` working tree and a planning comparison with the independent `ntfy_flutter` working tree. It does **not** treat a translated label or historical changelog entry as proof of behavior: preferences were followed into Kotlin, repository defaults, notification/service code, the manifest, database queries, and build-flavor flags. No secondary articles were used.

- **Official app revision audited:** clean `ntfy-android` checkout at [`51730a0f06cebfad59f1b7bc0cb6d5c47082b032`](https://github.com/binwiederhier/ntfy-android/tree/51730a0f06cebfad59f1b7bc0cb6d5c47082b032), commit date **2026-07-09 22:45:41 +02:00**, subject “Fix remaining bug on connection lost alert.” The build identifies itself as **1.25.2 (version code 63)** and targets Android 36, minimum 26 (`app/build.gradle:L15-L21`).
- **Flutter comparison snapshot:** the `ntfy_flutter` working tree on **2026-08-16**. At audit time it had no commits, so Flutter citations are working-tree line ranges, not immutable links.
- **Citation convention:** `Android: path:Lx-Ly` means a path relative to `ntfy-android`; `Flutter: path:Lx-Ly` means a path relative to `ntfy_flutter`. Important Android citations are also linked to the pinned commit. For compact table citations, Android Kotlin basenames resolve under `app/src/main/java/io/heckel/ntfy/` by class package: UI (`ui/`), database (`db/`), messaging (`msg/`), service (`service/`), workers (`work/`), UnifiedPush (`up/`), utilities (`util/`), backup (`backup/`), and application (`app/`). Resource basenames resolve under `app/src/main/res/xml/` or `app/src/main/res/values/`; flavor Firebase paths are written in full.
- **Tests:** the official repository contains no Kotlin `@Test` sources in this checkout. `TESTING.md:L1-L22` is a manual checklist covering subscription variants, priorities/tags/titles, global/per-topic mute, instant delivery, clear, test publish, and multi-delete. It supports intended workflows but is not automated evidence. Flutter does have protocol, database, delivery-helper, and widget tests (`test/ntfy_client_test.dart:L10-L172`, `test/app_database_test.dart:L23-L229`, `test/delivery_service_test.dart:L6-L19`, `test/widget_test.dart:L6-L31`).

## Executive summary

The official app is much more than a topic reader. Its core is a local Room-backed subscription/feed client with cached-history polling, live FCM or foreground streaming, publishing, Android notifications, rich message rendering, attachments, action buttons, sharing/deep links, per-server credentials and TLS material, backup/restore, diagnostics, and UnifiedPush distributor support. The actual global settings hierarchy has six sections and 25 visible or conditionally visible rows; ordinary subscription settings declare 11 rows across three sections, with at most 10 visible because Set/Remove icon are mutually exclusive.

The Flutter client already covers the minimal loop well: validated topic URLs, anonymous/Basic/Bearer auth, initial history import, deduplicated local feeds, unread counts, WebSocket foreground delivery, notification taps, plain-text publishing, refresh, rename, local clear/delete/unsubscribe, and richer configurable retention than upstream. Its largest **reliability/parity gaps** are recovery behavior, network-transition handling, catch-up polling after prolonged service loss, message update/delete/clear sequence semantics, and notification priority/mute behavior; boot delivery remains an explicit non-goal. Its largest **content gaps** are rich metadata/rendering, attachments, actions, and advanced composer fields.

For the project’s minimal Android-first direction, do not clone the official app’s entire surface. Prioritize delivery correctness and core message semantics; add title/priority/tags and search next. Treat FCM, UnifiedPush distribution, mTLS/pinning, custom proxy headers, log upload, full backup compatibility, and elaborate channel matrices as opt-in needs, not baseline parity.

The official app is **Apache-2.0** (`README.md:L17-L18`, `LICENSE:L1-L2`). This report describes behavior only; no ntfy-android code should be copied into the independent Flutter client.

## 1. Complete user-facing feature inventory

### Subscriptions and topic management

- Subscribe by topic plus a default or alternate server. The dialog validates duplicate/reserved topics, validates URL/topic syntax, remembers servers for autocomplete, probes read authorization, offers login if required, and can present a certificate trust flow after an SSL failure. `docs`, `static`, and `file` are blocked topic names. ([Android: `AddFragment.kt:L210-L342`](https://github.com/binwiederhier/ntfy-android/blob/51730a0f06cebfad59f1b7bc0cb6d5c47082b032/app/src/main/java/io/heckel/ntfy/ui/AddFragment.kt#L210-L342), [`AddFragment.kt:L364-L438`](https://github.com/binwiederhier/ntfy-android/blob/51730a0f06cebfad59f1b7bc0cb6d5c47082b032/app/src/main/java/io/heckel/ntfy/ui/AddFragment.kt#L364-L438), `AddFragment.kt:L515-L515`.)
- The subscription list shows display name, message count, last activity, unread badge (capped at 99+), mute/instant/connection-error indicators, subscription icon, and UnifiedPush ownership. Topics are ordered by UnifiedPush status and most recent message. (Android: `MainAdapter.kt:L79-L159`; `Database.kt:L493-L515`.)
- Add triggers cached-history polling and opens the feed; pull-to-refresh polls all topics. Long-press supports multi-unsubscribe with confirmation; per-topic unsubscribe removes its local notifications and FCM topic membership. (Android: `MainActivity.kt:L701-L795`, `MainActivity.kt:L834-L855`; `MainViewModel.kt:L24-L51`.)
- Per-topic management includes custom display name, local icon, mute, minimum notification priority, auto-delete, max-priority insistence, dedicated Android channels, instant delivery where applicable, and copyable topic URL. UnifiedPush-managed subscriptions expose only display name/topic URL, not normal notification controls. (Android: `detail_preferences.xml:L3-L74`; `DetailSettingsActivity.kt:L136-L151`.)
- `ntfy://` deep links can create and open a subscription; `secure` defaults true, custom port is honored, and `display` can set the local display name. (Android: `AndroidManifest.xml:L48-L63`; `DetailActivity.kt:L202-L275`.)

### Message feed and display

- Each feed is newest-first in the official app, auto-scrolls to index 0 for arrivals, supports pull-to-refresh, and searches case-insensitively over title, message, and tags. (Android: `Database.kt:L590-L604`; `DetailActivity.kt:L326-L387`; `DetailViewModel.kt:L13-L35`.)
- Rows show timestamp, optional title, body, unmatched text tags, priority icon, downloaded icon, attachment, action buttons, and a “new” dot. Plain text auto-links web URLs; Markdown uses Markwon. (Android: `DetailAdapter.kt:L104-L166`, `DetailAdapter.kt:L176-L249`.)
- Tap opens the message click URL when present; otherwise it copies decoded content. Long-press enables multi-select copy/delete. Swipe deletes locally with Undo. “Clear all” marks every message in that topic deleted without unsubscribing. (Android: `DetailActivity.kt:L360-L378`, `DetailActivity.kt:L878-L899`, `DetailActivity.kt:L935-L1023`.)
- Opening a feed suppresses pop-up notifications for that topic and cancels existing popups; leaving marks all topic messages read. Server `message_delete` and `message_clear` events delete or mark read by `sequence_id`, and a newer message with the same sequence replaces the older local row. (Android: `DetailActivity.kt:L395-L407`, `DetailActivity.kt:L546-L566`; `Repository.kt:L119-L138`; `NotificationParser.kt:L16-L70`.)
- Body/title formatting supports tags-to-emoji and base64-encoded byte payloads through utility formatting; Markdown content is identified by `content_type`. (Android: `Message.kt:L7-L49`; `Database.kt:L146-L258`; `DetailAdapter.kt:L112-L124`.)

### Publishing and composer

- A configurable bottom message bar performs quick plain-text publish, including an empty message; disabling it replaces the bar with a FAB opening the full composer. (Android: `SettingsActivity.kt:L487-L506`; `DetailActivity.kt:L412-L497`.)
- The full composer supports message, optional title, tags, priorities 1–5, Markdown, click URL, e-mail, delayed delivery expression, phone call, remote attachment URL plus filename, or local file upload plus editable filename. Local and remote attachments are mutually exclusive. (Android: `PublishFragment.kt:L224-L259`, `PublishFragment.kt:L286-L389`, `PublishFragment.kt:L498-L568`.)
- Local-file upload has progress, cancellation, a five-minute HTTP timeout, and server-specific authorization/custom headers. Errors distinguish unauthorized, too large, structured server error, and generic transport failure. (Android: `PublishFragment.kt:L391-L425`, `PublishFragment.kt:L520-L620`; `ApiService.kt:L30-L112`.)
- “Send test notification” publishes randomized title/tags/priority to the current topic. (Android: `DetailActivity.kt:L722-L758`.)
- These are client controls for ntfy **server-side publish capabilities**; the app submits query parameters/body and reports the server result. It does not itself deliver e-mail/calls or execute delayed delivery. (Android: `ApiService.kt:L30-L112`.)

### Notifications and actions

- The app creates five default priority channels (min, low, default, high, max) and optionally five dedicated channels per subscription. High/max channels use stronger vibration; max bypasses DND by default subject to Android/user policy. Users configure sound/DND in Android channel settings. (Android: `NotificationService.kt:L59-L73`, `NotificationService.kt:L373-L408`; `SettingsActivity.kt:L260-L269`.)
- Global and per-topic mute support resume now, 30 minutes, 1/2/8 hours, tomorrow at 08:30, or until resumed. Global/per-topic minimum priority gates popup notification dispatch. (Android: `values.xml:L59-L106`; `SettingsActivity.kt:L176-L239`; `NotificationDispatcher.kt:L85-L96`.)
- Notifications use the original server timestamp, topic/message title, big-text or big-picture style, downloaded icon/subscription icon, attachment progress, and click URL or feed navigation. Max priority can alert continuously until dismissed. (Android: `NotificationService.kt:L84-L162`, `NotificationService.kt:L186-L205`.)
- Attachment actions include Download/Cancel, Open, and Browse downloads. Server-supplied actions support `view`, `copy`, `broadcast`, and arbitrary HTTP method/headers/body; successful `clear=true` actions dismiss and mark read. HTTP actions run through WorkManager for doze/network resilience and display progress/failure back in the notification/feed. (Android: `NotificationService.kt:L208-L321`; `UserActionManager.kt:L13-L32`; `UserActionWorker.kt:L34-L127`.)
- Incoming ordinary messages can also be broadcast to other Android apps, with decoded/string/byte message fields, tags, priority, mute status, and attachment metadata. A public `io.heckel.ntfy.SEND_MESSAGE` broadcast publishes message/title/tags/priority/delay. (Android: `BroadcastService.kt:L18-L120`; `AndroidManifest.xml:L136-L147`.)

### Background delivery and connectivity

- **Play flavor:** ntfy.sh topics can use FCM for lower-battery delayed delivery; “instant” uses the foreground connection. FCM handles message/update-delete/clear, keepalive service restart, and poll requests. **F-Droid:** Firebase is a dummy and all normal subscriptions require foreground delivery. (Android: `app/build.gradle:L54-L64`; `app/src/play/java/io/heckel/ntfy/firebase/FirebaseService.kt:L32-L212`; `app/src/fdroid/java/io/heckel/ntfy/firebase/FirebaseService.kt:L1-L12`.)
- Instant subscriptions are grouped into one connection per base URL, not one per topic. Users choose JSON stream over HTTP or WebSocket globally; credentials, headers, certificates, topic set, and manual retry state are part of connection identity so changes rebuild the connection. (Android: `SubscriberService.kt:L209-L307`.)
- Both protocols use incremental `since` cursors and reconnect backoff. JSON streaming retries with coroutine delays; WebSocket retries with exact `AlarmManager` alarms where allowed. Network loss closes sockets but leaves the foreground service alive with “Waiting for network”; default-network transitions force reconnection. (Android: `JsonConnection.kt:L36-L99`; `WsConnection.kt:L73-L196`; `SubscriberService.kt:L213-L227`; `Application.kt:L30-L69`.)
- WorkManager polls all subscriptions hourly as catch-up, restarts the service every three hours, and runs retention cleanup every eight hours. The foreground service is sticky and has destruction, boot, FCM keepalive, and periodic restart paths. (Android: `MainActivity.kt:L469-L529`, `MainActivity.kt:L881-L895`; `SubscriberService.kt:L49-L61`.)
- Optional connection-loss alerts trigger after 5m/15m/1h/3h/12h, avoid alerting while the device itself is offline, auto-dismiss after recovery, and offer 8-hour/24-hour snooze or Never. (Android: `values.xml:L171-L186`; `SubscriberService.kt:L336-L419`, `SubscriberService.kt:L528-L551`.)

### Authentication and security

- Basic username/password is stored per base URL and applied to auth checks, poll/stream, publish, and attachment downloads. Add-subscription probes anonymous/read access and asks for credentials only when needed; users can be added/edited/deleted centrally. (Android: `Database.kt:L259-L266`; `AddFragment.kt:L222-L342`; `HttpUtil.kt:L75-L89`.)
- Arbitrary per-server custom HTTP headers support authenticated proxies/tunnels/SSO. Reserved transport headers and duplicates are blocked; `Authorization` cannot coexist with a managed user. (Android: `CustomHeaderFragment.kt:L171-L248`; `HttpUtil.kt:L75-L89`.)
- Per-server PEM trust certificates can be pinned/imported and PKCS#12 client certificates with passwords can be used for mTLS; add/view/delete and expiry metadata are exposed in settings. SSL failure during subscription can prompt trust review. (Android: `CertificateSettingsFragment.kt:L43-L180`; `AddFragment.kt:L243-L307`; `CertUtil.kt:L35-L245`.)
- The app permits cleartext HTTP and trusts Android system plus user CAs. Managed usernames/passwords and client-certificate passwords are stored in the Room database and can be included in full backups; this is functional parity, not a recommendation for Flutter. (Android: `AndroidManifest.xml:L27-L35`; `network_security_config.xml:L1-L9`; `Database.kt:L259-L279`; `Backuper.kt:L215-L256`.)

### Attachments and media

- Incoming attachment metadata includes filename, MIME type, size, expiry, and URL. Auto-download can be Never, Always, or size-limited; missing size is attempted and the worker enforces limits. Message icons download independently. (Android: `Message.kt:L25-L33`; `NotificationDispatcher.kt:L57-L83`.)
- Feed actions can download/cancel, open with another app, copy URL, delete the local copy, or save into Downloads. Expired remote links are surfaced. Pre-Android 10 storage permission is requested only when needed. APK opening is deliberately blocked. (Android: `DetailAdapter.kt:L294-L384`, `DetailAdapter.kt:L401-L515`.)
- Downloaded images up to 5 MiB get in-feed preview and zoom viewer; other media uses MIME-specific icons. Subscription icons accept supported images up to 4 MiB and 2048×2048. (Android: `DetailAdapter.kt:L200-L213`, `DetailAdapter.kt:L386-L399`, `DetailAdapter.kt:L573-L573`; `DetailSettingsActivity.kt:L441-L481`, `DetailSettingsActivity.kt:L529-L531`.)
- The composer uploads arbitrary local files or instructs the server to fetch an attachment URL. Android Sharesheet input handles text, images, audio, video, and application files. (Android: `PublishFragment.kt:L351-L475`; `AndroidManifest.xml:L82-L91`; `ShareActivity.kt:L192-L248`.)

### Intents, deep links, and sharing

- Exported `ShareActivity` accepts one `ACTION_SEND` item, previews/edit text or file/image metadata, suggests recent and subscribed destinations, remembers the last three topic URLs, and publishes the share. There is no `ACTION_SEND_MULTIPLE` filter. (Android: `AndroidManifest.xml:L82-L91`; `ShareActivity.kt:L130-L198`, `ShareActivity.kt:L285-L342`; `Repository.kt:L515-L528`.)
- `ntfy://host[:port]/topic?secure={true|false}&display=...` opens/subscribes a topic. UnifiedPush has its own `unifiedpush://link` selector contract. (Android: `AndroidManifest.xml:L48-L63`, `AndroidManifest.xml:L101-L106`; `DetailActivity.kt:L202-L275`; `LinkActivity.kt:L9-L36`.)
- External integration also includes incoming/outgoing message broadcasts and server action broadcasts described above. These are Android IPC surfaces, not ntfy server features. (Android: `AndroidManifest.xml:L136-L169`; `BroadcastService.kt:L18-L120`.)

### Appearance, accessibility, and localization

- Material 3 UI supports system/light/dark mode and Android 12+ dynamic color. Dynamic color is hidden below API 31 and changing it restarts the app. (Android: `SettingsActivity.kt:L353-L486`; `Application.kt:L23-L28`.)
- System bars are edge-to-edge/inset-aware; the manifest declares RTL support. The app uses descriptive content strings for primary FAB/message actions and standard Material controls. There is no user-facing font-size or contrast setting; those remain system/platform concerns. (Android: `AndroidManifest.xml:L27-L35`; `activity_detail.xml:L1-L120`; `strings.xml:L280-L303`.)
- The in-app language picker offers system default plus 30 languages whose translations are stated to exceed 80%; Android per-app locale metadata lists the same locales. More resource directories exist but are not selectable in-app unless on the supported list. (Android: `SettingsActivity.kt:L377-L454`; `locales_config.xml:L1-L42`.)
- Subscription display names and icons are local presentation only; they do not rename the server topic or mutate server data. (Android: `DetailSettingsActivity.kt:L390-L425`, `DetailSettingsActivity.kt:L441-L481`.)

### Retention, storage, import/export

- Room persists subscriptions, messages, users, log entries, headers, and certificates. Normal local delete first tombstones rows; the retention worker removes visible messages after the selected policy and hard-deletes rows after four months. Deleted attachments and orphaned icons are cleaned first. (Android: `Database.kt:L303-L321`, `Database.kt:L587-L649`; `DeleteWorker.kt:L18-L142`.)
- Global auto-delete values are Never, 1 day, 3 days, 1 week, 1 month (default), and 3 months; per topic adds “Use global.” This is local retention, not a server delete operation. (Android: `values.xml:L127-L160`; `Repository.kt:L684-L695`; `DeleteWorker.kt:L111-L136`.)
- JSON backup offers Everything, Everything except users, or Settings only. Full backup includes settings, subscriptions, messages, users/passwords, trusted certificates, and client certificates/passwords; restore merges by attempting inserts and re-subscribes FCM. Downloaded binary files are represented only by local content URIs, and individual Android notification-channel customizations are explicitly not restored. (Android: `SettingsActivity.kt:L638-L723`; `Backuper.kt:L26-L56`, `Backuper.kt:L101-L141`, `Backuper.kt:L259-L345`.)
- Android application backup is also allowed by the manifest (`allowBackup=true`), separate from the user-facing JSON export. (Android: `AndroidManifest.xml:L25-L35`.)

### Diagnostics and about

- Main/detail show offline and connection-error indicators; a connection dialog distinguishes refused connection, unsupported WebSocket, and unauthorized responses and offers immediate retry/countdown. (Android: `ConnectionErrorFragment.kt:L29-L227`; `MainActivity.kt:L456-L460`.)
- Optional on-device logs retain up to 1,000 entries. When enabled, users can clear them, copy original/scrubbed logs, or upload original/scrubbed logs to the maintainer-owned `nopaste.net`; scrub mode replaces known hosts/topics/usernames and masks passwords, but the UI warns that notification contents are not censored. (Android: `Log.kt:L24-L53`, `Log.kt:L67-L99`, `Log.kt:L136-L185`; `SettingsActivity.kt:L576-L636`, `SettingsActivity.kt:L784-L889`.)
- About shows version plus flavor and copies it on tap. Main menu can open docs/report issue and, in Play flavor, rate the app; docs/report links are hidden in Play by `PAYMENT_LINKS_AVAILABLE=false`, while rate is hidden in F-Droid. (Android: `SettingsActivity.kt:L748-L758`; `MainActivity.kt:L567-L651`; `app/build.gradle:L54-L64`.)

## 2. Complete settings inventory

The hierarchy below matches `main_preferences.xml:L3-L133` and `detail_preferences.xml:L3-L74`. “Default” comes from the repository/runtime implementation when it overrides XML.

### Global Settings → Notifications

| Setting | Allowed values / default | Visibility and actual effect |
|---|---|---|
| **Mute notifications** | Show all **(default)**; 30m; 1h; 2h; 8h; until tomorrow 08:30; until resumed | Always visible. Stores an absolute global timestamp; blocks popup dispatch but messages still persist/broadcast. (`values.xml:L59-L76`; `SettingsActivity.kt:L176-L215`; `NotificationDispatcher.kt:L109-L115`.) |
| **Minimum priority** | Any **(default)**; low+; default+; high+; max only (1–5) | Always visible. Filters Android popup notifications only. (`values.xml:L77-L90`; `Repository.kt:L289-L304`; `NotificationDispatcher.kt:L85-L96`.) |
| **Download attachments** | Never; Always; below 100k/500k/1/5/10/50 MiB. **Default 1 MiB on API ≥29; Never on API ≤28** | Always visible. Pre-29 enabling requests legacy write permission. Applies globally; there is no per-topic override. XML says `defaultValue=1`, but the custom data store makes Repository the effective source. (`main_preferences.xml:L16-L21`; `Repository.kt:L306-L319`; `SettingsActivity.kt:L271-L301`.) |
| **Delete notifications** | Never; 1d; 3d; 1w; 1mo **(default)**; 3mo | Always visible. Local/tombstone retention; worker runs every 8h and hard-deletes after 4 months. (`values.xml:L127-L160`; `Repository.kt:L321-L328`, `Repository.kt:L684-L695`; `DeleteWorker.kt:L111-L142`.) |
| **Keep alerting for highest priority** | Off **(default)** / On | Always visible. Max-priority popup loops sound until dismissed; per-topic override can inherit/on/off. (`Repository.kt:L387-L395`; `NotificationService.kt:L84-L113`.) |
| **Channel settings** | Action row | Opens Android app notification settings for DND, sounds, vibration, etc. (`SettingsActivity.kt:L260-L269`.) |

### Global Settings → General

| Setting | Allowed values / default | Visibility and actual effect |
|---|---|---|
| **Default server** | Empty → build’s `app_base_url` (`https://ntfy.sh`); otherwise validated root URL | Always visible. Used by subscribe/share; does not migrate existing topics. (`SettingsActivity.kt:L507-L527`; `DefaultServerFragment.kt:L55-L136`.) |
| **Manage users** | Dynamic per-server list; add/edit/delete one Basic user per base URL | Always visible. Shows which topics use the user; changing/deleting refreshes connections. Authorization custom-header conflict is enforced. (`SettingsActivity.kt:L918-L1004`, `SettingsActivity.kt:L1080-L1122`; `Database.kt:L259-L266`.) |
| **Language** | System **(default)**; English plus 29 listed translations | Always visible. Uses AndroidX per-app locales; list is built in code, not XML. (`SettingsActivity.kt:L377-L454`; `locales_config.xml:L1-L42`.) |

### Global Settings → Appearance

| Setting | Allowed values / default | Visibility and actual effect |
|---|---|---|
| **Dark mode** | System **(default)**; Light; Dark | Always visible; applies through `AppCompatDelegate`. (`values.xml:L217-L227`; `SettingsActivity.kt:L353-L376`.) |
| **Dynamic colors** | Off **(default)** / On | Visible only on Android 12/API 31+. Applies Material dynamic colors and restarts the app when changed. (`main_preferences.xml:L57-L60`; `SettingsActivity.kt:L455-L486`; `Application.kt:L23-L28`.) |
| **Show message bar** | On **(default)** / Off | On shows quick composer + expand control; Off shows only publish FAB/full dialog. (`Repository.kt:L407-L415`; `DetailActivity.kt:L412-L464`.) |

### Global Settings → Backup & Restore

| Setting | Allowed values / default | Visibility and actual effect |
|---|---|---|
| **Back up to file** | Everything **(initial selection)**; Everything except users; Settings only | Always visible action; selection opens Android create-document. “Settings only” excludes subscriptions/messages/users but includes certificates because they are classified as settings. (`values.xml:L207-L216`; `SettingsActivity.kt:L638-L683`; `Backuper.kt:L259-L269`.) |
| **Restore from file** | Any MIME file picker | Always visible action. Validates magic, imports settings/subscriptions/messages/users/certificates, recreates UI/theme, and tolerates individual duplicate/invalid records. (`SettingsActivity.kt:L685-L723`; `Backuper.kt:L34-L56`.) |

### Global Settings → Advanced

| Setting | Allowed values / default | Visibility and actual effect |
|---|---|---|
| **Alert when disconnected** | Never **(default)**; 5m; 15m; 1h; 3h; 12h | Always visible. Applies to unreachable live-connection servers, not device-offline periods; alert has snooze/never actions. (`values.xml:L171-L186`; `Repository.kt:L447-L455`; `SubscriberService.kt:L336-L419`.) |
| **Connection protocol** | JSON stream over HTTP **(default)**; WebSockets | Always visible. Global for foreground instant connections; changing refreshes them. (`values.xml:L187-L194`; `Repository.kt:L357-L365`; `SettingsActivity.kt:L724-L744`.) |
| **Exact alarms** | Action/status row, no stored app value | Visible only API 33+ **and** while not battery-optimization exempt. Opens Android alarm permission UI; WebSocket reconnect uses exact alarms and otherwise cannot schedule background reconnect. (`SettingsActivity.kt:L891-L919`; `WsConnection.kt:L108-L139`.) |
| **Custom headers** | Dynamic per-server name/value list; add/edit/delete | Always visible. Headers go on all app HTTP/WebSocket requests for that server; editing refreshes live connections. Reserved/duplicate/auth conflicts rejected. (`SettingsActivity.kt:L1012-L1071`, `SettingsActivity.kt:L1125-L1154`; `CustomHeaderFragment.kt:L171-L248`.) |
| **Manage certificates** | Dynamic trusted PEM and client PKCS#12 lists; add/view/delete | Always visible. One trust cert and one client cert per base URL in schema; used by all OkHttp client builders. (`CertificateSettingsFragment.kt:L43-L180`; `Database.kt:L268-L279`; `HttpUtil.kt:L91-L100`.) |
| **Broadcast messages** | On **(default)** / Off | Always visible. Controls outgoing `io.heckel.ntfy.MESSAGE_RECEIVED` broadcasts for ordinary subscriptions; not UnifiedPush. (`Repository.kt:L367-L375`; `NotificationDispatcher.kt:L98-L103`.) |
| **Enable UnifiedPush** | On **(default)** / Off | Always visible. Enables/disables distributor receiver/link activity components; controls whether other apps may register through ntfy. Existing UP subscriptions remain special rows. (`Repository.kt:L377-L385`; `SettingsActivity.kt:L549-L575`; `Distributor.kt:L47-L71`.) |
| **Record logs** | Off **(default)** / On | Always visible. Stores up to 1,000 app log entries; toggles the next two rows. (`Repository.kt:L397-L405`; `SettingsActivity.kt:L601-L636`; `Log.kt:L136-L175`.) |
| **Copy/upload logs** | Copy; copy censored; upload+copy link; upload censored+copy link | Visible only while Record logs is on. Action does not persist the selected option. Upload target is `https://nopaste.net/?f=json`. (`values.xml:L195-L206`; `SettingsActivity.kt:L576-L590`, `SettingsActivity.kt:L784-L858`.) |
| **Clear logs** | Action row | Visible only while Record logs is on. Deletes recorded entries. (`SettingsActivity.kt:L591-L600`, `SettingsActivity.kt:L877-L889`.) |

### Global Settings → About

| Setting | Allowed values / default | Visibility and actual effect |
|---|---|---|
| **Version** | `ntfy <version> (<flavor>)` | Always visible; tap copies it. (`SettingsActivity.kt:L748-L758`.) |

### Subscription settings → Notifications

These rows are hidden as a category for UnifiedPush-managed subscriptions (`DetailSettingsActivity.kt:L136-L151`).

| Setting | Allowed values / default | Conditional visibility and effect |
|---|---|---|
| **Instant delivery** | Per-subscription On/Off | Visible only in Play builds for the built-in ntfy.sh base URL. New self-hosted and all F-Droid subscriptions are always instant; ntfy.sh Play subscriptions take the add-dialog checkbox. Toggle refreshes foreground service. (`DetailSettingsActivity.kt:L156-L177`; `AddFragment.kt:L364-L438`; `MainActivity.kt:L701-L729`.) |
| **Mute notifications** | Same seven choices as global; Show all **(default)** | Visible for ordinary subscriptions. Independent of global mute; either mute suppresses popup. (`DetailSettingsActivity.kt:L221-L261`; `NotificationDispatcher.kt:L109-L115`.) |
| **Minimum priority** | Use global **(default)**; priorities 1–5 | Visible for ordinary subscriptions. Overrides popup threshold. (`values.xml:L91-L106`; `DetailSettingsActivity.kt:L263-L293`.) |
| **Delete notifications** | Use global **(default)**; Never/1d/3d/1w/1mo/3mo | Visible for ordinary subscriptions. Local per-topic retention override. (`values.xml:L137-L160`; `DetailSettingsActivity.kt:L295-L326`.) |
| **Keep alerting for highest priority** | Use global **(default)**; Keep alerting; Alert once | Visible for ordinary subscriptions. (`values.xml:L161-L170`; `DetailSettingsActivity.kt:L328-L353`.) |
| **Custom notification settings** | Off **(default)** / On | Visible for ordinary subscriptions. Creates/deletes five dedicated Android priority channels. (`DetailSettingsActivity.kt:L179-L205`; `NotificationService.kt:L64-L73`.) |
| **Configure notification settings** | Action row | Visible only when dedicated channels are enabled. Opens Android app notification settings (not a single-channel picker). (`DetailSettingsActivity.kt:L207-L219`.) |

### Subscription settings → Appearance / About

| Setting | Default | Conditional visibility and effect |
|---|---|---|
| **Subscription icon** / **tap to remove** | None | For ordinary subscriptions, exactly one of Set/Remove is shown. Accepts supported image ≤4 MiB and ≤2048×2048; appears in list and notifications. Hidden for UnifiedPush subscriptions by the load path. (`DetailSettingsActivity.kt:L136-L151`, `DetailSettingsActivity.kt:L355-L388`, `DetailSettingsActivity.kt:L441-L481`.) |
| **Display name** | Blank → derived topic short URL | Always visible, including UnifiedPush. Local-only; updates dedicated channel names. (`DetailSettingsActivity.kt:L390-L425`.) |
| **Topic URL** | Current base/topic | Always visible. Tap copies the short topic URL. (`DetailSettingsActivity.kt:L427-L439`.) |

## 3. Important Android/platform behavior and permissions

| Platform concern | Audited behavior |
|---|---|
| **Internet/network** | `INTERNET` and `ACCESS_NETWORK_STATE`; cleartext allowed. Connectivity callbacks close/wait offline and force reconnect on Wi-Fi/cellular/VPN changes. (Android: `AndroidManifest.xml:L5-L6`, `AndroidManifest.xml:L35-L35`; `Application.kt:L30-L69`.) |
| **Foreground service** | `FOREGROUND_SERVICE` + API 34 `FOREGROUND_SERVICE_SPECIAL_USE`; service declares `specialUse`, immediately calls `startForeground`, returns `START_STICKY`, and runs only when at least one instant subscription exists. Ongoing low-importance “Background service” notification is mandatory. (Android: `AndroidManifest.xml:L7-L8`, `AndroidManifest.xml:L110-L116`; `SubscriberService.kt:L79-L145`; `SubscriberServiceManager.kt:L33-L73`.) |
| **Wake lock** | `WAKE_LOCK` is declared. The service creates a partial wake-lock object but this commit does **not** call `acquire()`; cleanup only releases it if held. Do not infer continuous CPU lock from the permission/field alone. (Android: `AndroidManifest.xml:L9-L9`; `SubscriberService.kt:L156-L190`.) |
| **Notifications** | `POST_NOTIFICATIONS` requested at runtime on API 33+ during main activity creation. Channels: five priority channels, optional five-per-topic groups, low-importance foreground-service channel, and default-importance connection-alert channel. `VIBRATE` declared. (Android: `AndroidManifest.xml:L11-L14`; `MainActivity.kt:L391-L399`; `NotificationService.kt:L373-L408`; `SubscriberService.kt:L462-L473`.) |
| **Exact alarms** | `SCHEDULE_EXACT_ALARM` declared. On API 33+, WebSocket reconnect schedules `RTC_WAKEUP` only when `canScheduleExactAlarms()`; UI/banner can open the grant panel. JSON-stream retry does not need exact alarms. Boot receiver also listens for permission-state changes. (Android: `AndroidManifest.xml:L13-L13`, `AndroidManifest.xml:L119-L128`; `WsConnection.kt:L108-L139`; `SettingsActivity.kt:L891-L919`.) |
| **Battery optimization / doze** | `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` declared. A banner offers Fix now, Ask later (1 day), or Dismiss forever. Exact-alarm UI is hidden when exempt. Instant foreground delivery is the doze-oriented path; FCM is lower-battery but may delay. Note: `showHideBatteryBanner` calculates whether instant subscriptions exist but does not use it in `showBanner`, so current source may show the banner even without one. (Android: `AndroidManifest.xml:L15-L15`; `MainActivity.kt:L273-L302`, `MainActivity.kt:L408-L416`; `SettingsActivity.kt:L906-L919`.) |
| **Boot/restart** | `RECEIVE_BOOT_COMPLETED`; exported receiver handles boot and exact-alarm permission changes. Service is sticky, broadcasts restart on destroy, is checked by a 3-hour periodic worker, and Play FCM keepalive can trigger restart. (Android: `AndroidManifest.xml:L10-L10`, `AndroidManifest.xml:L119-L134`; `SubscriberService.kt:L149-L153`, `SubscriberService.kt:L509-L525`; `MainActivity.kt:L509-L529`.) |
| **Periodic recovery** | Network-constrained WorkManager poll every 60m, service restart every 180m, retention every 480m. WorkManager timing is inexact; these are catch-up/recovery, not proof of instant delivery. (Android: `MainActivity.kt:L469-L529`, `MainActivity.kt:L881-L895`.) |
| **Storage/files** | Legacy `WRITE_EXTERNAL_STORAGE` only through API 28; modern save uses MediaStore. FileProvider exposes downloaded/cache/internal files with URI grants. (Android: `AndroidManifest.xml:L12-L12`, `AndroidManifest.xml:L198-L208`; `DetailAdapter.kt:L401-L515`.) |
| **App backup/security** | Manifest allows Android backup and permits user/system CAs plus HTTP. User-facing JSON backup may contain passwords and private keys. This differs from Flutter’s `allowBackup=false` and secure credential store. (Android: `AndroidManifest.xml:L25-L35`; `network_security_config.xml:L1-L9`; `Backuper.kt:L215-L269`; Flutter: `android/app/src/main/AndroidManifest.xml:L10-L15`, `lib/app_database.dart:L399-L432`.) |
| **Exported entry points** | Launcher and `ntfy://` detail activity; ACTION_SEND share activity; UnifiedPush link/receiver; send-message broadcast receiver. Other notification/service receivers are not exported. (Android: `AndroidManifest.xml:L38-L106`, `AndroidManifest.xml:L136-L183`.) |

## 4. Gap matrix against current `ntfy_flutter`

Status meanings: **Present** = useful behavior exists now; **Partial** = core exists but important official behavior/metadata/platform handling is absent; **Missing** = no current implementation found; **Intentionally out of scope** = explicitly excluded by Flutter’s minimal-client statement or platform direction. “Out of scope” is a planning judgment, not a claim that the official feature is unimportant.

| Capability | Status | Evidence and planning note |
|---|---|---|
| Add/validate topic; alternate server | **Present** | Official probes/validates (`AddFragment.kt:L210-L438`). Flutter takes one complete topic URL and validates origin/topic (`lib/main.dart:L1043-L1272`; `lib/ntfy_client.dart:L37-L90`). |
| Local display name | **Present** | Official per-topic display name (`DetailSettingsActivity.kt:L390-L425`). Flutter add/rename and DB field (`lib/main.dart:L656-L675`, `lib/main.dart:L826-L883`; `lib/app_database.dart:L168-L174`). |
| Basic authentication | **Present** | Official per-base user (`HttpUtil.kt:L75-L89`). Flutter Basic stored in secure storage and HTTPS-only (`lib/models.dart:L3-L51`; `lib/ntfy_client.dart:L93-L127`; `lib/app_database.dart:L399-L432`). |
| Bearer authentication | **Present** | Official has arbitrary Authorization header but managed UI is Basic (`UserFragment.kt:L18-L223`; `CustomHeaderFragment.kt:L171-L248`). Flutter exposes first-class Bearer (`lib/main.dart:L1140-L1233`; `lib/ntfy_client.dart:L111-L122`). |
| Auth probe/login-on-demand | **Partial** | Official checks read access before saving (`AddFragment.kt:L222-L342`). Flutter discovers bad credentials through initial poll and requires auth choice up front (`lib/app_controller.dart:L49-L78`). |
| Subscription list/unread/latest | **Present** | Official list metadata (`MainAdapter.kt:L79-L159`). Flutter summaries/unread/latest (`lib/app_database.dart:L89-L117`; `lib/main.dart:L212-L528`). |
| Refresh/history/cursor/dedup | **Present** | Official poll/cursor (`ApiService.kt:L117-L140`; `Repository.kt:L119-L138`). Flutter imports `since=all`, advances cursor, unique-dedups event IDs (`lib/app_controller.dart:L49-L90`; `lib/app_database.dart:L258-L291`, `lib/app_database.dart:L317-L371`). |
| Feed ordering | **Present** | Official newest-first (`Database.kt:L590-L604`). Flutter DB reads newest-first then renders reversed, latest at bottom (`lib/app_database.dart:L120-L128`; `lib/main.dart:L1538-L1564`). |
| Search title/message/tags | **Missing** | Official query/UI (`Database.kt:L593-L604`; `DetailActivity.kt:L574-L629`). No search path in Flutter feed (`lib/main.dart:L1327-L1590`). Useful next. |
| Read state/unread suppression | **Present** | Official marks topic read on leave/open (`DetailActivity.kt:L546-L566`). Flutter marks imported history/read on opening and tracks unread (`lib/app_controller.dart:L107-L110`; `lib/app_database.dart:L130-L135`). |
| Local swipe delete, clear, unsubscribe | **Present** | Official local delete/clear/unsubscribe (`DetailActivity.kt:L360-L378`, `DetailActivity.kt:L878-L933`). Flutter swipe/delete/clear/unsubscribe (`lib/main.dart:L675-L707`, `lib/main.dart:L997-L1036`, `lib/main.dart:L1546-L1563`; `lib/app_controller.dart:L112-L151`). |
| Server message update/delete/clear semantics | **Missing** | Official parses events and applies by sequence ID (`NotificationParser.kt:L16-L70`; `Repository.kt:L119-L138`). Flutter parser recognizes envelope but DB ignores all non-`message` events and dedups only event ID (`lib/models.dart:L61-L126`; `lib/app_database.dart:L327-L340`). Must-have reliability/data-correctness gap. |
| Quick plain-text publish | **Present** | Official message bar (`DetailActivity.kt:L412-L497`). Flutter composer and HTTP PUT (`lib/main.dart:L1434-L1442`, `lib/ntfy_client.dart:L176-L199`). Flutter rejects empty messages, unlike official quick bar. |
| Title/priority/tags publish | **Missing** | Official composer/API (`PublishFragment.kt:L498-L568`; `ApiService.kt:L30-L58`). Flutter publishes only body (`lib/ntfy_client.dart:L176-L199`). Must/useful next. |
| Advanced publish: Markdown/click/delay/e-mail/call | **Intentionally out of scope** | Official controls (`PublishFragment.kt:L286-L389`, `PublishFragment.kt:L498-L568`). Flutter README explicitly frames minimal publish and code exposes body only (`README.md:L1-L4`; `lib/ntfy_client.dart:L176-L199`). Add only from concrete need. |
| Incoming rich title/tags/priority display | **Partial** | Official renders priority/tags/Markdown (`DetailAdapter.kt:L104-L199`). Flutter stores title/priority/tags and shows title/tags, but priority has no feed treatment; message body is plain text and notification channel/priority are fixed (`lib/models.dart:L129-L155`; `lib/main.dart:L1591-L1718`; `lib/notification_service.dart:L66-L83`). |
| Markdown and link/click behavior | **Missing** | Official Markwon, URL auto-link, click URL (`DetailAdapter.kt:L112-L139`; `DetailActivity.kt:L935-L957`). Flutter model does not parse `content_type`/`click` (`lib/models.dart:L61-L126`). |
| Notification tap opens topic | **Present** | Official content intent (`NotificationService.kt:L186-L197`). Flutter payload routing covers running/terminated app (`lib/notification_service.dart:L34-L55`, `lib/main.dart:L87-L122`). |
| Notification priority channels and per-topic channels | **Missing** | Official five global + optional dedicated groups (`NotificationService.kt:L59-L73`, `NotificationService.kt:L373-L408`). Flutter has one default-importance message channel (`lib/notification_service.dart:L14-L19`, `lib/notification_service.dart:L66-L83`). Add global priority mapping before per-topic channels. |
| Global/per-topic mute and min-priority filter | **Missing** | Official dispatcher honors both (`NotificationDispatcher.kt:L85-L115`). Flutter always notifies inserted live messages (`lib/delivery_service.dart:L181-L191`). Must-have if notification volume matters. |
| Insistent max-priority alert | **Missing** | Official opt-in (`NotificationService.kt:L84-L113`). Flutter fixed normal notification (`lib/notification_service.dart:L66-L83`). YAGNI unless alerting use cases require it. |
| Server action buttons (view/copy/http/broadcast) | **Missing** | Official actions (`UserActionWorker.kt:L34-L127`). Flutter event model omits actions (`lib/models.dart:L61-L126`). Useful only after rich-message model; HTTP/broadcast are security-sensitive. |
| Foreground WebSocket delivery | **Present** | Official one connection per base URL (`SubscriberService.kt:L209-L307`). Flutter foreground special-use service reconnects one WebSocket per subscription (`lib/delivery_service.dart:L24-L91`, `lib/delivery_service.dart:L103-L221`; `android/app/src/main/AndroidManifest.xml:L35-L43`). |
| Connection aggregation | **Partial** | Official multiplexes topics by base URL (`SubscriberService.kt:L229-L307`). Flutter deliberately owns one stream per subscription (`lib/delivery_service.dart:L107-L166`; `README.md:L27-L31`). Optimize only if measured battery/socket cost warrants it. |
| Offline/network-transition handling | **Partial** | Official stops retrying offline and immediately reconnects on network handoff (`Application.kt:L30-L69`; `SubscriberService.kt:L213-L227`). Flutter only retries timers and has no connectivity callback/banner (`lib/delivery_service.dart:L146-L221`). Must-have reliability gap. |
| Recovery poll / service health worker | **Missing** | Official hourly poll + three-hour service check (`MainActivity.kt:L469-L529`). Flutter explicitly has no WorkManager and only service auto-restart/visible-app restart (`README.md:L1-L4`, `README.md:L29-L31`; `lib/main.dart:L98-L108`). Add a minimal catch-up strategy before assuming always-live delivery. |
| Boot delivery | **Intentionally out of scope** | Official boot receiver (`AndroidManifest.xml:L119-L128`). Flutter declares boot permission through plugin needs but intentionally disables automatic boot delivery (`README.md:L31-L31`; `android/app/src/main/AndroidManifest.xml:L2-L8`); no app receiver is declared. |
| FCM low-power ntfy.sh mode | **Intentionally out of scope** | Official Play flavor only (`app/build.gradle:L54-L64`; `app/src/play/java/io/heckel/ntfy/firebase/FirebaseService.kt:L32-L212`). Flutter explicitly has no FCM (`README.md:L1-L4`). Requires separate Firebase/server infrastructure. |
| Exact-alarm WebSocket reconnect UI | **Missing** | Official AlarmManager path (`WsConnection.kt:L108-L139`). Flutter service isolate uses Dart timers and does not request exact alarms (`lib/delivery_service.dart:L204-L221`; `android/app/src/main/AndroidManifest.xml:L2-L8`). Reassess only after doze testing proves a gap. |
| Battery/offline/connection diagnostics | **Missing** | Official banners/dialog/status (`MainActivity.kt:L273-L369`, `ConnectionErrorFragment.kt:L29-L227`). Flutter errors are general inline/snackbar text (`lib/main.dart:L233-L252`, `lib/main.dart:L1459-L1490`). A compact service/offline status is useful next. |
| Local retention global/per-topic | **Present** | Official day-to-month values, default 30d (`values.xml:L127-L160`). Flutter default Never and 1h–30d options, inherit/override, 15m active cleanup (`lib/main.dart:L17-L27`, `lib/main.dart:L884-L986`; `lib/app_database.dart:L149-L232`; `lib/delivery_service.dart:L125-L129`). |
| Attachments receive/download/view | **Missing** | Official parser/download/feed UI (`NotificationParser.kt:L25-L34`; `DetailAdapter.kt:L200-L213`, `DetailAdapter.kt:L294-L399`). Flutter model omits attachment (`lib/models.dart:L61-L126`). Useful next only for target use cases. |
| Attachment publish/upload | **Missing** | Official full upload/URL flow (`PublishFragment.kt:L351-L475`, `PublishFragment.kt:L520-L568`). Flutter body-only (`lib/ntfy_client.dart:L176-L199`). Larger UI/storage/security surface. |
| ACTION_SEND share target | **Missing** | Official exported share activity (`AndroidManifest.xml:L82-L91`; `ShareActivity.kt:L192-L342`). Flutter manifest launcher only (`android/app/src/main/AndroidManifest.xml:L16-L32`). Useful next for Android-first convenience. |
| `ntfy://` deep links | **Missing** | Official intent filter and subscribe path (`AndroidManifest.xml:L48-L63`; `DetailActivity.kt:L202-L275`). Flutter manifest has no VIEW/BROWSABLE filter (`android/app/src/main/AndroidManifest.xml:L16-L32`). Add only if links are part of intended onboarding. |
| Outgoing/incoming Android broadcasts | **Intentionally out of scope** | Official integration contract (`BroadcastService.kt:L18-L120`). Flutter has no receivers and is intentionally minimal (`README.md:L1-L4`; `android/app/src/main/AndroidManifest.xml:L16-L43`). |
| UnifiedPush distributor | **Intentionally out of scope** | Official acts as distributor (`Distributor.kt:L9-L71`). Flutter is a client only and has no UP components (`android/app/src/main/AndroidManifest.xml:L16-L43`). Avoid. |
| Theme/dynamic color/language | **Partial** | Official light/dark/system, dynamic color, 30-language picker (`SettingsActivity.kt:L353-L486`). Flutter follows system light/dark with seeded Material 3, hard-coded English, no dynamic color (`lib/main.dart:L125-L208`). System theme is enough now; localization only when audience requires it. |
| Subscription icon | **Missing** | Official local image with limits (`DetailSettingsActivity.kt:L355-L388`, `DetailSettingsActivity.kt:L441-L481`). Flutter uses a generic icon (`lib/main.dart:L430-L446`). Cosmetic/YAGNI. |
| Backup/restore | **Missing** | Official JSON export/import (`Backuper.kt:L26-L56`). Flutter disables Android backup and has no export UI (`android/app/src/main/AndroidManifest.xml:L10-L15`; `lib/main.dart:L750-L820`). Consider a safe config export only after schema stabilizes. |
| Custom headers | **Missing** | Official per-server headers (`CustomHeaderFragment.kt:L171-L248`). Flutter sends only Authorization/content type (`lib/ntfy_client.dart:L93-L127`, `lib/ntfy_client.dart:L176-L190`). Add for authenticated proxy users, not general parity. |
| Trusted/self-signed cert and mTLS | **Missing** | Official TLS manager (`CertificateSettingsFragment.kt:L43-L180`). Flutter uses platform defaults and no cert UI (`lib/ntfy_client.dart:L21-L35`; `pubspec.yaml:L32-L37`). Security-sensitive; avoid until required. |
| Secure credential storage | **Present** | Official user secrets are Room fields (`Database.kt:L259-L266`). Flutter uses `flutter_secure_storage`, HTTPS-only Basic/Bearer (`lib/app_database.dart:L399-L432`; `lib/ntfy_client.dart:L93-L127`). Keep. |
| Diagnostics/log export/version/about | **Missing** | Official logs/version (`SettingsActivity.kt:L576-L636`, `SettingsActivity.kt:L748-L758`). Flutter has no log/about UI (`lib/main.dart:L750-L820`). Add local version/copy diagnostics before any third-party upload. |

## 5. Prioritized shortlist for a minimal Android-first Flutter client

### Must-have parity: reliability and protocol correctness

1. **Implement `sequence_id`, `message_delete`, and `message_clear` transactionally.** Current Flutter advances cursors past control events but ignores their state effect; this can leave stale content and wrong popup state. Mirror behavior, not code. (Android: `NotificationParser.kt:L16-L70`, `Repository.kt:L119-L138`; Flutter: `lib/app_database.dart:L327-L371`.)
2. **Add reconnect catch-up and network-transition awareness.** At minimum, force/recreate streams after default-network changes and perform a cursor poll after reconnect/service bootstrap. A full official-style WorkManager stack is not initially required. (Android: `Application.kt:L30-L69`, `PollWorker.kt:L25-L64`; Flutter: `lib/delivery_service.dart:L117-L221`.)
3. **Map event priority to Android notification behavior and add global/per-topic mute plus minimum-priority filtering.** Start with a small fixed channel set and native channel settings; per-topic channel groups can wait. (Android: `NotificationDispatcher.kt:L85-L115`, `NotificationService.kt:L373-L408`; Flutter: `lib/notification_service.dart:L14-L83`.)
4. **Prove foreground-service lifecycle on physical Android under screen-off, process removal, network handoff, doze, notification denial, and service recreation.** The README checklist is good but not evidence of completed acceptance (`README.md:L41-L54`). Add observable service/offline state if failures are otherwise invisible.
5. **Preserve secure credential handling.** Do not regress to official-style plaintext Room storage or secret-bearing backups. (Flutter: `lib/app_database.dart:L399-L432`, `lib/ntfy_client.dart:L93-L127`.)

### Useful next

1. **Title, priority, tags** in model, message card, notification, and composer; these provide most ntfy expressiveness with limited surface. (Android: `ApiService.kt:L30-L58`; Flutter gap: `lib/ntfy_client.dart:L176-L199`.)
2. **Feed search** over title/message/tags using SQLite, without a search framework. (Android: `Database.kt:L593-L604`.)
3. **Compact connection/offline diagnostics** and a route to both message and foreground-channel Android settings. Avoid an elaborate diagnostics subsystem.
4. **Receive/display click URL and plain Markdown/link behavior** if actual publishers use them. Sanitize URL launching and do not automatically execute remote content.
5. **ACTION_SEND share target** for text first; file sharing only after incoming attachment support exists.
6. **Attachments** only if needed: start with metadata + tap-to-download/open, then image preview; add upload last.
7. **Optional default server convenience** only if full topic URLs become repetitive. Current one-field URL onboarding is simpler and less ambiguous.

### Avoid / YAGNI unless a concrete requirement appears

- FCM infrastructure and dual delivery modes.
- Acting as a UnifiedPush distributor.
- Per-topic five-channel groups, insistent looping alerts, exact-alarm UI, and aggressive battery-exemption prompting before device tests show a need.
- mTLS, custom trust/pinning, and arbitrary custom headers except for identified self-hosted users.
- Full official backup compatibility, especially exporting secrets/private keys or stale content URIs.
- Public Android broadcast APIs and remote HTTP/broadcast action execution.
- Remote diagnostic-log upload; if diagnostics are needed, provide local copy/export with explicit redaction first.
- Subscription icons, rate/docs menus, randomized test notifications, app-specific language picker, or broad appearance settings until the core is stable.

## 6. Current source vs history vs server capability

- Changelog version 63 says connection-loss alert, no-network handling, longer WebSocket ping, network-transition reconnect, and UnifiedPush disable behavior were added/fixed; all are verified in current Kotlin (`fastlane/metadata/android/en-US/changelog/63.txt:L1-L13`; current `Application.kt:L30-L69`, `SubscriberService.kt:L213-L227`, `SettingsActivity.kt:L549-L575`).
- Changelog 59 records search/copy action/timestamp changes; current source contains the search SQL/UI, copy action worker, and server timestamp assignment (`fastlane/metadata/android/en-US/changelog/59.txt:L1-L12`; current `Database.kt:L593-L604`, `UserActionWorker.kt:L72-L79`, `NotificationService.kt:L90-L97`).
- Changelog 58 records update/delete and certificate support; current parser/repository and certificate screens verify these are not merely historical labels (`fastlane/metadata/android/en-US/changelog/58.txt:L1-L10`; current `NotificationParser.kt:L16-L70`, `CertificateSettingsFragment.kt:L43-L180`).
- Publish chips for e-mail, call, delay, remote attachment and Markdown expose **server requests**, not on-device delivery engines. Likewise FCM behavior requires the official server/Firebase configuration; the labels do not make these client-local capabilities. (Current `ApiService.kt:L30-L112`; `app/src/play/java/io/heckel/ntfy/firebase/FirebaseService.kt:L32-L212`.)
- The current source has build-flavor policy gates that can hide docs/report/copy-topic links in Play despite code/resources being present. Inventory entries therefore state conditional visibility rather than treating every resource string as reachable. (`app/build.gradle:L54-L64`; `MainActivity.kt:L567-L651`; `DetailActivity.kt:L865-L876`.)

## 7. Open questions and source ambiguities

1. **Battery banner condition likely disagrees with its own log/comment.** `hasInstantSubscriptions` is computed but omitted from `showBanner`; determine whether this is intentional after recent service changes before copying the UX. (Android: `MainActivity.kt:L408-L416`.)
2. **Wake-lock intent vs implementation.** The manifest/comment says the foreground service uses `WAKE_LOCK`, but current code creates and never acquires it. Device testing is needed before deciding whether Flutter’s plugin `allowWakeLock=true` is necessary or harmful. (Android: `AndroidManifest.xml:L9-L9`; `SubscriberService.kt:L156-L190`; Flutter: `lib/delivery_service.dart:L39-L49`.)
3. **Exact-alarm “revoke” wording.** The row always launches `ACTION_REQUEST_SCHEDULE_EXACT_ALARM`; behavior of tapping while already granted is platform/OEM-dependent. Do not promise in-app revoke without device verification. (Android: `strings.xml:L472-L474`; `SettingsActivity.kt:L891-L919`.)
4. **Backup completeness.** Several current preferences are not represented in `Backuper.Settings` (notably UnifiedPush enabled, insistent max, message bar), and Android channel customization has an explicit TODO. “Everything” is therefore not literally every current preference/platform setting. (Android: `Backuper.kt:L272-L290`, `Backuper.kt:L135-L136`; `Repository.kt:L377-L415`.)
5. **Flutter service boot semantics.** Flutter declares `RECEIVE_BOOT_COMPLETED` and configures plugin auto-restart, while its README says automatic boot delivery is intentionally disabled and no app receiver appears in the manifest. Confirm the plugin’s merged manifest/runtime behavior on a release APK before relying on either claim. (Flutter: `android/app/src/main/AndroidManifest.xml:L2-L8`, `lib/delivery_service.dart:L39-L49`, `README.md:L31-L31`.)
6. **Flutter notification behavior while a feed is open.** Official suppresses popups for the visible topic; Flutter’s service always calls `showMessage` for inserted live events and has no visible-topic signal. Decide whether this is desired before calling notification parity complete. (Android: `NotificationDispatcher.kt:L85-L96`; Flutter: `lib/delivery_service.dart:L181-L191`.)
7. **Official automated verification is absent in this clone.** The manual checklist does not cover newer search, certificates, composer attachments, connection alerts, or backup edge cases. Current implementation tracing is strong evidence, but runtime/OEM behavior still needs device acceptance. (Android: `TESTING.md:L1-L22`.)
8. **Flutter has no immutable audited revision.** Before implementing from this matrix, create an initial commit/tag so future parity decisions can be tied to a stable baseline.

## License note

`ntfy-android` is distributed under the **Apache License 2.0** (`README.md:L17-L18`; `LICENSE:L1-L2`). This permits use under its terms but does not require or justify copying its architecture. For this independent Flutter client, use the official source as a behavioral primary source, design independently, and do not copy code. If code is ever copied, perform a separate license/notice review and retain required attribution and change notices.
