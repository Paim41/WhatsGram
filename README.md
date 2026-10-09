<div align="center">

<img src="assets/branding/whatsgram_logo.png" width="140" alt="WhatsGram Logo" />

# WhatsGram

*An unofficial Telegram client for Android and Windows — two independently authenticated accounts, a shared chat-selection workspace, and a Telegram-blue interface.*

<img src="https://img.shields.io/badge/Flutter-Cross--Platform-2489D4?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter cross-platform" />
<img src="https://img.shields.io/badge/Android-ARM64%20%7C%20x86__64-2489D4?style=for-the-badge&logo=android&logoColor=white" alt="Android ARM64 and x86_64" />
<img src="https://img.shields.io/badge/Windows-x64-2489D4?style=for-the-badge&logo=windows&logoColor=white" alt="Windows x64" />
<img src="https://img.shields.io/badge/TDLib-1.8.67-2489D4?style=for-the-badge&logo=telegram&logoColor=white" alt="TDLib 1.8.67" />
<img src="https://img.shields.io/badge/Release-0.1.1%20Preview-F4F8FC?style=for-the-badge&labelColor=2489D4" alt="Release 0.1.1 preview" />

<br /><br />

<a href="https://github.com/Paim41/WhatsGram/releases/download/v0.1.1/WhatsGram-0.1.1-windows-x64.zip"><img src="https://img.shields.io/badge/Download-Windows%20ZIP-2489D4?style=for-the-badge&logo=windows&logoColor=white" alt="Download Windows ZIP" /></a>
<a href="https://github.com/Paim41/WhatsGram/releases/download/v0.1.1/WhatsGram-0.1.1-android-arm64.apk"><img src="https://img.shields.io/badge/Download-Android%20APK-2489D4?style=for-the-badge&logo=android&logoColor=white" alt="Download Android ARM64 APK" /></a>

