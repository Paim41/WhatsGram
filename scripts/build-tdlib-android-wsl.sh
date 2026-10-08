#!/usr/bin/env bash
set -euo pipefail
# Isolated Linux build using a dedicated scratch directory on WSL's ext4 disk.
root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="${WHATSGRAM_NATIVE_SCRATCH:-$HOME/.cache/whatsgram-native-build}"
sdk="$scratch/sdk"
mkdir -p "$sdk/ndk" "$scratch"
cd "$scratch"
ndk_version=28.2.13676358
if [[ ! -d "$sdk/ndk/$ndk_version" ]]; then
  curl --fail --location --retry 3 https://dl.google.com/android/repository/android-ndk-r28c-linux.zip -o ndk.zip
  echo 'a7b54a5de87fecd125a17d54f73c446199e72a64  ndk.zip' | sha1sum -c -
  unzip -q ndk.zip
  mv android-ndk-r28c "$sdk/ndk/$ndk_version"
fi
export ANDROID_NDK_ROOT="$sdk/ndk/$ndk_version"
export ANDROID_NDK_HOME="$ANDROID_NDK_ROOT"
export PATH="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"
if [[ ! -d td/.git ]]; then git clone --filter=blob:none --no-checkout https://github.com/tdlib/td.git td; fi
git -C td fetch origin 42e6a5259551178d1dab54a22ad96d14bd906e20 --depth 1
git -C td checkout --detach 42e6a5259551178d1dab54a22ad96d14bd906e20
cmake -S td -B generated -G Ninja -DTD_GENERATE_SOURCE_FILES=ON -DCMAKE_BUILD_TYPE=Release
cmake --build generated --parallel 2
if [[ ! -f openssl.tar.gz ]]; then curl --fail --location --retry 3 https://github.com/openssl/openssl/releases/download/openssl-3.6.5/openssl-3.6.5.tar.gz -o openssl.tar.gz; fi
echo 'a2157c2830efdec3788939b00c9b0638306d3f0bbb76dc4832ee503bb397df98  openssl.tar.gz' | sha256sum -c -
for abi in arm64-v8a x86_64; do
  if [[ "$abi" == arm64-v8a ]]; then openssl_target=android-arm64; else openssl_target=android-x86_64; fi
  openssl_dir="$scratch/openssl-$abi"
  if [[ ! -f "$openssl_dir/lib/libcrypto.a" ]]; then
    mkdir -p "$scratch/openssl-src-$abi"
    tar -xf openssl.tar.gz --strip-components=1 -C "$scratch/openssl-src-$abi"
    pushd "$scratch/openssl-src-$abi"
    ./Configure "$openssl_target" -D__ANDROID_API__=26 no-shared no-tests --prefix="$openssl_dir" --libdir=lib
    make -j2
    make install_sw
    popd
  fi
  cmake -S td -B "build-$abi" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_FLAGS_RELEASE='-O2 -DNDEBUG -g0' \
    -DCMAKE_C_FLAGS_RELEASE='-O2 -DNDEBUG -g0' \
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$abi" -DANDROID_PLATFORM=android-26 -DANDROID_STL=c++_static \
    -DOPENSSL_ROOT_DIR="$openssl_dir" -DOPENSSL_INCLUDE_DIR="$openssl_dir/include" \
    -DOPENSSL_CRYPTO_LIBRARY="$openssl_dir/lib/libcrypto.a" -DOPENSSL_SSL_LIBRARY="$openssl_dir/lib/libssl.a" \
    -DTD_ENABLE_JNI=OFF
  cmake --build "build-$abi" --target tdjson --parallel 2
  mkdir -p "$root/android/app/src/main/jniLibs/$abi"
  "$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" --strip-unneeded "build-$abi/libtdjson.so"
  cp "build-$abi/libtdjson.so" "$root/android/app/src/main/jniLibs/$abi/"
done
