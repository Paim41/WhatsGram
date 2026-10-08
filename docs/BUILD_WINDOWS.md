# Windows x64 build

Use Windows, Flutter 3.47.6, Visual Studio Desktop development with C++, CMake, a Windows SDK, Git, and PowerShell. See [Flutter's Windows build documentation](https://docs.flutter.dev/platform-integration/windows/building).

```powershell
Set-Location C:\Projects\WhatsGram
$env:Path = "C:\Projects\WhatsGramFlutter\bin;$env:Path"
./scripts/build-tdlib-windows.ps1 -Jobs 4
flutter pub get
./scripts/prepare-windows-plugins.ps1
flutter analyze
flutter test
./scripts/run.ps1 windows
./scripts/build-release.ps1 windows
```

The native script checks out the exact TDLib commit from `native/tdlib.lock.json` and vcpkg commit `2750401336fb7c95f6619657a46a7e798661341c`. vcpkg builds OpenSSL and zlib statically with the dynamic MSVC runtime. It builds `tdjson.dll` with Ninja in Release mode and copies it into `native/windows/`. CMake bundles every DLL in that directory next to the app.

The pinned notification plugin uses the WinRT `/await` bridge. The application CMake file acknowledges its deprecation for the installed MSVC 14.51 compiler. This is a compatibility setting, not a claim that the plugin already uses modern C++ coroutines.

Distribute the entire `build/windows/x64/runner/Release/` directory or `dist/WhatsGram-windows-x64.zip`, including `whatsgram.exe`, `tdjson.dll`, Flutter/media runtime DLLs and `data/`. Do not distribute the EXE alone. Target machines also need Microsoft's supported x64 Visual C++ runtime; use Microsoft's redistributable rather than copying arbitrary system DLLs.

The window is resizable. Closing it quits the process and stops message reception. Tray mode is not implemented. Credential-bearing binaries are local artifacts; source control excludes them.

Native build prerequisites may take substantial time and disk space to download. Errors are propagated by the scripts rather than being treated as successful builds. The current verification result is recorded in `VERIFICATION.md`.

If MSVC reports missing files under `windows/flutter/ephemeral/cpp_client_wrapper`, stop the build and restore that generated directory from the matching Flutter SDK's `bin/cache/artifacts/engine/windows-x64/cpp_client_wrapper`. Use one consistent short project path for subsequent builds. This was necessary on the original workstation after regenerating the build directory.
