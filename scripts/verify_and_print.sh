#!/usr/bin/env bash
set -euo pipefail

AAR_PATH="${1:-dist/libv2ray.aar}"
if [ ! -f "$AAR_PATH" ]; then
  echo "::error::AAR not found at $AAR_PATH"
  exit 1
fi

echo "[verify] list AAR content:"
unzip -l "$AAR_PATH" || true

echo "[verify] check for libgojni.so presence:"
unzip -l "$AAR_PATH" | grep -E 'jni/.*/libgojni\.so' || {
  echo "::error::libgojni.so not found inside AAR"
  exit 1
}

echo "[ok] AAR contains libgojni.so"
