#!/usr/bin/env bash
# shellcheck disable=SC2086

set -euo pipefail

REPO_URL="${LXLITE_REPO:-https://github.com/2dust/AndroidLibXrayLite.git}"
REPO_REF="${LXLITE_REF:-main}"

echo "[clone] AndroidLibXrayLite: ${REPO_URL} @ ${REPO_REF}"

# Клонируем лёгко (depth=1) c правильной веткой (main)
if [[ -n "${REPO_REF}" ]]; then
  git clone --depth=1 --branch "${REPO_REF}" "${REPO_URL}" AndroidLibXrayLite
else
  git clone --depth=1 "${REPO_URL}" AndroidLibXrayLite
fi

cd AndroidLibXrayLite

# На практике go-пакет лежит в корне репозитория (модуль mobile).
# Проверим наличие go.mod рядом.
if [[ ! -f "go.mod" ]]; then
  echo "::error::go.mod not found at repository root"
  exit 1
fi

# --- ПАТЧ, чтобы xudp/basekey никем не устанавливался и не читался ---

# 1) Глобально выключаем XUDP на Android и гасим любые Setenv к basekey
#    (у 2dust периодически проскальзывает что-то вроде установки basekey из cache-dir).
#    Патчим все встреченные места.
git grep -n -E 'xray\.xudp|XRAY_XUDP_BASEKEY|xudp\.basekey' || true

# Мягко выпилим любые попытки установки basekey/env (оставим комментариями).
# sed работает только если такие строки встретятся — иначе просто молча пройдём.
# Патчим *.go по всему дереву.
find . -type f -name '*.go' -print0 | xargs -0 sed -i \
  -e 's/\(os\.Setenv\s*(\s*"xray\.xudp\.basekey"[^)]*)\)/\/\/ patched: \1/g' \
  -e 's/\(os\.Setenv\s*(\s*"XRAY_XUDP_BASEKEY"[^)]*)\)/\/\/ patched: \1/g' \
  -e 's/\(os\.Setenv\s*(\s*"XRAY\.XUDP\.BASEKEY"[^)]*)\)/\/\/ patched: \1/g' \
  -e 's/\(os\.Setenv\s*(\s*"xray\.xudp"\s*,\s*"on"\s*[^)]*)\)/\/\/ patched: \1/g'

# 2) Добавим guard-файл, который в рантайме жёстко выключает XUDP.
#    Файл кладём в корень модуля, пакет выбираем "mobile" (у 2dust основной pkg).
cat > xudp_guard_android.go <<'EOF'
package mobile

import (
	"os"
)

// android-only: выключаем XUDP всегда и подставляем безопасный ключ-строку,
// чтобы любые ранние проверки в go-биндингах не падали.
func init() {
	_ = os.Setenv("xray.xudp", "off")
	_ = os.Setenv("xray.xudp.show", "")
	// 32 байта в base64url (43 символа) — валидная, но не используемая строка.
	_ = os.Setenv("xray.xudp.basekey", "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8")
	_ = os.Setenv("XRAY_XUDP_BASEKEY", "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8")
	_ = os.Setenv("XRAY.XUDP.BASEKEY", "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8")
}
EOF

# На случай, если у mobile другой package-нейм, попробуем автоматически поправить.
PKG_NAME=$(go list -f '{{.Name}}' 2>/dev/null || echo "mobile")
if [[ "${PKG_NAME}" != "mobile" ]]; then
  sed -i "1s/^package .*/package ${PKG_NAME}/" xudp_guard_android.go
fi

# Выведем что получилось (для отладки в логах CI)
echo "---- patched files ----"
git status --porcelain
git diff --name-only

# Вернёмся в корень и сообщим runner-у, где лежит пакет для bind
cd ..
echo "pkg_dir=$(pwd)/AndroidLibXrayLite" >> "$GITHUB_OUTPUT"

echo "[ok] clone_and_patch completed"
