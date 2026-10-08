# Set up WhatsGram

WhatsGram is an unofficial client using the Telegram API. This repository is a native Flutter application for Android and Windows; it is not a website. No hosted application backend is required.

## Location and tools

On the original build computer, `C:\Projects\WhatsGram` is a directory junction to this project in the Codex outputs folder. `C:\Projects\WhatsGramFlutter` points to the local Flutter SDK. The short paths avoid Windows tool path-length limitations. You can clone the repository into another short writable directory such as `C:\src\WhatsGram`.

The implementation uses Flutter **3.47.6**, Dart **3.13.5**, and TDLib **1.8.67**, commit `42e6a5259551178d1dab54a22ad96d14bd906e20`. Direct Dart dependencies are pinned in `pubspec.yaml`; transitive versions and hashes are in `pubspec.lock`. Use the lockfile.

Install Flutter from the [official SDK archive](https://docs.flutter.dev/install/archive). Install Android Studio and its Android SDK, command-line tools, platform and NDK. For Windows builds install Visual Studio with **Desktop development with C++**, CMake tools, and a Windows SDK. Visual Studio and Visual Studio Code are different products.

```powershell
$env:Path = "C:\Projects\WhatsGramFlutter\bin;$env:Path"
Set-Location C:\Projects\WhatsGram
flutter doctor -v
flutter pub get
```

If Flutter reports missing Windows symlink permission, enable Windows Developer Mode yourself or run `./scripts/prepare-windows-plugins.ps1` after dependencies have downloaded, then repeat `flutter pub get`. This helper creates project-local directory junctions; it does not change machine policy. Re-run it after a dependency change if needed.

## Telegram developer credentials

Use [my.telegram.org](https://my.telegram.org), sign in with your own account, open API development tools, and obtain an `api_id` and `api_hash`. See [Telegram's instructions](https://core.telegram.org/api/obtaining_api_id) and [API terms](https://core.telegram.org/api/terms).

```powershell
Copy-Item config/telegram.example.json config/telegram.local.json
notepad config/telegram.local.json
```

Replace the placeholder values in **telegram.local.json**, not the example. Do not paste OTPs, passwords or sessions into that file. `telegram.local.json` is ignored by Git. For the original build, credentials accidentally entered in the example were moved into this local file and the example was restored before Git initialization.

Pass the same ignored configuration when running or building:

```powershell
flutter run -d windows --dart-define-from-file=config/telegram.local.json
```

Build-time credentials can be extracted from an installed application. Do not describe them as inaccessible secrets, and do not publish credential-bearing binaries without understanding this. The source repository contains only placeholders.

## Branding

The supplied original PNG is `assets/branding/whatsgram_logo.png`. Its pixels, proportions and transparency are preserved. To replace it, replace that file and run:

```powershell
./scripts/generate-icons.ps1
```

This generates padded Android launcher/adaptive images and a Windows ICO with 16, 24, 32, 48, 64, 128 and 256 pixel sizes. A separate single-color Android notification icon lives in `android/app/src/main/res/drawable/ic_notification.xml`. If the original logo is missing, the app uses a WG text fallback. Personal use does not establish official endorsement or trademark permission.

## Run

Build the appropriate TDLib library first: [Windows](BUILD_WINDOWS.md), [Android](BUILD_ANDROID.md). Then use `./scripts/run.ps1 windows` or `./scripts/run.ps1 android`.

Sign in with your own phone number. Telegram chooses where the code is delivered; it may arrive inside Telegram rather than SMS. Password, email and QR states follow actual TDLib authorization updates. Registration and purchase-required states direct you to an official Telegram client. The app never treats a submitted code as a successful login until TDLib reports ready.

See [pairing](PAIRING.md), [privacy](PRIVACY.md), and the [manual testing checklist](TESTING.md).

## Troubleshooting

- **Cannot load tdjson.dll / libtdjson.so:** build the pinned native source, verify x64 on Windows or the device's Android ABI, and include runtime files. A different TDLib version is rejected.
- **Android toolchain:** use Android Studio SDK Manager to install required packages and review/accept SDK licenses. `flutter doctor -v` shows missing tools.
- **Verification code or password rejected:** use the current code/delivery method and retry. Credentials are never persisted by the form.
- **Rate limit:** follow Telegram's wait interval. Repeated login or send attempts can extend restrictions.
- **Access required:** join/open the group using your own account; synchronized selections do not grant membership.
- **Automatic export pending:** check size/category filters, folder permission and network policy. On Windows network cost is unknown, so the unmetered-only option conservatively waits until disabled.
- **No notifications after quitting:** the app uses local notifications from a running TDLib process. There is no push relay, Android foreground service, or Windows tray process.
