#!/usr/bin/env bash
# 下载离线语音识别用到的原生库（sherpa-onnx），解压到 android/app/src/main/jniLibs。
#
# 这些 .so 一共 31MB，不进 git 仓库（会让仓库变成几百 MB）。
# 首次 clone 后跑一次即可，之后不用管。
set -euo pipefail

VERSION="${SHERPA_VERSION:-1.13.8}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/android/app/src/main/jniLibs"
TMP="$(mktemp -d)"
ARCHIVE="$TMP/sherpa-android.tar.bz2"

URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/v${VERSION}/sherpa-onnx-v${VERSION}-android.tar.bz2"
MIRROR="https://ghfast.top/${URL}"

echo "==> 下载 sherpa-onnx v${VERSION} 原生库（约 44MB）"
if ! curl -fL --retry 2 --max-time 900 -o "$ARCHIVE" "$URL"; then
  echo "    直连失败，换镜像"
  curl -fL --retry 2 --max-time 900 -o "$ARCHIVE" "$MIRROR"
fi

echo "==> 解压 arm64-v8a"
mkdir -p "$DEST"
tar xjf "$ARCHIVE" -C "$TMP" ./jniLibs/arm64-v8a
cp "$TMP"/jniLibs/arm64-v8a/*.so "$DEST/arm64-v8a/"

rm -rf "$TMP"
echo "==> 完成，已放入：$DEST/arm64-v8a"
ls -lh "$DEST/arm64-v8a"
echo
echo "现在可以 flutter build apk --release --target-platform android-arm64"