[All releases](https://github.com/Paim41/WhatsGram/releases) | [Installation guide](docs/DEVICE_GUIDE.md) | [Verification status](docs/VERIFICATION.md)

</div>

---

## Downloads

| Platform | Package | Download |
|---|---|---|
| Windows x64 | Complete desktop ZIP bundle | [Windows ZIP](https://github.com/Paim41/WhatsGram/releases/download/v0.1.1/WhatsGram-0.1.1-windows-x64.zip) |
| Android ARM64 | APK for compatible 64-bit phones | [Android ARM64 APK](https://github.com/Paim41/WhatsGram/releases/download/v0.1.1/WhatsGram-0.1.1-android-arm64.apk) |
| Android x86_64 | APK for compatible Intel devices and emulators | [Android x86_64 APK](https://github.com/Paim41/WhatsGram/releases/download/v0.1.1/WhatsGram-0.1.1-android-x86_64.apk) |
| Checksums | SHA-256 package hashes | [SHA256SUMS](https://github.com/Paim41/WhatsGram/releases/download/v0.1.1/SHA256SUMS-0.1.1.txt) |

**Windows:** close WhatsGram, extract the entire ZIP into a new folder, and run `whatsgram.exe`. Keep every DLL and the `data` folder together.

**Android:** download the APK matching your device architecture and install it. For updates, install over the existing app using the same signing key to retain local app data.

*These are development preview builds. Android packages use development signing, and Windows is not Authenticode signed. Physical-device, two-account acceptance remains outstanding.*

---

## What is implemented

- **Two-account workspace** — independently authenticated Telegram accounts with verified pairing and shared chat selections.
- **Telegram sign-in** — TDLib-driven phone, code, two-step password, email, and QR authorization.
- **Selected conversations** — participant-pair chats, shared supergroups, and real forum topics; selecting a group includes its topics.
- **Messaging tools** — paginated and live text messages, replies, editing, deletion, forwarding, and reactions.
- **Search & preferences** — selected-scope search, active-view read handling, and per-device mute and pin settings.
- **Media & voice** — photo, original-document, and video attachments; native M4A voice recording, playback, and transfer controls.
- **Safe exports** — manual exports and optional automatic media saving, disabled by default.
- **Selection synchronization** — versioned settings events, durable offline changes, deterministic Lamport conflict resolution, and history replay.
- **Responsive interface** — desktop and narrow layouts, light/dark/system themes, and native local notifications.
- **Branding** — Telegram Blue (`#2489D4`), Ice White (`#F4F8FC`), supplied logos, and native app icons.

*Implementation code does not establish a passed live-account acceptance test. Read [VERIFICATION.md](docs/VERIFICATION.md) for actual build/test results and remaining limitations.*

---

## Interface previews

These are renders of the actual welcome screen, before Telegram sign-in.

<div align="center">

<img src="docs/images/welcome-mobile.png" width="240" alt="WhatsGram mobile welcome screen" />
<img src="docs/images/welcome-desktop.png" width="600" alt="WhatsGram desktop welcome screen" />

</div>

---

## Requirements

| Requirement | Version / Detail |
|---|---|
| Flutter | 3.47.6 |
| TDLib | Pinned 1.8.67 native library for the target platform |
| Telegram API credentials | Your own API ID and API hash |
| Platform toolchain | Android or Windows build tools |
| Shared workspace | Two distinct Telegram accounts |

*A single Flutter project targets Android and Windows. Messages and media stay in their original Telegram conversations; a dedicated private Telegram settings supergroup carries validated selection events.*

---

## Local setup

1. Install Flutter 3.47.6 and the toolchain for your target platform.
2. Copy `config/telegram.example.json` to the ignored `config/telegram.local.json`.
3. Add your own Telegram API ID and API hash to the local configuration.
4. Build the pinned TDLib 1.8.67 native library for the target platform.
5. Install dependencies and run the checks below.

```bash
flutter pub get
flutter analyze
flutter test
```

### Run on Windows

```powershell
./scripts/run.ps1 windows
```

### Run on Android

```powershell
./scripts/run.ps1 android
```

The original development workspace is at `C:\Projects\WhatsGram`, with its Flutter SDK at `C:\Projects\WhatsGramFlutter`. You may clone the repository into another short, writable path.

See [SETUP.md](docs/SETUP.md), [BUILD_WINDOWS.md](docs/BUILD_WINDOWS.md), and [BUILD_ANDROID.md](docs/BUILD_ANDROID.md) for complete configuration and native-build instructions.

---

## Workspace behavior

| Behavior | Detail |
|---|---|
| Independent sessions | Each device signs in to its own Telegram session |
| Shared selections | Pairing synchronizes the selection list through a private Telegram settings group |
| Original conversations | Messages and media remain in their original Telegram chats |
| Account access | Pairing does not grant access to another account's private messages |
| Same account on both devices | Supported for sign-in; chat selection still requires an existing workspace with a second distinct account |
| Standalone personal workspace | Not implemented in this version |
| Device preferences | Theme, notifications, mute/pin settings, and exports are configured per device |
| Notifications | Require a running app and are subject to operating-system restrictions |

See the [device guide](docs/DEVICE_GUIDE.md) and [pairing guide](docs/PAIRING.md) for setup.

---

## Privacy & storage

| Design | Detail |
|---|---|
| Telegram conversations | Messages and media stay in their original Telegram conversations |
| Settings synchronization | Validated selection events use a dedicated private Telegram settings supergroup |
| Session keys | Session encryption keys are held in platform secure storage |
| Application backend | No hosted application backend is included |
| External databases | No Supabase, Firebase, or GitHub chat database is included |
| Media exports | Automatic export is off by default |
| Pet system | No pet implementation is included; the future boundary is documented |

*The TDLib JSON FFI transport runs in a dedicated isolate with ordered updates, request correlation, timeouts, shutdown handling, and native-version validation.*

---

## Documentation

| Guide | Contents |
|---|---|
| [Device guide](docs/DEVICE_GUIDE.md) | Phone and Windows installation and usage |
| [Setup](docs/SETUP.md) | Configuration and credentials |
| [Windows build](docs/BUILD_WINDOWS.md) | Native build and complete release bundle |
| [Android build](docs/BUILD_ANDROID.md) | Native build and release signing |
| [Pairing](docs/PAIRING.md) | Workspace pairing and chat selection |
| [Architecture](docs/ARCHITECTURE.md) | Application structure and future pet boundary |
| [Privacy](docs/PRIVACY.md) | Privacy and storage behavior |
| [Testing](docs/TESTING.md) | Tests and two-account acceptance checklist |
| [Verification](docs/VERIFICATION.md) | Actual build/test results and remaining limitations |

**Release status:** WhatsGram must not be advertised as a fully accepted production client until the two-account checklist passes on both devices.

---

## Official references

- [TDLib](https://core.telegram.org/tdlib)
- [TDLib getting started](https://core.telegram.org/tdlib/getting-started)
- [TDLib API documentation](https://core.telegram.org/tdlib/docs/)
- [Telegram API terms](https://core.telegram.org/api/terms)
- [Flutter Windows builds](https://docs.flutter.dev/platform-integration/windows/building)

---

<div align="center">

*Your Telegram conversations, with a shared selection workspace across Android and Windows.*

**Unofficial Telegram client | Telegram Blue & Ice White | Built with Flutter**

</div>

