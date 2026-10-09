$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$flutter = if (Get-Command flutter -ErrorAction SilentlyContinue) { 'flutter' } else { 'C:\Projects\WhatsGramFlutter\bin\flutter.bat' }
if (!(Test-Path config/telegram.local.json)) { throw 'Configure the ignored local API credentials first.' }
foreach ($abi in @('arm64-v8a', 'x86_64')) {
    if (!(Test-Path "android/app/src/main/jniLibs/$abi/libtdjson.so")) { throw "Missing TDLib: $abi" }
}
$previousSigning = $env:ORG_GRADLE_PROJECT_developmentSigning
try {
    $env:ORG_GRADLE_PROJECT_developmentSigning = 'true'
    & $flutter build apk --release --no-pub --split-per-abi --target-platform android-arm64,android-x64 --dart-define-from-file=config/telegram.local.json
    if ($LASTEXITCODE -ne 0) { throw 'Optimized development build failed.' }
} finally {
    $env:ORG_GRADLE_PROJECT_developmentSigning = $previousSigning
}
# Verify/sign explicitly: Flutter/AGP combinations may emit unsigned split APKs.
if (!(Test-Path android/key.properties)) {
    $sdk = $env:ANDROID_SDK_ROOT
    if (!$sdk) { $sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
    $buildTools = Get-ChildItem (Join-Path $sdk 'build-tools') -Directory | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    $signer = Join-Path $buildTools.FullName 'apksigner.bat'
    $debugKey = Join-Path $env:USERPROFILE '.android\debug.keystore'
    if (!(Test-Path $debugKey)) { throw 'Generate the standard Android debug keystore with a debug build first.' }
    foreach ($abi in @('arm64-v8a', 'x86_64')) {
        $apk = "build/app/outputs/flutter-apk/app-$abi-release.apk"
        & $signer sign --ks $debugKey --ks-key-alias androiddebugkey --ks-pass pass:android --key-pass pass:android $apk
        if ($LASTEXITCODE -ne 0) { throw 'Development signing failed.' }
        & $signer verify $apk
        if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed.' }
    }
}
Write-Output 'Optimized per-ABI APKs are in build/app/outputs/flutter-apk. Without owner release keys they use the local debug identity, not production signing.'
