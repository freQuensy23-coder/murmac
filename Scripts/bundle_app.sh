#!/usr/bin/env bash
# Builds a self-contained Murmac.app bundle with native Metal LLM & sherpa-onnx libraries.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
NATIVE_DIR="${MURMAC_NATIVE_LIBS_DIR:-$ROOT/.cache/native/macos-arm64}"
APP_DIR="$ROOT/dist/Murmac.app"

if [[ ! -f "$NATIVE_DIR/libmurmur_llm.dylib" || ! -f "$NATIVE_DIR/libsherpa-onnx-c-api.dylib" ]]; then
  echo "==> Native libraries not found in $NATIVE_DIR; building them first..."
  "$ROOT/native/build_native.sh" all
fi

echo "==> Building Murmac ($CONFIG)..."
cd "$ROOT"
swift build -c "$CONFIG" --product Murmac

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/Murmac"
[[ -x "$BIN" ]] || { echo "Binary not found: $BIN" >&2; exit 1; }

echo "==> Packaging $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Frameworks" "$APP_DIR/Contents/Resources"

cp "$BIN" "$APP_DIR/Contents/MacOS/Murmac"

# Copy SwiftPM resource bundles into Contents/Resources (loaded by MurmacCoreResources / MurmacAppResources)
for b in "$BIN_DIR"/*.bundle; do
  [[ -d "$b" ]] || continue
  cp -R "$b" "$APP_DIR/Contents/Resources/"
done

# Copy native dylibs + ggml Metal/BLAS/CPU backend modules
cp -a "$NATIVE_DIR"/lib*.dylib "$APP_DIR/Contents/Frameworks/"
cp -a "$NATIVE_DIR"/lib*.so "$APP_DIR/Contents/Frameworks/"

cat > "$APP_DIR/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Murmac</string>
  <key>CFBundleIdentifier</key>
  <string>app.murmur.murmac</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Murmac</string>
  <key>CFBundleDisplayName</key>
  <string>Murmac</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Murmac records your voice locally on your Mac to transcribe dictation offline.</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>Murmac optionally reads on-screen text from your active window using Apple Vision (locally in memory) to improve names, spelling, and formatting.</string>
</dict>
</plist>
EOF

# Ad-hoc sign frameworks and app bundle
for f in "$APP_DIR/Contents/Frameworks"/lib*.dylib "$APP_DIR/Contents/Frameworks"/lib*.so; do
  [[ -f "$f" && ! -L "$f" ]] || continue
  codesign --force --sign - "$f"
done
codesign --force --deep --sign - "$APP_DIR"

echo "==> Packaged successfully: $APP_DIR"
ls -lh "$APP_DIR/Contents/MacOS/Murmac"
ls -lh "$APP_DIR/Contents/Frameworks"
