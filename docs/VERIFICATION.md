# Verification record — 9 October 2026

This is an implemented native Flutter client for Android and Windows. It is not a web application, and live Telegram acceptance is still required.

## Verified in this workspace

- Flutter 3.47.6 / Dart 3.13.5, pinned dependencies and pinned TDLib 1.8.67 schema.
- Static analysis completed with no issues.
- 24 automated tests passed, including request correlation, synchronization replay and offline retries, protocol validation, selected-topic boundaries, media export checks, and mobile/desktop large-text composer layouts. The optional screenshot export test is skipped in the normal suite.
- Windows TDLib 1.8.67 compiled successfully. The native FFI smoke test passed twice: library/version validation, request correlation, initial authorization state, close and recreation. This test used no API credentials or Telegram session.
- Android TDLib compiled successfully for arm64-v8a and x86_64 using NDK r28c and OpenSSL 3.6.5.
- Windows x64 Flutter Release built successfully and was packaged as `dist/WhatsGram-windows-x64.zip`, including TDLib, Flutter/media/plugin runtime libraries and application assets. The packaged TDLib SHA-256 matches the library used by the native smoke test.
- Android development APK built successfully as `dist/WhatsGram-android-development.apk`. Its ZIP contents were checked for both `lib/arm64-v8a/libtdjson.so` and `lib/x86_64/libtdjson.so`. Native ELF headers/dependencies were verified for the intended architectures and Android system libraries.
- Mobile and desktop welcome screenshots were rendered from the actual widgets and visually checked.
- The supplied logo is included unchanged; platform icon variants have been generated.
- Real API credentials are held in ignored `config/telegram.local.json`; the checked-in example contains placeholders.

## Build issues resolved

- Android's initial build found an outdated compile SDK in the pinned desktop-drop plugin. Overriding that plugin to API 36 when its Android DSL is finalized resolved the failure.
- The first Android TDLib compilation exhausted WSL's memory-backed `/tmp`. Building in persistent Linux storage with release debug information disabled resolved this, and both ABI builds completed.
- Windows generated wrapper sources were missing during a rebuild. Restoring the exact files from the pinned Flutter SDK and rebuilding from the short project path resolved it. No Flutter SDK source was modified.

## Acceptance and distribution limits

- No real Telegram login, message, group creation, pairing, media transfer, notification delivery, or two-account device acceptance has been performed. Follow [TESTING.md](TESTING.md) using deliberately authorized accounts and conversations.
- Android release signing requires the owner's keystore and ignored signing configuration. The supplied APK uses debug signing and is only a development build. Neither package has undergone real-device Telegram acceptance. The Windows application is not Authenticode signed.
- Android immediate notifications depend on the app remaining runnable under OS lifecycle restrictions; no push service or foreground service is implemented. Windows closing the window quits the app; no tray service is implemented.
- Windows automatic export with the unmetered-only preference waits because network cost cannot currently be established. The user can explicitly disable this restriction in storage settings.
- Media sends are individual attachments; album composition and clipboard-image paste are not implemented. Supported voice recording uses AAC/M4A as permitted by the pinned TDLib schema.
- The future pet boundary is documented only; no pet code or backend is included.

Source compilation and automated tests are not evidence that live Telegram acceptance passed. Do not label this client production accepted until the device checklist has actually been completed.
