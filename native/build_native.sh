#!/usr/bin/env bash
# Builds/fetches Murmac's macOS native libraries into .cache/native/macos-arm64:
#   1. libmurmur_llm.dylib (+ libllama, libggml, Metal + CPU backends) via CMake
#   2. libsherpa-onnx-c-api.dylib (+ libonnxruntime.dylib) from pinned sherpa-onnx v2.0.1 macOS arm64 release
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${MURMAC_NATIVE_LIBS_DIR:-$ROOT/.cache/native/macos-arm64}"
BUILD_DIR="$ROOT/.cache/native/build/murmur_llm"
DL_DIR="$ROOT/.cache/native/dl"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 8)}"

SHERPA_VERSION="2.0.1"
SHERPA_ARCHIVE="sherpa-onnx-v${SHERPA_VERSION}-osx-arm64-shared-no-tts-lib.tar.bz2"
SHERPA_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/v${SHERPA_VERSION}/${SHERPA_ARCHIVE}"
SHERPA_SHA256="ac5594ad237db56ec4a6c4b3fc48700441b33a07bb71c235f35530a52a93f2e3"

mkdir -p "$OUT_DIR" "$DL_DIR"

WHAT="${1:-all}"

build_sherpa() {
  echo "==> Preparing sherpa-onnx v${SHERPA_VERSION} (macOS arm64)..."
  local archive="$DL_DIR/$SHERPA_ARCHIVE"
  if [[ ! -f "$archive" ]] || ! echo "$SHERPA_SHA256  $archive" | shasum -a 256 -c --status; then
    rm -f "$archive.part"
    curl -fSL --retry 3 -o "$archive.part" "$SHERPA_URL"
    mv "$archive.part" "$archive"
  fi
  echo "$SHERPA_SHA256  $archive" | shasum -a 256 -c --status

  local tmp="$ROOT/.cache/native/build/sherpa_extract"
  rm -rf "$tmp"
  mkdir -p "$tmp"
  tar -xjf "$archive" -C "$tmp"

  cp -f "$tmp"/sherpa-onnx-*/lib/libsherpa-onnx-c-api.dylib "$OUT_DIR/"
  cp -f "$tmp"/sherpa-onnx-*/lib/libonnxruntime.dylib "$OUT_DIR/"
  chmod +w "$OUT_DIR/libsherpa-onnx-c-api.dylib" "$OUT_DIR/libonnxruntime.dylib"

  # Ensure clean @rpath install names so dlopen works both from .cache and from Murmac.app/Contents/Frameworks
  install_name_tool -id "@rpath/libonnxruntime.dylib" "$OUT_DIR/libonnxruntime.dylib"
  install_name_tool -id "@rpath/libsherpa-onnx-c-api.dylib" "$OUT_DIR/libsherpa-onnx-c-api.dylib"
  for dep in $(otool -L "$OUT_DIR/libsherpa-onnx-c-api.dylib" | awk '/libonnxruntime/{print $1}'); do
    install_name_tool -change "$dep" "@rpath/libonnxruntime.dylib" "$OUT_DIR/libsherpa-onnx-c-api.dylib"
  done
  install_name_tool -add_rpath "@loader_path" "$OUT_DIR/libsherpa-onnx-c-api.dylib" 2>/dev/null || true

  # Re-sign ad-hoc after install_name_tool modification (required on Apple Silicon)
  codesign --force --sign - "$OUT_DIR/libonnxruntime.dylib"
  codesign --force --sign - "$OUT_DIR/libsherpa-onnx-c-api.dylib"
  echo "==> sherpa-onnx installed in $OUT_DIR"
}

build_llm() {
  echo "==> Building murmur_llm (llama.cpp + Metal)..."
  cmake -S "$ROOT/native/murmur_llm" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DCMAKE_LIBRARY_OUTPUT_DIRECTORY="$OUT_DIR" \
    -DCMAKE_RUNTIME_OUTPUT_DIRECTORY="$OUT_DIR" \
    -DMURMUR_BUILD_VARIANT="macos-metal"
  cmake --build "$BUILD_DIR" --parallel "$JOBS" --target murmur_llm murmur-llm-bench

  # Copy llama.cpp / ggml shared libraries & backend plugins (Metal, BLAS, CPU) into $OUT_DIR
  if [[ -d "$BUILD_DIR/bin" ]]; then
    cp -a "$BUILD_DIR/bin"/lib*.dylib "$OUT_DIR/" 2>/dev/null || true
    cp -a "$BUILD_DIR/bin"/lib*.so "$OUT_DIR/" 2>/dev/null || true
  fi

  # Normalize rpaths and ad-hoc sign all real dylibs/so files and bench binary
  for f in "$OUT_DIR"/lib*.dylib "$OUT_DIR"/lib*.so; do
    [[ -f "$f" && ! -L "$f" ]] || continue
    chmod +w "$f"
    install_name_tool -add_rpath "@loader_path" "$f" 2>/dev/null || true
    codesign --force --sign - "$f"
  done
  if [[ -f "$OUT_DIR/murmur-llm-bench" ]]; then
    install_name_tool -add_rpath "@executable_path" "$OUT_DIR/murmur-llm-bench" 2>/dev/null || true
    codesign --force --sign - "$OUT_DIR/murmur-llm-bench"
  fi
  echo "==> murmur_llm built in $OUT_DIR"
}

case "$WHAT" in
  all)    build_sherpa; build_llm ;;
  sherpa) build_sherpa ;;
  llm)    build_llm ;;
  *)      echo "Usage: $0 [all|sherpa|llm]" >&2; exit 1 ;;
esac

echo "==> Native artifacts ready:"
ls -lh "$OUT_DIR"
