# Android build

The Flutter host targets Android API 26+, arm64-v8a phones and x86_64 emulators. Install Android Studio, the platform/NDK versions requested by Flutter's Gradle project, command-line tools and Java 17 or a compatible Android Studio JBR. Review Android SDK licenses with the SDK tooling. Android SDK and Flutter locations belong in ignored `android/local.properties`.

## Native TDLib

The original Windows machine can also build the native libraries through its Ubuntu WSL installation:

```powershell
wsl -d Ubuntu -u root -- bash -lc "apt-get update && apt-get install -y build-essential cmake ninja-build git gperf php-cli perl curl wget unzip zlib1g-dev libssl-dev"
wsl -d Ubuntu -- bash /mnt/c/Projects/WhatsGram/scripts/build-tdlib-android-wsl.sh
```

This alternative pins and verifies NDK r28c / 28.2.13676358 and OpenSSL 3.6.5, builds both arm64-v8a and x86_64, and copies the resulting libraries into the Android project. It builds in `$HOME/.cache/whatsgram-native-build` on WSL's Linux filesystem to avoid slow cross-filesystem compilation and memory-backed `/tmp` limits. Set `WHATSGRAM_NATIVE_SCRATCH` to change the build directory. Allow at least 15 GB of free disk space. Use the script matching your environment; do not mix outputs from different TDLib commits.

`scripts/build-tdlib-android.sh` uses TDLib's pinned official JSON build pipeline. Run it in WSL/Linux with a **Linux** Android SDK containing NDK `23.2.8568313` and CMake `3.22.1`, plus C/C++ tools, Ninja, make, Perl, PHP, gperf, curl/wget, unzip and Git. Windows SDK executables cannot run as Linux SDK executables.

```bash
export ANDROID_SDK_ROOT=/path/to/linux-android-sdk
bash scripts/build-tdlib-android.sh
```

The script checks out the pinned TDLib commit, builds OpenSSL and the JSON shared library, and places `libtdjson.so` under `android/app/src/main/jniLibs/arm64-v8a/` and `x86_64/`. The upstream script also compiles 32-bit targets, but WhatsGram packages only the two declared ABIs. C++ is linked statically. Do not package a Windows DLL as an Android library.

## Run/debug

```powershell
flutter pub get
flutter devices
flutter run --dart-define-from-file=config/telegram.local.json
flutter build apk --debug --target-platform android-arm64 --dart-define-from-file=config/telegram.local.json
```

A debug APK is for development, uses a debug signing identity, and is not a signed production release. Native TDLib is required for Telegram to connect even if the Flutter APK itself compiles.

## Release signing

Create and safely back up your own keystore. Keep its password out of source control. Create ignored `android/key.properties`:

```properties
storeFile=C:/private/whatsgram-release.jks
storePassword=YOUR_PASSWORD
keyAlias=whatsgram
keyPassword=YOUR_PASSWORD
```

```powershell
./scripts/build-release.ps1 android
```

The script requires both native libraries, a local credential file, and explicit release signing configuration. Gradle does not silently substitute debug signing for Release. APKs are written to `build/app/outputs/flutter-apk/`.

Android exports use the system document picker / Storage Access Framework. Automatic export retains a user-chosen directory URI permission. There is no broad storage permission or silent gallery export. Backup and device transfer exclude app data and sessions. Microphone and notification permissions are requested at the feature boundary.

Without a push service or optional foreground service, reliable reception is limited to the running app and OS lifecycle conditions. Force-stop/process death prevents immediate local notification delivery. Reopen to restore the session and reconcile settings. See `VERIFICATION.md` for what was actually built and tested.
