#!/usr/bin/env bash
set -euo pipefail
# Run in WSL/Linux with its own Linux Android SDK/NDK; Windows SDK binaries do
# not work inside WSL. Uses TDLib's pinned, upstream Android build pipeline.
root="$(cd "$(dirname "$0")/.." && pwd)"
: "${ANDROID_SDK_ROOT:?Set ANDROID_SDK_ROOT to a Linux SDK with NDK 23.2.8568313 and CMake 3.22.1}"
commit=42e6a5259551178d1dab54a22ad96d14bd906e20
if [[ ! -d "$root/native/td-android" ]]; then
  git clone --filter=blob:none --no-checkout https://github.com/tdlib/td.git "$root/native/td-android"
fi
cd "$root/native/td-android"
git fetch origin "$commit" --depth 1
git checkout --detach "$commit"
cd example/android
./build-openssl.sh "$ANDROID_SDK_ROOT" 23.2.8568313 third-party/openssl openssl-3.6.5
./build-tdlib.sh "$ANDROID_SDK_ROOT" 23.2.8568313 third-party/openssl c++_static JSON
for abi in arm64-v8a x86_64; do
  mkdir -p "$root/android/app/src/main/jniLibs/$abi"
  cp "tdlib/libs/$abi/libtdjson.so" "$root/android/app/src/main/jniLibs/$abi/"
done
