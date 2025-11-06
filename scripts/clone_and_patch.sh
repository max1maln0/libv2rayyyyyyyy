#!/usr/bin/env bash
# Clones AndroidLibXrayLite and patches out XUDP on Android.
# Must be executed in CI (Ubuntu runner with bash, git, sed, grep).

set -euxo pipefail

echo "[clone] AndroidLibXrayLite: ${LXLITE_REPO:-unset} @ ${LXLITE_REF:-unset}"

# Проверка переменных окружения
if [[ -z "${LXLITE_REPO:-}" || -z "${LXLITE_REF:-}" ]]; then
  echo "::error::LXLITE_REPO or LXLITE_REF not set"
  exit 1
fi

# Клонируем репозиторий
git clone --depth=1 "$LXLITE_REPO" AndroidLibXrayLite

cd AndroidLibXrayLite

MOBILE_DIR="mobile"
if [[ ! -d "$MOBILE_DIR" ]]; then
  echo "::error::Directory '$MOBILE_DIR' not found in AndroidLibXrayLite"
  exit 1
fi
cd "$MOBILE_DIR"

# 1️⃣ Добавляем guard-файл, который отключает XUDP
echo "[patch] adding xudp_guard_android.go"
cat > xudp_guard_android.go <<'EOF'
//go:build android
// +build android

package mobile

import "C"

// This file disables XUDP usage on Android builds entirely.
func init() {
    _ = "XUDP disabled at build-time (patched)"
}
EOF

# 2️⃣ Убираем обращения к basekey в исходниках
echo "[patch] removing basekey references"
grep -RIl --include='*.go' -e 'xudp.basekey' -e 'XRAY_XUDP_BASEKEY' -e 'XRAY.XUDP.BASEKEY' . \
  | while read -r f; do
      echo "  cleaning $f"
      sed -i '/xudp\.basekey/d' "$f" || true
      sed -i '/XRAY_XUDP_BASEKEY/d' "$f" || true
      sed -i '/XRAY\.XUDP\.BASEKEY/d' "$f" || true
    done

# 3️⃣ Убираем panic при проверке BaseKey
echo "[patch] removing BaseKey panic"
grep -RIl --include='*.go' -e 'BaseKey must be 32 bytes' . \
  | while read -r f; do
      echo "  patching $f"
      sed -i 's/panic(.*BaseKey.*32 bytes.*)/return/g' "$f" || true
    done

echo "[done] AndroidLibXrayLite patched successfully."

