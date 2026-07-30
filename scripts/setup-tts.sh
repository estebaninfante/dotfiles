#!/usr/bin/env bash
set -euo pipefail

TTS_DIR="$HOME/.local/share/tts"
PIPER_DIR="$TTS_DIR/piper"
PIPER_VOICES_DIR="$PIPER_DIR/voices"
PIPER_VERSION="2023.11.14-2"

mkdir -p "$PIPER_VOICES_DIR"

echo "=== Piper TTS ==="
if [ ! -f "$PIPER_DIR/piper" ]; then
  echo "Downloading Piper binary..."
  curl -sL "https://github.com/rhasspy/piper/releases/download/$PIPER_VERSION/piper_linux_x86_64.tar.gz" \
    -o /tmp/piper.tar.gz
  tar xzf /tmp/piper.tar.gz -C /tmp/
  mkdir -p "$PIPER_DIR"
  cp /tmp/piper/piper "$PIPER_DIR/"
  cp /tmp/piper/piper_phonemize "$PIPER_DIR/"
  cp /tmp/piper/lib* "$PIPER_DIR/" 2>/dev/null || true
  cp /tmp/piper/espeak-ng-data "$PIPER_DIR/" -r
  cp /tmp/piper/libespeak* "$PIPER_DIR/" 2>/dev/null || true
  cp /tmp/piper/libtashkeel* "$PIPER_DIR/" 2>/dev/null || true
  chmod +x "$PIPER_DIR/piper" "$PIPER_DIR/piper_phonemize"
  rm -rf /tmp/piper /tmp/piper.tar.gz
  echo "Piper installed at $PIPER_DIR"
else
  echo "Piper already installed"
fi

download_voice() {
  local name="$1"
  local url="$2"
  local json="$PIPER_VOICES_DIR/$name.onnx.json"
  local model="$PIPER_VOICES_DIR/$name.onnx"
  if [ ! -f "$model" ]; then
    echo "Downloading voice: $name..."
    curl -sL "$url" -o "$model"
    curl -sL "${url}.json" -o "$json"
    echo "  Downloaded $name"
  else
    echo "  Voice $name already present"
  fi
}

echo "Downloading Piper voices..."
download_voice "es_ES-davefx-medium" \
  "https://huggingface.co/rhasspy/piper-voices/resolve/main/es/es_ES/davefx/medium/es_ES-davefx-medium.onnx"
download_voice "es_ES-sharvard-medium" \
  "https://huggingface.co/rhasspy/piper-voices/resolve/main/es/es_ES/sharvard/medium/es_ES-sharvard-medium.onnx"
download_voice "en_US-amy-medium" \
  "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx"
download_voice "en_US-lessac-medium" \
  "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/en_US-lessac-medium.onnx"

echo ""
echo "=== Kokoro TTS ==="
if python3 -c "import kokoro" 2>/dev/null; then
  echo "Kokoro already installed"
else
  # Kokoro requires Python <3.13
  PY_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
  if python3 -c "import sys; exit(0 if sys.version_info < (3,13) else 1)" 2>/dev/null; then
    echo "Installing Kokoro..."
    pip3 install --user 'kokoro>=0.7,<0.8' 2>&1 | tail -3
  else
    echo "Kokoro requires Python <3.13 (current: $PY_VER). Skipping."
  fi
fi

echo ""
echo "=== espeak-ng ==="
if command -v espeak-ng &>/dev/null; then
  echo "espeak-ng available"
  espeak-ng --voices 2>/dev/null | grep -iE 'es|en' | head -5
fi

echo ""
echo "TTS setup complete!"
echo "  - Piper: $PIPER_DIR"
echo "  - espeak-ng: system"
echo "  - Kokoro: $(python3 -c 'import kokoro; print(kokoro.__version__)' 2>/dev/null || echo 'not installed')"
echo ""
echo "Test with: tts --help"