# Testing

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

The tests use an injected TDLib interface only in tests; production always uses native TDLib. They exercise request correlation, ordering, timeouts, shutdown, error presentation; strict genesis/event validation; numeric Lamport order, concurrent selection/tombstones, retry UUID reuse, bootstrap/live overlap and missing-genesis recovery; account-specific pair resolution; forum send/read boundaries; hidden-topic notification suppression; safe filenames; and mobile/desktop large-text authentication layouts. Test doubles do not assert that a real Telegram account was tested.

## Manual two-account acceptance checklist

Use explicitly authorized test accounts and conversations. Do not run this checklist against real people or upload files without deliberate authorization.

1. A signs into Android; B signs into Windows. Verify code, password, email and QR states when Telegram requests them.
2. Pair both accounts to one verified settings group, checking actual owner ID and genesis sender.
3. Select their direct conversation and a shared forum group/topic.
4. Confirm both show the same selection and hide unrelated chats/control group.
5. Send text both ways; verify the correct sender in official Telegram.
6. Exchange a photo, an original document, video and recorded M4A voice message. Verify captions, transfer progress, download cancellation, playback and saves.
7. Reply, edit, react, forward and delete where permitted; check results in official Telegram.
8. Change topic selection on each device. Verify convergence and group-wide precedence.
9. Make different selections while offline. Reconnect and verify convergence without duplicate logical operations.
10. Check an inaccessible selected group: Access required, no preview/notification, no permission bypass.
11. Enable local notifications and test selected/unselected topics, preview privacy and deep links. Check Android process/Doze limitations and Windows quit behavior.
12. Restart both apps and verify independent restored sessions, settings and encrypted database keys.
13. Test auto-save off/on, category/size/metering filters, per-device destinations, deduplication, denied folder permission and failed partial cleanup.
14. Log out of one app without damaging the other account/session.
15. Delete/edit a settings event and verify replay; remove trusted genesis and verify recovery error. Test future schema rejection.
16. Test keyboard Enter/Shift+Enter, right-click actions, file drops, Android rotation/back navigation, large text and screen reader labels.

Record device/OS versions, account permission conditions and actual results. SDK installation, native compilation or passing unit tests alone do not establish live Telegram compatibility. See `VERIFICATION.md` for the recorded build result.
