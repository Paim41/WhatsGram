# Architecture

One Flutter project contains Android and Windows native runners. Riverpod exposes `AppController`; the shell chooses split-pane or narrow navigation at 900 logical pixels. Feature widgets do not own the native transport. Flutter's navigator and overlays remain the app-shell boundary.

`telegram/native/td_native.dart` owns a dedicated isolate and one TDLib client. It copies every returned UTF-8 string before the next receive, frees all Dart-allocated request strings, and runs a single receive loop. `RequestBroker` correlates string `@extra` IDs, preserves unsolicited update order, times out requests, rejects late responses and cancels outstanding requests on shutdown. Closing waits for the closed authorization state before terminating the worker; a bounded timeout handles an unresponsive worker. New sessions get a new client lifecycle.

The adapter is pinned to TDLib 1.8.67. The complete matching `td_api.tl` is included under `native/schema`; runtime version mismatch blocks startup. In this schema forum routing uses `messageTopicForum.forum_topic_id`, not older `message_thread_id` examples. DTO fields and requests are concentrated in the Telegram repository and workspace transport.

Telegram user IDs, supergroup IDs, local chat IDs and message IDs are different identifiers. Settings store stable IDs as decimal strings. Participant pairs resolve to the other user's local private chat independently for each account. No cross-account session copying occurs.

## Workspace convergence

The verified genesis binds a UUID workspace to exactly two user IDs and an owner sender. Event records are accepted only from non-forwarded, non-imported `messageSenderUser` Telegram messages whose sender equals the declared actor and is a genesis participant. Records are limited to 8192 UTF-8 bytes and strict supported JSON shapes. Unknown schema versions stop synchronization.

Each selection is a last-writer-wins register ordered numerically by Lamport, numerically by actor ID, then lexically by canonical UUID device/event IDs. Lamport never uses wall-clock time. Deselection tombstones remain records. Duplicate event UUIDs do not apply twice; retries keep their UUID. Local pending events, registers, clock and device ID are protected by platform storage. History is paged and replayed while live updates are buffered. Reconciliation occurs on reconnect, resume and periodically; edited/deleted control records trigger a rebuild. Missing or changed genesis prevents further synchronization and retains the last known selection for recovery.

The log is append-only by convention, not immutable. Telegram members/admins may edit or delete messages. There is no history compaction in this version. Selecting a whole supergroup includes all its topics; individual topic selections matter when the whole group is not selected.

## Media and notifications

TDLib owns message/media transfer and cache. Windows recording uses AAC in an actual M4A container, explicitly supported by the pinned inputVoiceNote schema; it is not renamed to OGG. media_kit provides native audio/video playback. Photo versus original-document mode is explicit.

Manual exports use native save UI. Auto-export is off by default, scoped to selected accessible conversations, rechecks permission/selection before export, uses category/size/network filters, durable completion records and deterministic filenames. Android uses persistent SAF folder access; Windows uses a native folder selector and partial-file renames. Device paths never enter the shared protocol. Metered-network cost is available on Android; Windows cost is treated as unknown.

Local notifications use actual incoming TDLib messages, suppress the settings group/unselected topics, recheck access and selection, and deduplicate per account. History replay and messages older than two minutes do not create notification bursts. This deliberately favors no duplicate historical notifications over guaranteed catch-up alerts. Native click payloads contain account and logical target identities, and are revalidated before navigation. Message read calls include only on-screen messages in the active route, while the app is resumed.

## Future Interactive Pet integration

A future optional pet can attach through the existing Flutter navigator Overlay above `WhatsGramShell`, on both narrow and desktop layouts. A later adapter may observe sanitized connection, notification and send-completion state at `AppController` and repository boundaries; it must not receive message text, media or credentials by default. Use Settings → Appearance/Companion for future device-only controls, default off. Placement must respect safe areas, keyboard, resizing, text scaling and all messaging controls, and must not steal input/accessibility focus. Any desktop-wide window mode is separate future native work. No pet assets, dependencies, controls, timers, hooks or placeholders are present now.
