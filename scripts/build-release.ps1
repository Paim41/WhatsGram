param([ValidateSet('windows','android')][string]$Target = 'windows')
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$flutter = if (Get-Command flutter -ErrorAction SilentlyContinue) { 'flutter' } else { 'C:\Projects\WhatsGramFlutter\bin\flutter.bat' }
if (!(Test-Path 'config/telegram.local.json')) { throw 'Configure config/telegram.local.json first.' }
& $flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'Static analysis failed.' }
& $flutter test
if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
if ($Target -eq 'windows') {
  if (!(Test-Path 'native/windows/tdjson.dll')) { throw 'Build the pinned Windows TDLib first.' }
  & $flutter build windows --release --dart-define-from-file=config/telegram.local.json
  if ($LASTEXITCODE -ne 0) { throw 'Windows release build failed.' }
  New-Item -ItemType Directory -Path dist -Force | Out-Null
  Compress-Archive -Path 'build/windows/x64/runner/Release/*' -DestinationPath 'dist/WhatsGram-windows-x64.zip' -Force
} else {
  if (!(Test-Path 'android/key.properties')) { throw 'Provide release signing configuration in android/key.properties.' }
  foreach ($abi in @('arm64-v8a','x86_64')) { if (!(Test-Path "android/app/src/main/jniLibs/$abi/libtdjson.so")) { throw "Missing TDLib for $abi" } }
  & $flutter build apk --release --target-platform android-arm64,android-x64 --split-per-abi --dart-define-from-file=config/telegram.local.json
  if ($LASTEXITCODE -ne 0) { throw 'Android release build failed.' }
}
