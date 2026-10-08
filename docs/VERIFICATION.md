# Verification record

This is an implemented native Flutter client for Android and Windows. It is not a web application, and live Telegram acceptance is still required.

## Verified in this workspace

- Flutter 3.47.6 / Dart 3.13.5, pinned dependencies and pinned TDLib 1.8.67 schema.
- Static analysis completed with no issues.
- 24 automated tests passed, including request correlation, synchronization replay and offline retries, protocol validation, selected-topic boundaries, media export checks, and mobile/desktop large-text composer layouts. The optional screenshot export test is skipped in the normal suite.
- A Windows x64 Flutter Release executable compiled with the installed Visual Studio toolchain. This initial build did not yet contain the native TDLib library and is not a complete distributable.
- The supplied logo is included unchanged; platform icon variants have been generated.
- Real API credentials are held in ignored `config/telegram.local.json`; the checked-in example contains placeholders.

## Build work in progress

- Windows TDLib is compiling from the pinned source commit. Native startup smoke testing and a complete final bundle are pending.
- Android's initial build found an outdated compile SDK in the pinned desktop-drop plugin. The project now overrides that plugin to API 36; the build is being rerun.
- The first Android TDLib compilation exhausted WSL's memory-backed `/tmp`. The script now builds in persistent Linux storage, with release debug information disabled. Both ABI outputs and final APK packaging are pending.

## Acceptance and distribution limits

- No real Telegram login, message, group creation, pairing, media transfer, notification delivery, or two-account device acceptance has been performed. Follow [TESTING.md](TESTING.md) using deliberately authorized accounts and conversations.
- Android release signing requires the owner's keystore and ignored signing configuration. A debug APK, when available, is only a development build.
- Android immediate notifications depend on the app remaining runnable under OS lifecycle restrictions; no push service or foreground service is implemented. Windows closing the window quits the app; no tray service is implemented.
- Windows automatic export with the unmetered-only preference waits because network cost cannot currently be established. The user can explicitly disable this restriction in storage settings.
- Media sends are individual attachments; album composition and clipboard-image paste are not implemented. Supported voice recording uses AAC/M4A as permitted by the pinned TDLib schema.
- The future pet boundary is documented only; no pet code or backend is included.

Source compilation and automated tests are not evidence that live Telegram acceptance passed. Do not label this client production accepted until the device checklist has actually been completed.
